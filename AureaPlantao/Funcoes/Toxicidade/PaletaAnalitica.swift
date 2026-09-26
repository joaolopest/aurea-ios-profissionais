import SwiftUI

// Peças compartilhadas pelas duas telas analíticas do painel (Toxicidade e Navegação).
// Moram aqui, e não em `Sistema/`, porque só estas duas telas desenham gráfico hoje; quando
// uma terceira precisar, o lugar certo passa a ser o sistema — ver o relatório da porta.

/// A paleta de DADO do ADR-005, sem o petróleo-teal (no app ele é lido como verde, e verde
/// é faixa clínica). Cor sai por ÍNDICE, nunca escolhida por "combina com o assunto": quem
/// quiser pintar uma barra de vermelho vai ter que editar isto e ler o porquê.
///
/// 🔴 Nenhuma cor de `Faixa` entra em gráfico (ADR-005, regra 2). Contagem de operação não é
/// classificação de paciente, mesmo quando conta sintoma amarelo ou vermelho.
enum PaletaAnalitica {
    static let series: [Color] = [
        Color(hex: 0x35597F), // azul-aço
        Color(hex: 0x4C4A86), // índigo
        Color(hex: 0x74477A), // ameixa
        Color(hex: 0x8A4668), // vinho-rosa
    ]
    /// A quinta série — ou "Outras", o excedente agrupado. Tom neutro, e UM só: repetir cor
    /// faria duas categorias diferentes ficarem idênticas (ADR-005, regra 5).
    static let outras = Color(hex: 0x6F6F72)

    /// Séries com cor própria. A quinta leva o neutro; da sexta em diante, tudo vira "Outras".
    static let maximoDeSeries = 4

    static func cor(_ indice: Int) -> Color {
        indice < maximoDeSeries ? series[indice] : outras
    }
}

/// Uma categoria pronta para gráfico: rótulo, valor e a cor já decidida pelo índice.
struct CategoriaAnalitica: Identifiable, Equatable {
    let id: String
    let rotulo: String
    let valor: Int
    let indiceDeCor: Int
    /// Quando é o balde "Outras", o que foi agrupado nele, por extenso — o número não some.
    var agrupadas: [(rotulo: String, valor: Int)] = []

    var cor: Color { PaletaAnalitica.cor(indiceDeCor) }
    var ehOutras: Bool { !agrupadas.isEmpty }

    static func == (a: CategoriaAnalitica, b: CategoriaAnalitica) -> Bool {
        a.id == b.id && a.valor == b.valor && a.indiceDeCor == b.indiceDeCor
    }

    /// Mantém as `maximoDeSeries` primeiras com cor própria e soma o resto em "Outras".
    /// Uma categoria sozinha no excedente não vira "Outras": agrupar uma só esconde o nome
    /// dela sem ganhar nada — ela entra com o neutro e o próprio nome.
    static func agrupar(_ itens: [(id: String, rotulo: String, valor: Int)]) -> [CategoriaAnalitica] {
        let teto = PaletaAnalitica.maximoDeSeries
        guard itens.count > teto + 1 else {
            return itens.enumerated().map { i, x in
                CategoriaAnalitica(id: x.id, rotulo: x.rotulo, valor: x.valor, indiceDeCor: min(i, teto))
            }
        }
        let principais = itens.prefix(teto).enumerated().map { i, x in
            CategoriaAnalitica(id: x.id, rotulo: x.rotulo, valor: x.valor, indiceDeCor: i)
        }
        let resto = itens.dropFirst(teto)
        let outras = CategoriaAnalitica(
            id: "__outras__", rotulo: "Outras",
            valor: resto.reduce(0) { $0 + $1.valor }, indiceDeCor: teto,
            agrupadas: resto.map { ($0.rotulo, $0.valor) }
        )
        return principais + [outras]
    }
}

