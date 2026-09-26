import Charts
import SwiftUI

@MainActor
@Observable
final class ToxicidadeStore {
    private(set) var carga: Carga<IndicadoresDeToxicidade> = .carregando
    /// Verdadeiro enquanto uma janela nova é buscada com o valor anterior ainda na tela.
    private(set) var atualizando = false
    var janela: Janela = .trinta
    private let api: ClienteAPI

    // `nonisolated` para a View poder criar o store no valor inicial do `@State` sem
    // arrastar o próprio init para o MainActor (`telaSecundaria` não é isolada).
    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    /// As janelas oferecidas. A API aceita 7…365; fora disso ela devolve 500, então a tela
    /// só oferece o que cabe. 30 é o padrão do web.
    enum Janela: Int, CaseIterable, Hashable {
        case sete = 7, quatorze = 14, trinta = 30, noventa = 90, ano = 365

        var titulo: String {
            self == .ano ? "12 meses" : "\(rawValue) dias"
        }
    }

    func carregar() async {
        let anterior = carga.valor
        atualizando = anterior != nil
        defer { atualizando = false }
        do {
            let valor: IndicadoresDeToxicidade = try await api.obter(
                "/painel/indicadores-de-toxicidade",
                consulta: [URLQueryItem(name: "dias", value: String(janela.rawValue))]
            )
            carga = .pronto(valor)
        } catch is CancellationError {
            // Troca de janela no meio da busca: a nova chamada assume, nada a mostrar.
        } catch {
            carga = .falhou(AcessoAnalitico.traduzir(error), anterior: anterior)
        }
    }
}

/// Indicadores de toxicidade — porta de `painel/toxicidade/page.tsx`.
///
/// Duas leituras de gestão que exigiriam abrir paciente por paciente: o que mais apareceu
/// na janela, e qual sintoma cada protocolo produz. Contagem de OPERAÇÃO: nenhuma barra
/// usa cor de faixa clínica (ADR-005), mesmo contando sintoma que passou do limiar.
struct ToxicidadeView: View {
    @State private var store = ToxicidadeStore()

    /// Explícito e `nonisolated`: `telaSecundaria` (MaisView) cria a tela fora do MainActor.
    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Painel",
                titulo: "Indicadores de toxicidade",
                contexto: "Contagem de operação, não classificação de paciente. Conta o sintoma que passou do limiar; o que ficou dentro dele não é evento de toxicidade."
            )
            // O limiar que decide "passou" é um conjunto de regras sem assinatura clínica.
            AvisoNaoValidado()

            SeletorDePilulas(
                opcoes: ToxicidadeStore.Janela.allCases.map { OpcaoDeSeletor(id: $0, titulo: $0.titulo) },
                selecionado: $store.janela
            )
            .padding(.horizontal, -Espaco.margem)
            .accessibilityLabel("Janela de tempo")

            ConteudoDaCarga(carga: store.carga, linhasDeEsqueleto: 4, tentarDeNovo: {
                Task { await store.carregar() }
            }) { dados in
                PainelDeToxicidade(dados: dados)
                    .opacity(store.atualizando ? 0.55 : 1)
                    .animation(Movimento.interface, value: store.atualizando)
            }
        }
        .task(id: store.janela) { await store.carregar() }
    }
}

// MARK: - Conteúdo

private struct PainelDeToxicidade: View {
    let dados: IndicadoresDeToxicidade

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            indicadores

            if !dados.amostraSuficiente {
                AvisoAnalitico(
                    titulo: "Amostra pequena",
                    texto: "São \(dados.totalDeSessoes) \(dados.totalDeSessoes == 1 ? "sessão" : "sessões") nos últimos \(dados.diasConsiderados) dias. Os percentuais abaixo são verdadeiros, mas variam muito com uma resposta a mais ou a menos. Leia como ordem de grandeza, não como taxa.",
                    icone: "exclamationmark.circle"
                )
            }

