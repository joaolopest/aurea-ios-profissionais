import SwiftUI
import UIKit

/// Uma mola para o app inteiro. Massa e amortecimento iguais em toda parte é o que faz o
/// app parecer UM objeto — curva diferente por tela é como o acabamento se desfaz.
///
/// A regra do web vale aqui: o que sai é sempre mais rápido do que o que chega.
enum Movimento {
    /// Padrão: troca de estado, abrir, reordenar.
    static let interface = Animation.spring(response: 0.35, dampingFraction: 0.86)
    /// O que chega na tela.
    static let chegada = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// O que sai. Mais rápido, sem quique.
    static let partida = Animation.spring(response: 0.24, dampingFraction: 1)
    /// Resposta ao toque — realce sob o dedo.
    static let toque = Animation.spring(response: 0.18, dampingFraction: 0.9)
}

/// Vocabulário de haptics. Cada evento tem o seu, sempre o mesmo — é linguagem, não enfeite.
///
/// | Evento                          | Haptic          |
/// |---------------------------------|-----------------|
/// | troca de filtro ou de aba       | seleção         |
/// | atendimento registrado          | sucesso         |
/// | outra pessoa já atendeu (409)   | aviso           |
/// | puxar pra atualizar             | impacto leve    |
/// | erro que impede a ação          | erro            |
@MainActor
enum Tato {
    static func selecao() { UISelectionFeedbackGenerator().selectionChanged() }
    static func sucesso() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func aviso() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func erro() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func leve() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// Botão que afunda sob o dedo, com um toque leve de haptic no momento do aperto.
///
/// A háptica mora AQUI, no estilo, e não num `TapGesture` sobre o rótulo: um gesto
/// competindo com o `Button` engole o toque e mata a ação (lição do BT Professor).
struct EstiloPressionavel: ButtonStyle {
    var escala: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? escala : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, apertado in
                if apertado { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6) }
            }
    }
}

/// Entrada de item de lista: sobe 14 pt e aparece, com atraso por índice.
/// O atraso tem teto — linhas que entram por rolagem não podem esperar.
struct EntradaEscalonada: ViewModifier {
    let indice: Int
    @State private var visivel = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    func body(content: Content) -> some View {
        content
            .opacity(visivel ? 1 : 0)
            .offset(y: visivel || reduzirMovimento ? 0 : 14)
            .onAppear {
                guard !visivel else { return }
                let atraso = reduzirMovimento ? 0 : Double(min(indice, 8)) * 0.045
                withAnimation(reduzirMovimento ? .easeOut(duration: 0.15) : Movimento.chegada.delay(atraso)) {
                    visivel = true
                }
            }
    }
}

extension View {
    func entradaEscalonada(_ indice: Int) -> some View {
        modifier(EntradaEscalonada(indice: indice))
    }
}

extension ButtonStyle where Self == EstiloPressionavel {
    static var pressionavel: EstiloPressionavel { EstiloPressionavel() }
}