/// O cartão que abriga um bloco analítico: título, descrição que diz o que o número mede,
/// e o conteúdo. Entra subindo, como as linhas — a tela monta em cascata, não de uma vez.
struct BlocoAnalitico<Conteudo: View>: View {
    let titulo: String
    var descricao: String?
    var indice = 0
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo)
                    .font(Tipo.tituloDeBloco)
                    .foregroundStyle(Cor.texto)
                    .accessibilityAddTraits(.isHeader)
                if let descricao {
                    Text(descricao)
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            conteudo
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Espaco.l)
        .superficie()
        .entradaEscalonada(indice)
    }
}

/// Aviso de leitura (amostra pequena, comparação indisponível). Neutro de propósito:
/// é nota de interpretação, não alerta clínico — âmbar aqui seria lido como paciente amarelo.
struct AvisoAnalitico: View {
    let titulo: String
    let texto: String
    var icone = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cor.azulProfundo)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(Tipo.apoioForte).foregroundStyle(Cor.texto)
                Text(texto)
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Espaco.l)
        .superficie(.afundado, raio: Raio.linha)
        .accessibilityElement(children: .combine)
    }
}

/// Crescimento das barras na chegada. As barras nascem do zero e crescem até o valor —
/// o olho acompanha a comparação em vez de receber um bloco pronto. Reduce Motion: nasce pronto.
struct RevelacaoDeGrafico: ViewModifier {
    @Binding var revelado: Bool
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    func body(content: Content) -> some View {
        content.onAppear {
            guard !revelado else { return }
            if reduzirMovimento {
                revelado = true
            } else {
                withAnimation(Movimento.chegada.delay(0.12)) { revelado = true }
            }
        }
    }
}

extension View {
    func revelaGrafico(_ revelado: Binding<Bool>) -> some View {
        modifier(RevelacaoDeGrafico(revelado: revelado))
    }
}

enum AcessoAnalitico {
    /// A API responde o 403 com `{ "erro": … }`, e o cliente só lê `mensagem`/`message` —
    /// então chega aqui como "recusou o pedido (403)". A tela troca por uma frase honesta
    /// sobre o acesso, em vez de parecer quebrada.
    static func traduzir(_ erro: Error) -> ErroDaAPI {
        let e = ErroDaAPI(erro)
        if case .recusado(let m) = e, m.contains("(403)") {
            return .recusado("Seu acesso não inclui os indicadores do painel. Eles pedem permissão de plantão ou de histórico de paciente — fale com a coordenação.")
        }
        return e
    }
}

enum FormatoAnalitico {
    static let local = Locale(identifier: "pt_BR")

    /// `AAAA-MM-DD` como dia civil. Ancorado ao meio-dia UTC e lido em UTC: nenhum fuso
    /// faz o dia escorregar (a meia-noite UTC em Brasília é 21 h do dia anterior).
    static func diaCivil(_ texto: String) -> Date? {
        let partes = texto.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard partes.count == 3 else { return nil }
        var c = DateComponents()
        c.year = partes[0]; c.month = partes[1]; c.day = partes[2]; c.hour = 12
        return calendarioUTC.date(from: c)
    }

    static let calendarioUTC: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = local
        return c
    }()

    /// "26/09/2026"
    static func dataCurta(_ data: Date) -> String {
        var f = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year().locale(local)
        f.timeZone = TimeZone(identifier: "UTC")!
        return data.formatted(f)
    }

    /// "29 de agosto" — para leitor de tela.
    static func diaPorExtenso(_ data: Date) -> String {
        var f = Date.FormatStyle.dateTime.day().month(.wide).locale(local)
        f.timeZone = TimeZone(identifier: "UTC")!
        return data.formatted(f)
    }

    /// Minutos viram hora quando passam de 90: "184 minutos" não é lido, é convertido.
    static func duracao(_ minutos: Int?) -> String {
        guard let minutos else { return "sem registro" }
        if minutos < 90 { return "\(minutos) min" }
        let horas = minutos / 60, resto = minutos % 60
        return resto == 0 ? "\(horas) h" : "\(horas) h \(resto) min"
    }

    /// Arredondamento do `Math.round` do web (meio vai para cima, inclusive no negativo),
    /// para o app e o web mostrarem a mesma variação.
    static func arredondarComoWeb(_ v: Double) -> Int {
        Int((v + 0.5).rounded(.down))
    }
}