            BlocoAnalitico(
                titulo: "Últimos \(dados.diasConsiderados) dias",
                descricao: "Percentual sobre o total de sessões concluídas na janela, não sobre o total de sintomas.",
                indice: 1
            ) {
                if dados.taxas.isEmpty {
                    VazioAnalitico(
                        titulo: "Nenhum sintoma acima do limiar",
                        texto: "Ninguém passou do critério na janela. Vale conferir se os check-ins estão sendo respondidos."
                    )
                } else {
                    TaxasPorSintoma(dados: dados)
                }
            }

            BlocoAnalitico(
                titulo: "Ocorrências ao longo da janela",
                descricao: "Dia sem barra também é informação: vários dias seguidos sem registro num serviço ativo costumam ser falha de coleta, não ausência de sintoma.",
                indice: 2
            ) {
                SerieDeOcorrencias(dados: dados)
            }

            BlocoAnalitico(
                titulo: "Toxicidades por protocolo",
                descricao: "O sintoma que mais apareceu em cada protocolo. Muda o que a enfermagem pergunta antes de a pessoa reclamar.",
                indice: 3
            ) {
                if dados.porProtocolo.isEmpty {
                    VazioAnalitico(
                        titulo: "Sem registro por protocolo",
                        texto: "Nenhuma ocorrência na janela veio de paciente com tratamento ativo."
                    )
                } else {
                    TabelaPorProtocolo(linhas: dados.porProtocolo)
                }
            }
        }
    }

    /// Três assuntos independentes, três cartões — o primeiro em destaque, com a variação
    /// contra a janela anterior no lugar do apoio (só quando o motor diz que é comparável).
    private var indicadores: some View {
        let periodo = "últimos \(dados.diasConsiderados) dias"
        let apoioDoDestaque: String = {
            guard let v = dados.variacao else { return periodo }
            let sinal = v.percentual > 0 ? "+" : (v.percentual < 0 ? "−" : "")
            return "\(sinal)\(abs(v.percentual))% contra \(v.antes) no período anterior"
        }()
        let protocolos = dados.porProtocolo.count

        return VStack(spacing: Espaco.s) {
            CartaoDeIndicador(
                rotulo: "Sintomas acima do limiar",
                valor: "\(dados.ocorrenciasNaJanela)",
                apoio: apoioDoDestaque,
                destaque: true
            )
            HStack(alignment: .top, spacing: Espaco.s) {
                CartaoDeIndicador(rotulo: "Sessões na janela", valor: "\(dados.totalDeSessoes)", apoio: periodo)
                CartaoDeIndicador(
                    rotulo: "Protocolos com registro",
                    valor: "\(protocolos)",
                    apoio: protocolos == 1 ? "protocolo" : "protocolos"
                )
            }
        }
        .animation(Movimento.interface, value: dados)
    }
}

// MARK: - Taxas por sintoma

/// Uma barra por sintoma, na escala FIXA de 0 a 100%. Reescalar pelo maior valor faria
/// 23% parecer quase tudo; as marcas de 25, 50 e 75 transformam o trilho vazio em distância
/// até um valor que a pessoa consegue nomear.
private struct TaxasPorSintoma: View {
    let dados: IndicadoresDeToxicidade
    @State private var revelado = false

    private struct Linha: Identifiable {
        let id: String
        let nome: String
        let ocorrencias: Int
        let percentual: Int
        let indiceDeCor: Int
        let agrupadas: String?
    }

