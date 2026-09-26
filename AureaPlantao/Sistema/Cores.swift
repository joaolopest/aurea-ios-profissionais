import SwiftUI

/// Paleta do AUREA Plantão. Espelha `apps/web/src/app/globals.css` — o mesmo produto, a mesma cor.
///
/// Duas famílias, e elas não se misturam (ADR-004 e ADR-005):
///
/// - `Cor.*` é a marca e a estrutura: azul petróleo, lima, neutros, texto.
/// - `Faixa.*` é CLASSIFICAÇÃO CLÍNICA. Verde, amarelo, vermelho e silêncio significam
///   gravidade de paciente e nada mais. Um botão, um ícone ou um gráfico com essas cores
///   ensina a enfermeira a ignorar o vermelho — e o vermelho é o único sinal que importa.
///
/// Por isso `Faixa` não expõe as cores soltas: só se chega nelas a partir de uma
/// `SituacaoClinica`. Quem quiser pintar um botão de vermelho vai ter que passar por aqui
/// e ler este comentário.
enum Cor {
    // Marca
    static let azulProfundo = Color(hex: 0x0E2739)
    static let azulProfundoAlto = Color(hex: 0x091D2A)
    /// Azul do `hover` do web, usado aqui como estado pressionado. Nunca verde (ADR-006, achado 1).
    static let azulPressionado = Color(hex: 0x1A3A52)
    /// Lima da landing. FORA do app: sobre o cinza e o azul ele é lido como verde, e
    /// verde é faixa clínica (decisão do João, 25/09/2026). Fica aqui só para ninguém
    /// reintroduzir por engano sem ler isto.
    @available(*, deprecated, message: "Lima lê como verde no app — use Cor.azulGelo / Cor.azulProfundo.")
    static let lima = Color(hex: 0xDFF178)

    /// O acento que acende: número-herói e brilhos sobre o azul profundo.
    static let azulGelo = Color(hex: 0xA9D4FF)
    /// Tons da aurora do fundo — só azuis, longe de qualquer faixa clínica.
    static let auroraCeu = Color(hex: 0x8FC3F2)
    static let auroraAco = Color(hex: 0x7FA7CF)
    static let auroraIndigo = Color(hex: 0x9C9EE0)
    /// Sombra tingida para o que é preenchido de azul profundo.
    static let sombraAzul = Color(hex: 0x0E2739, opacidade: 0.28)

    // Fundo do sistema da equipe (neutro, não o creme da landing)
    static let fundo = Color(hex: 0xF6F6F6)
    static let fundoBaixo = Color(hex: 0xECECEC)
    static let fundoFundo = Color(hex: 0xE3E3E3)
    static let superficie = Color.white

    // Texto — tinta esverdeada escura do web, nunca preto puro
    static let texto = Color(hex: 0x14201A)
    static let textoSuave = Color(hex: 0x4A5A4E)
    static let textoFraco = Color(hex: 0x7D8A80)
    static let textoInvertido = Color(hex: 0xF4F1E2)

    /// A tinta das sombras e filetes. Sombra preta sobre o fundo acinzenta; tinta sombreia.
    static let tinta = Color(red: 20 / 255, green: 32 / 255, blue: 26 / 255)
    static let filete = tinta.opacity(0.07)
    static let fileteForte = tinta.opacity(0.14)
}

/// A escala clínica. Só existe a partir de uma situação de paciente.
enum Faixa {
    struct Tons {
        let tinta: Color
        let fundo: Color
    }

    static func tons(_ situacao: SituacaoClinica) -> Tons {
        switch situacao {
        case .vermelho: Tons(tinta: Color(hex: 0xA3341F), fundo: Color(hex: 0xF7E2DC))
        case .amarelo: Tons(tinta: Color(hex: 0xA8701F), fundo: Color(hex: 0xF9EDD8))
        case .verde: Tons(tinta: Color(hex: 0x5D7040), fundo: Color(hex: 0xEEF1E2))
        case .silencio: Tons(tinta: Color(hex: 0x6B7A70), fundo: Color(hex: 0xECEEE9))
        }
    }
}

extension Color {
    init(hex: UInt32, opacidade: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacidade
        )
    }
}
