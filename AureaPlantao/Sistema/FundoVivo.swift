import SwiftUI
import UIKit

/// O fundo do app: manchas de luz borradas derivando devagar sobre o cinza do sistema,
/// com um grão fino de papel por cima.
///
/// Vem do BT Professor (a "aurora" sobre a quadra à noite), traduzido para o claro:
/// lá a luz acende o preto; aqui ela dá matéria ao cinza — e é ela que o vidro da barra
/// de abas refrata. Sem ela o material translúcido desfoca cinza liso e parece opaco.
///
/// 🔴 Lei clínica: a aurora só usa AZUIS — céu, aço, índigo. Nada que puxe para verde,
/// amarelo ou vermelho (o lima saiu por isso: sobre o cinza ele é lido como verde). Nunca vermelho, âmbar ou verde de faixa: uma mancha vermelha
/// no fundo do plantão seria lida como alerta.
///
/// Movimento preso ao relógio (`TimelineView`), não a `onAppear` + `repeatForever`, para
/// a deriva viver igual em qualquer aba. Reduce Motion congela a deriva; a luz fica.
struct FundoVivo: View {
    var tom: Color = Cor.auroraCeu
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    private struct Mancha {
        let raio: CGFloat
        let base: CGPoint
        let deriva: CGSize
        let opacidade: Double
        let periodo: Double
        let fase: Double
        /// A segunda mancha é sempre o azul da marca — ancora o tom da aba na identidade.
        let daMarca: Bool
    }

    // Períodos primos entre si: o movimento composto nunca "bate".
    private let manchas: [Mancha] = [
        Mancha(raio: 1.3, base: .init(x: -0.30, y: -0.20), deriva: .init(width: 0.28, height: 0.14),
               opacidade: 0.95, periodo: 19, fase: 0, daMarca: false),
        Mancha(raio: 1.0, base: .init(x: 0.45, y: 0.38), deriva: .init(width: -0.22, height: -0.14),
               opacidade: 0.14, periodo: 23, fase: 1.7, daMarca: true),
        Mancha(raio: 1.0, base: .init(x: 0.05, y: 0.72), deriva: .init(width: 0.24, height: -0.14),
               opacidade: 0.60, periodo: 29, fase: 3.4, daMarca: false),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Cor.fundo
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduzirMovimento)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(manchas.indices, id: \.self) { i in
                            mancha(manchas[i], t: t, w: w, h: h)
                        }
                    }
                }
                Grao.camada
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mancha(_ m: Mancha, t: Double, w: CGFloat, h: CGFloat) -> some View {
        let r = w * m.raio
        let f = 2 * .pi * t / m.periodo + m.fase
        // Deriva elíptica: X e Y defasados em um quarto de ciclo, senão vira vaivém reto.
        let x = w * m.base.x + w * m.deriva.width * 0.5 * (1 + sin(f))
        let y = h * m.base.y + h * m.deriva.height * 0.5 * (1 + sin(f + .pi / 2))
        let cor = m.daMarca ? Cor.azulProfundo : tom
        return Circle()
            .fill(RadialGradient(colors: [cor.opacity(m.opacidade), .clear],
                                 center: .center, startRadius: 0, endRadius: r / 2))
            .frame(width: r, height: r)
            .blur(radius: 40)
            .offset(x: x, y: y)
    }
}

/// Grão de papel. Gerado UMA vez em 128×128 com semente fixa e repetido em ladrilho —
/// nada no bundle, nada recalculado por quadro, igual em todo aparelho.
@MainActor
enum Grao {
    static let camada: some View = Image(uiImage: ladrilho)
        .resizable(resizingMode: .tile)
        .opacity(0.035)
        .blendMode(.multiply)
        .ignoresSafeArea()

    private static let ladrilho: UIImage = {
        let lado = 128
        var semente: UInt64 = 0x9E3779B97F4A7C15
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: lado, height: lado), format: formato).image { ctx in
            for y in 0..<lado {
                for x in 0..<lado {
                    semente = semente &* 6364136223846793005 &+ 1442695040888963407
                    let v = CGFloat((semente >> 33) & 0xFF) / 255
                    UIColor(white: v, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }()
}