    /// No máximo cinco barras; um sexto sintoma em diante é somado em "Outras".
    private var linhas: [Linha] {
        let total = dados.totalDeSessoes
        let categorias = CategoriaAnalitica.agrupar(
            dados.taxas.map { (id: $0.sintoma.codigo, rotulo: $0.sintoma.nome, valor: $0.ocorrencias) }
        )
        return categorias.map { c in
            let percentual = c.ehOutras
                ? (total > 0 ? FormatoAnalitico.arredondarComoWeb(Double(c.valor) / Double(total) * 100) : 0)
                : (dados.taxas.first { $0.sintoma.codigo == c.id }?.percentual ?? 0)
            return Linha(
                id: c.id, nome: c.rotulo, ocorrencias: c.valor, percentual: percentual,
                indiceDeCor: c.indiceDeCor,
                agrupadas: c.ehOutras ? c.agrupadas.map { "\($0.rotulo) \($0.valor)" }.joined(separator: ", ") : nil
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            ForEach(linhas) { linha in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
                        Circle()
                            .fill(PaletaAnalitica.cor(linha.indiceDeCor))
                            .frame(width: 8, height: 8)
                        Text(linha.nome)
                            .font(Tipo.corpo)
                            .foregroundStyle(Cor.texto)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        // Colunas de largura fixa: "32%" e "5%" não têm a mesma medida, e
                        // coluna serrilhada desfaz a comparação que a peça existe para fazer.
                        Text("\(linha.percentual)%")
                            .font(Tipo.corpoForte)
                            .monospacedDigit()
                            .foregroundStyle(Cor.texto)
                            .frame(minWidth: 48, alignment: .trailing)
                        // O denominador ao lado, sempre: "40%" sozinho mente por omissão.
                        Text("\(linha.ocorrencias) de \(dados.totalDeSessoes)")
                            .font(Tipo.apoio)
                            .monospacedDigit()
                            .foregroundStyle(Cor.textoFraco)
                            .frame(minWidth: 68, alignment: .trailing)
                    }
                    BarraDePercentual(percentual: revelado ? linha.percentual : 0, cor: PaletaAnalitica.cor(linha.indiceDeCor))
                    if let agrupadas = linha.agrupadas {
                        Text(agrupadas).font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rotuloAcessivel(linha))
            }
            ReguaDePercentual()
        }
        .revelaGrafico($revelado)
        .animation(Movimento.chegada, value: linhas.map(\.percentual))
    }

    private func rotuloAcessivel(_ l: Linha) -> String {
        var texto = "\(l.nome): \(l.percentual) por cento de \(dados.totalDeSessoes) sessões, \(l.ocorrencias) \(l.ocorrencias == 1 ? "ocorrência" : "ocorrências")"
        if let agrupadas = l.agrupadas { texto += ". Inclui \(agrupadas)" }
        return texto
    }
}

/// Uma barra horizontal em Swift Charts, domínio fixo 0…100, com as marcas de quarto.
private struct BarraDePercentual: View {
    let percentual: Int
    let cor: Color

