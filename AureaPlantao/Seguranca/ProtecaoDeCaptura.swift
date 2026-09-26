import SwiftUI
import UIKit

/// Conteúdo que não sai em captura de tela nem em gravação/espelhamento.
///
/// O iOS não tem API pública para "bloquear screenshot". O que existe é o comportamento
/// do campo de senha: o sistema apaga o conteúdo de um `UITextField` seguro de qualquer
/// captura. Hospedar a view dentro da camada desse campo herda a proteção — na captura, o
/// prontuário sai em branco.
///
/// É a técnica que apps de banco usam. Se um dia a Apple mudar a hierarquia interna do
/// campo, o fallback é mostrar o conteúdo normalmente — nunca esconder da própria enfermeira.
struct ProtegidoDeCaptura<Conteudo: View>: UIViewRepresentable {
    let conteudo: Conteudo

    init(@ViewBuilder conteudo: () -> Conteudo) {
        self.conteudo = conteudo()
    }

    func makeUIView(context: Context) -> UIView {
        let campo = UITextField()
        campo.isSecureTextEntry = true
        campo.isUserInteractionEnabled = false

        let hospedeiro = UIHostingController(rootView: conteudo)
        hospedeiro.sizingOptions = []
        hospedeiro.view.backgroundColor = .clear
        hospedeiro.view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.hospedeiro = hospedeiro

        // A subview do campo seguro que o sistema oculta na captura.
        guard let camadaSegura = campo.subviews.first else {
            return hospedeiro.view
        }
        camadaSegura.subviews.forEach { $0.removeFromSuperview() }
        camadaSegura.isUserInteractionEnabled = true

        // Contêiner comum: o SwiftUI dimensiona ELE (pelo frame), e a camada segura
        // acompanha por autoresizing. Pôr constraints na camada direto desligava o frame
        // que o SwiftUI aplica — o prontuário transbordava e era cortado.
        let conteiner = UIView()
        conteiner.backgroundColor = .clear
        camadaSegura.frame = conteiner.bounds
        camadaSegura.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        conteiner.addSubview(camadaSegura)

        camadaSegura.addSubview(hospedeiro.view)
        NSLayoutConstraint.activate([
            hospedeiro.view.topAnchor.constraint(equalTo: camadaSegura.topAnchor),
            hospedeiro.view.bottomAnchor.constraint(equalTo: camadaSegura.bottomAnchor),
            hospedeiro.view.leadingAnchor.constraint(equalTo: camadaSegura.leadingAnchor),
            hospedeiro.view.trailingAnchor.constraint(equalTo: camadaSegura.trailingAnchor),
        ])
        return conteiner
    }

    /// Ocupa exatamente o espaço proposto. Sem isto o SwiftUI pergunta o tamanho à camada
    /// segura, que não tem tamanho próprio, e o conteúdo transbordava para a direita e
    /// era cortado embaixo.
    func sizeThatFits(_ proposta: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        proposta.replacingUnspecifiedDimensions()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hospedeiro?.rootView = conteudo
    }

    func makeCoordinator() -> Coordenador { Coordenador() }

    final class Coordenador {
        var hospedeiro: UIHostingController<Conteudo>?
    }
}
