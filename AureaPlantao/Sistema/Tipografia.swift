import SwiftUI

/// Tipografia. Plus Jakarta Sans para tudo que é texto, IBM Plex Mono só para coluna.
///
/// Regra do ADR-006 (Onda 2): mono não entra em frase corrida. Em monoespaçada a vírgula
/// e o espaço têm a largura de um dígito, e `38,9 °C` dentro de uma frase sai esgarçado.
/// Em frase, número vai na sans com `tabular`. Mono é para alinhar coluna — horário,
/// protocolo, ciclo.
///
/// Todo tamanho escala com o Dynamic Type (`relativeTo:`). A escala abaixo nomeia o
/// PAPEL de cada tamanho, como o web faz, e não o número.
enum Tipo {
    private static let sans = "Plus Jakarta Sans"
    private static let mono = "IBMPlexMono"

    /// O número-herói do plantão: "3". Só um por tela.
    static let heroi = Font.custom(sans, size: 64, relativeTo: .largeTitle).weight(.bold)
    /// A assinatura da tela — um `h1` por tela, como o `.titulo` do web.
    static let titulo = Font.custom(sans, size: 30, relativeTo: .largeTitle).weight(.bold)
    static let tituloDeBloco = Font.custom(sans, size: 19, relativeTo: .title3).weight(.semibold)
    static let destaque = Font.custom(sans, size: 17, relativeTo: .headline).weight(.semibold)
    static let corpo = Font.custom(sans, size: 16, relativeTo: .body)
    static let corpoForte = Font.custom(sans, size: 16, relativeTo: .body).weight(.semibold)
    static let apoio = Font.custom(sans, size: 14, relativeTo: .subheadline)
    static let apoioForte = Font.custom(sans, size: 14, relativeTo: .subheadline).weight(.semibold)
    /// Rótulo em caixa alta com tracking aberto. Sempre com `.tracking(Tipo.trackingDeRotulo)`.
    static let rotulo = Font.custom(sans, size: 11.5, relativeTo: .caption).weight(.bold)
    static let trackingDeRotulo: CGFloat = 0.9

    static let coluna = Font.custom("\(mono)-Regular", size: 13, relativeTo: .footnote)
    static let colunaForte = Font.custom("\(mono)-Medium", size: 13, relativeTo: .footnote)
}

extension View {
    /// Rótulo de seção: caixa alta, tracking aberto, cor fraca.
    func estiloDeRotulo(cor: Color = Cor.textoFraco) -> some View {
        font(Tipo.rotulo)
            .tracking(Tipo.trackingDeRotulo)
            .textCase(.uppercase)
            .foregroundStyle(cor)
    }
}
