import SwiftUI

/// Material e elevação — o ADR-006 traduzido para SwiftUI.
///
/// Cinco níveis nomeados por USO. Cada um carrega as três coisas juntas: sombra em
/// camadas (contato · forma), em tinta e nunca preto, e luz no topo — o filete claro
/// na quina de cima que faz o olho ler "objeto sob uma luz" em vez de "área pintada".
enum Elevacao {
    case plano
    case apoiado
    case erguido
    case flutuante
    case afundado
}

enum Raio {
    static let cartao: CGFloat = 20
    static let linha: CGFloat = 16
    static let controle: CGFloat = 14
    static let pilula: CGFloat = 999
}

enum Espaco {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Margem lateral das telas.
    static let margem: CGFloat = 20
}

private struct Superficie: ViewModifier {
    let elevacao: Elevacao
    let raio: CGFloat
    let preenchimento: Color

    func body(content: Content) -> some View {
        let forma = RoundedRectangle(cornerRadius: raio, style: .continuous)

        content
            .background {
                switch elevacao {
                case .afundado:
                    forma
                        .fill(Cor.fundoBaixo)
                        .overlay {
                            // Luz invertida: escuro no topo, claro embaixo.
                            forma.strokeBorder(
                                LinearGradient(
                                    colors: [Cor.tinta.opacity(0.10), .white.opacity(0.7)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        }
                default:
                    forma
                        .fill(preenchimento)
                        .overlay { forma.strokeBorder(Cor.tinta.opacity(opacidadeDoFilete), lineWidth: 0.75) }
                        .overlay(alignment: .top) {
                            // A luz no topo: 1pt branco colado na quina superior.
                            forma
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white, .white.opacity(0)],
                                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.08)
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: Cor.tinta.opacity(contato.opacidade), radius: contato.raio, y: contato.y)
                        .shadow(color: Cor.tinta.opacity(forma1.opacidade), radius: forma1.raio, y: forma1.y)
                }
            }
    }

    private var opacidadeDoFilete: Double {
        switch elevacao {
        case .plano, .apoiado: 0.07
        case .erguido: 0.09
        case .flutuante: 0.10
        case .afundado: 0.06
        }
    }

    private typealias Sombra = (opacidade: Double, raio: CGFloat, y: CGFloat)

    private var contato: Sombra {
        switch elevacao {
        case .plano, .afundado: (0, 0, 0)
        case .apoiado: (0.04, 0.5, 1)
        case .erguido: (0.05, 1, 1)
        case .flutuante: (0.05, 2, 2)
        }
    }

    private var forma1: Sombra {
        switch elevacao {
        case .plano, .afundado: (0, 0, 0)
        case .apoiado: (0.05, 5, 3)
        case .erguido: (0.09, 10, 6)
        case .flutuante: (0.14, 28, 18)
        }
    }
}

extension View {
    func superficie(
        _ elevacao: Elevacao = .apoiado,
        raio: CGFloat = Raio.cartao,
        preenchimento: Color = Cor.superficie
    ) -> some View {
        modifier(Superficie(elevacao: elevacao, raio: raio, preenchimento: preenchimento))
    }
}

extension View {
    /// Cartão de destaque (BT Professor, traduzido): a cor do assunto acende no canto
    /// superior e tinge a borda de leve. Um por tela — dois destaques é nenhum.
    func cartaoDestaque(tom: Color = Cor.auroraCeu, raio: CGFloat = Raio.cartao) -> some View {
        let forma = RoundedRectangle(cornerRadius: raio, style: .continuous)
        return background {
            ZStack {
                forma.fill(Cor.superficie)
                forma.fill(RadialGradient(colors: [tom.opacity(0.30), tom.opacity(0)],
                                          center: .topLeading, startRadius: 4, endRadius: 280))
            }
            .shadow(color: Cor.tinta.opacity(0.04), radius: 1, y: 1)
            .shadow(color: Cor.tinta.opacity(0.07), radius: 14, y: 8)
        }
        .overlay {
            forma.strokeBorder(
                LinearGradient(colors: [.white, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        }
        .overlay { forma.strokeBorder(tom.opacity(0.35), lineWidth: 0.5) }
    }
}
