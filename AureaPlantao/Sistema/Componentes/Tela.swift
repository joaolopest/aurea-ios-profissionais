import SwiftUI

// A moldura de toda tela do app. Quem constrói tela nova usa ISTO — é o que mantém o app
// um objeto só (mesmo cabeçalho, mesma margem, mesma folga para a barra de abas, mesmo
// fundo vivo aparecendo atrás).

/// Folga inferior para a faixa "ao vivo" + barra de abas flutuantes.
enum Folga {
    static let barra: CGFloat = 170
}

/// Cabeçalho de tela: rótulo em caixa alta, título-assinatura (um por tela) e uma linha
/// de contexto opcional explicando o que a tela mostra (ADR-004 §2).
struct CabecalhoDeTela: View {
    var rotulo: String?
    let titulo: String
    var contexto: String?
    var mostrarConta = false
    @Environment(\.abrirConta) private var abrirConta
    @Environment(Sessao.self) private var sessao

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let rotulo { Text(rotulo).estiloDeRotulo() }
                Text(titulo)
                    .font(Tipo.titulo)
                    .foregroundStyle(Cor.texto)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if let contexto {
                    Text(contexto)
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            if mostrarConta {
                Button {
                    Tato.selecao()
                    abrirConta()
                } label: {
                    Iniciais(nome: sessao.eu?.perfilDetalhado?.nome ?? "AUREA", tamanho: 42)
                }
                .buttonStyle(.pressionavel)
                .accessibilityLabel("Sua conta")
            }
        }
        .padding(.top, Espaco.s)
    }
}

/// Tela rolável padrão de uma aba: NavigationStack transparente (o fundo vivo aparece),
/// margem lateral, folga da barra, puxar para atualizar com haptic.
struct TelaDeAba<Conteudo: View>: View {
    var aoAtualizar: (() async -> Void)?
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        NavigationStack {
            TelaRolavel(aoAtualizar: aoAtualizar) { conteudo }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// O miolo rolável, para telas empurradas (detalhe) ou dentro de uma `TelaDeAba`.
struct TelaRolavel<Conteudo: View>: View {
    var aoAtualizar: (() async -> Void)?
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.l) { conteudo }
                .padding(.horizontal, Espaco.margem)
                .padding(.bottom, Folga.barra)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            guard let aoAtualizar else { return }
            Tato.leve()
            await aoAtualizar()
        }
        .containerBackground(.clear, for: .navigation)
    }
}

/// Estado de carga padrão: esqueleto enquanto não há dado, erro com "tentar de novo",
/// vazio com texto próprio, e o conteúdo. Toda lista remota passa por aqui.
struct ConteudoDaCarga<Valor: Sendable, Pronto: View>: View {
    let carga: Carga<Valor>
    var linhasDeEsqueleto = 5
    var vazio: ((Valor) -> Bool)?
    var tituloVazio = "Nada aqui ainda."
    var textoVazio = ""
    var iconeVazio = "tray"
    let tentarDeNovo: () -> Void
    @ViewBuilder let pronto: (Valor) -> Pronto

    var body: some View {
        if let erro = carga.erro {
            CartaoDeErro(erro: erro, tentarDeNovo: tentarDeNovo)
                .encerraSessaoNo401(erro)
        }
        if let valor = carga.valor {
            if vazio?(valor) == true {
                EstadoVazio(titulo: tituloVazio, texto: textoVazio, icone: iconeVazio).superficie()
            } else {
                pronto(valor)
            }
        } else if carga.erro == nil {
            VStack(spacing: Espaco.s) {
                ForEach(0..<linhasDeEsqueleto, id: \.self) { _ in LinhaDeEsqueleto() }
            }
        }
    }
}

struct LinhaDeEsqueleto: View {
    var body: some View {
        HStack(spacing: 12) {
            Esqueleto(largura: 36, altura: 36)
            VStack(alignment: .leading, spacing: 8) {
                Esqueleto(largura: 150, altura: 12)
                Esqueleto(largura: 210, altura: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .superficie(raio: Raio.linha)
    }
}

/// Linha de lista padrão: ícone ou avatar à esquerda, título, apoio, e uma coluna à direita.
struct LinhaPadrao<Direita: View>: View {
    var icone: String?
    var avatar: String?
    let titulo: String
    var apoio: String?
    var mostrarSeta = true
    @ViewBuilder var direita: Direita

    var body: some View {
        HStack(spacing: 12) {
            if let avatar {
                Iniciais(nome: avatar, tamanho: 40)
            } else if let icone {
                Image(systemName: icone)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Cor.azulProfundo)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Cor.azulGelo.opacity(0.35)))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(Tipo.corpoForte).foregroundStyle(Cor.texto).lineLimit(2)
                if let apoio {
                    Text(apoio).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            direita
            if mostrarSeta {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Cor.textoFraco.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
    }
}

extension LinhaPadrao where Direita == EmptyView {
    init(icone: String? = nil, avatar: String? = nil, titulo: String, apoio: String? = nil, mostrarSeta: Bool = true) {
        self.init(icone: icone, avatar: avatar, titulo: titulo, apoio: apoio, mostrarSeta: mostrarSeta) { EmptyView() }
    }
}

/// Indicador em cartão (ADR-004 §3): rótulo acima, número grande abaixo, apoio opcional.
struct CartaoDeIndicador: View {
    let rotulo: String
    let valor: String
    var apoio: String?
    var destaque = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rotulo).estiloDeRotulo(cor: destaque ? Cor.textoInvertido.opacity(0.65) : Cor.textoFraco)
            Text(valor)
                .font(.custom("Plus Jakarta Sans", size: 30, relativeTo: .title).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(destaque ? Cor.azulGelo : Cor.texto)
                .contentTransition(.numericText())
            if let apoio {
                Text(apoio).font(Tipo.apoio)
                    .foregroundStyle(destaque ? Cor.textoInvertido.opacity(0.7) : Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Espaco.l)
        .background {
            if destaque {
                RoundedRectangle(cornerRadius: Raio.cartao, style: .continuous)
                    .fill(Cor.azulProfundo)
                    .overlay {
                        RoundedRectangle(cornerRadius: Raio.cartao, style: .continuous)
                            .fill(RadialGradient(colors: [Color(hex: 0x2C5170, opacidade: 0.6), .clear],
                                                 center: .topLeading, startRadius: 0, endRadius: 220))
                    }
                    .shadow(color: Cor.sombraAzul, radius: 14, y: 8)
            }
        }
        .modifier(SuperficieSe(ativo: !destaque))
        .accessibilityElement(children: .combine)
    }
}

private struct SuperficieSe: ViewModifier {
    let ativo: Bool
    func body(content: Content) -> some View {
        if ativo { content.superficie() } else { content }
    }
}

/// Placeholder honesto de tela que ainda não foi construída. Não é para chegar ao João.
struct EmConstrucao: View {
    let destino: Destino

    var body: some View {
        TelaDeAba {
            CabecalhoDeTela(titulo: destino.nome, contexto: destino.descricao)
            EstadoVazio(titulo: "Em construção.", texto: "Esta tela ainda não foi portada do web.", icone: destino.icone)
                .superficie()
        }
    }
}