    var body: some View {
        Chart {
            ForEach([25, 50, 75], id: \.self) { marca in
                RuleMark(x: .value("Marca", marca))
                    .foregroundStyle(Cor.fileteForte)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            BarMark(
                xStart: .value("Início", 0),
                xEnd: .value("Percentual", min(percentual, 100)),
                y: .value("Sintoma", "")
            )
            .foregroundStyle(cor)
            .clipShape(Capsule())
        }
        .chartXScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { area in
            area.background(Capsule().fill(Cor.fundoBaixo))
                .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// A régua, uma vez só embaixo de todas as barras: nomeia as marcas que atravessam a pilha.
private struct ReguaDePercentual: View {
    var body: some View {
        GeometryReader { geo in
            let largura = geo.size.width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Cor.filete).frame(height: 1)
                ForEach([0, 25, 50, 75, 100], id: \.self) { marca in
                    Text("\(marca)%")
                        .font(Tipo.rotulo)
                        .monospacedDigit()
                        .foregroundStyle(Cor.textoFraco)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            let x = largura * CGFloat(marca) / 100
                            switch marca {
                            case 0: return 0
                            case 100: return d.width - x
                            default: return d.width / 2 - x
                            }
                        }
                        .padding(.top, 5)
                }
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

// MARK: - Série

/// A contagem de ocorrências por dia da janela, zeros inclusive. Em janela longa, por
/// semana: 365 barras de um ponto cada não se leem — viram textura.
private struct SerieDeOcorrencias: View {
    let dados: IndicadoresDeToxicidade
    @State private var revelado = false

    private struct Ponto: Identifiable {
        let data: Date
        let ocorrencias: Int
        var id: Date { data }
    }

    private var porSemana: Bool { dados.diasConsiderados > 60 }

    private var pontos: [Ponto] {
        let diarios = dados.serie.compactMap { p in
            FormatoAnalitico.diaCivil(p.dia).map { Ponto(data: $0, ocorrencias: p.ocorrencias) }
        }
        guard porSemana else { return diarios }
        var calendario = FormatoAnalitico.calendarioUTC
        calendario.firstWeekday = 2
        var somas: [Date: Int] = [:]
        for p in diarios {
            let inicio = calendario.dateInterval(of: .weekOfYear, for: p.data)?.start ?? p.data
            somas[inicio, default: 0] += p.ocorrencias
        }
        return somas.map { Ponto(data: $0.key, ocorrencias: $0.value) }.sorted { $0.data < $1.data }
    }

    var body: some View {
        let pontos = self.pontos
        let total = pontos.reduce(0) { $0 + $1.ocorrencias }
        let pico = pontos.max { $0.ocorrencias < $1.ocorrencias }
        let vazios = dados.serie.filter { $0.ocorrencias == 0 }.count
        let unidade: Calendar.Component = porSemana ? .weekOfYear : .day

        VStack(alignment: .leading, spacing: Espaco.m) {
            HStack(alignment: .firstTextBaseline, spacing: Espaco.xl) {
                resumo(valor: "\(total)", rotulo: total == 1 ? "ocorrência" : "ocorrências")
                if let pico, pico.ocorrencias > 0 {
                    resumo(valor: "\(pico.ocorrencias)", rotulo: porSemana
                           ? "pico · semana de \(FormatoAnalitico.dataCurta(pico.data).prefix(5))"
                           : "pico · \(FormatoAnalitico.dataCurta(pico.data).prefix(5))")
                }
                resumo(valor: "\(vazios)", rotulo: "de \(dados.serie.count) dias sem registro")
            }

            Chart(pontos) { p in
                BarMark(
                    x: .value(porSemana ? "Semana" : "Dia", p.data, unit: unidade),
                    y: .value("Ocorrências", revelado ? p.ocorrencias : 0)
                )
                .foregroundStyle(PaletaAnalitica.series[0])
                .cornerRadius(2.5)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { valor in
                    AxisGridLine().foregroundStyle(Cor.filete)
                    AxisValueLabel {
                        if let data = valor.as(Date.self) {
                            Text(String(FormatoAnalitico.dataCurta(data).prefix(5)))
                                .font(Tipo.rotulo)
                                .foregroundStyle(Cor.textoFraco)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { valor in
                    AxisGridLine().foregroundStyle(Cor.filete)
                    AxisValueLabel {
                        if let n = valor.as(Int.self) {
                            Text("\(n)").font(Tipo.rotulo).monospacedDigit().foregroundStyle(Cor.textoFraco)
                        }
                    }
                }
            }
            .frame(height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rotuloAcessivel(pontos: pontos, total: total, vazios: vazios))
        }
        .revelaGrafico($revelado)
        .animation(Movimento.chegada, value: pontos.map(\.ocorrencias))
    }

    private func resumo(valor: String, rotulo: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor)
                .font(.custom("Plus Jakarta Sans", size: 22, relativeTo: .title2).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Cor.texto)
                .contentTransition(.numericText())
            Text(rotulo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// O gráfico por extenso: só os períodos com ocorrência são lidos um a um; os vazios
    /// entram como contagem, senão o VoiceOver leria trinta "zero".
    private func rotuloAcessivel(pontos: [Ponto], total: Int, vazios: Int) -> String {
        let comRegistro = pontos.filter { $0.ocorrencias > 0 }
        let prefixo = porSemana ? "Ocorrências por semana" : "Ocorrências por dia"
        guard !comRegistro.isEmpty else {
            return "\(prefixo) nos últimos \(dados.diasConsiderados) dias: nenhuma ocorrência."
        }
        let itens = comRegistro.map { p in
            let quando = porSemana ? "semana de \(FormatoAnalitico.diaPorExtenso(p.data))" : FormatoAnalitico.diaPorExtenso(p.data)
            return "\(quando), \(p.ocorrencias)"
        }
        return "\(prefixo) nos últimos \(dados.diasConsiderados) dias. Total de \(total). " +
            itens.joined(separator: "; ") + ". \(vazios) dias sem registro."
    }
}

// MARK: - Por protocolo

private struct TabelaPorProtocolo: View {
    let linhas: [IndicadoresDeToxicidade.PorProtocolo]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Protocolo").estiloDeRotulo()
                Spacer()
                Text("Sessões").estiloDeRotulo()
            }
            .padding(.bottom, Espaco.s)
            .accessibilityHidden(true)

            ForEach(Array(linhas.enumerated()), id: \.element.protocolo) { i, linha in
                if i > 0 { Rectangle().fill(Cor.filete).frame(height: 1) }
                HStack(alignment: .center, spacing: Espaco.m) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(linha.protocolo)
                            .font(Tipo.corpoForte)
                            .foregroundStyle(Cor.texto)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(linha.sintomaMaisFrequente?.nome ?? "nenhum")
                                .foregroundStyle(Cor.textoSuave)
                            Text("\(linha.ocorrenciasDoMaisFrequente)×")
                                .monospacedDigit()
                                .foregroundStyle(Cor.textoFraco)
                        }
                        .font(Tipo.apoio)
                    }
                    Spacer(minLength: 8)
                    // Asterisco, não a frase repetida: aviso que aparece em toda linha deixa
                    // de ser aviso. A nota embaixo explica uma vez.
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(linha.totalDeSessoes)")
                            .font(Tipo.corpoForte)
                            .monospacedDigit()
                            .foregroundStyle(Cor.texto)
                        if !linha.amostraSuficiente {
                            Text("*").font(Tipo.apoio).foregroundStyle(Cor.textoFraco).baselineOffset(5)
                        }
                    }
                }
                .padding(.vertical, Espaco.m)
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rotuloAcessivel(linha))
            }

            // A nota só existe quando há linha marcada: legenda de algo que não está na
            // tela é ruído que ensina a ignorar legenda.
            if linhas.contains(where: { !$0.amostraSuficiente }) {
                Text("* Amostra pequena: poucas sessões no período para ler como tendência. O número está certo; o que ele sugere ainda não se sustenta.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoFraco)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Espaco.s)
            }
        }
    }

    private func rotuloAcessivel(_ l: IndicadoresDeToxicidade.PorProtocolo) -> String {
        let sintoma = l.sintomaMaisFrequente.map { "sintoma mais frequente \($0.nome), \(l.ocorrenciasDoMaisFrequente) vezes" }
            ?? "nenhum sintoma mais frequente"
        return "\(l.protocolo): \(sintoma), em \(l.totalDeSessoes) \(l.totalDeSessoes == 1 ? "sessão" : "sessões")"
            + (l.amostraSuficiente ? "" : ", amostra pequena")
    }
}

// MARK: - Vazio dentro de bloco

/// Vazio que mora dentro de um bloco já emoldurado: sem segunda superfície por cima.
struct VazioAnalitico: View {
    let titulo: String
    let texto: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
            Text(texto)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Espaco.l)
        .superficie(.afundado, raio: Raio.linha)
        .accessibilityElement(children: .combine)
    }
}
