import SwiftUI

// Contrato do giro de cadeiras (`apps/api/src/rotas/cadeiras.ts`), modelado a partir das
// respostas REAIS conferidas com curl em 25/09/2026 — não do tipo do web.
//
// Surpresas contra o TypeScript (`packages/contratos/src/giro-de-cadeiras.ts`):
// - `cadeira` traz também `observacao` e `criadaEm` (o tipo do web só declara id, número, ativa).
// - `sessoesDoDia[]` traz `pacienteId`, que o tipo `SessaoNaCadeira` não declara.
// - A `observacao` da SESSÃO é gravada no POST mas não volta em nenhuma leitura do painel;
//   por isso o app não oferece o campo (seria escrever num lugar que ninguém lê).
// - O erro da API vem em `{ "erro": … }`, não em `message`/`mensagem`.

// MARK: - GET /painel/cadeiras

struct PainelDeCadeiras: Decodable, Sendable {
    let giro: GiroDasCadeiras
    let janelasLivres: [JanelaLivreDeCadeira]
    let sessoesDoDia: [SessaoDeCadeira]
    let expediente: ExpedienteDoGiro
}

struct GiroDasCadeiras: Decodable, Sendable {
    let total: Int
    let ocupadas: Int
    let emPreparo: Int
    let aguardandoMedicacao: Int
    let emObservacao: Int
    let disponiveis: Int
    /// 0 a 100, já arredondado pela API. Conta como ocupada tudo que não está disponível.
    let taxaDeOcupacao: Int
    /// Nulo quando nenhuma sessão de hoje começou E terminou.
    let tempoMedioDeOcupacaoEmMinutos: Int?
    /// Nulo quando já existe cadeira livre — a resposta é "agora".
    let proximaCadeiraLivreEm: Date?
    let atrasoAcumuladoEmMinutos: Int
    let porCadeira: [OcupacaoDeCadeira]

    func quantas(_ estado: EstadoDaCadeira) -> Int {
        switch estado {
        case .disponivel: disponiveis
        case .aguardandoMedicacao: aguardandoMedicacao
        case .emPreparo: emPreparo
        case .ocupada: ocupadas
        case .emObservacao: emObservacao
        case .desconhecido(let bruto): porCadeira.filter { $0.estado.bruto == bruto }.count
        }
    }
}

struct OcupacaoDeCadeira: Decodable, Sendable, Identifiable, Hashable {
    let cadeira: CadeiraDoGiro
    let estado: EstadoDaCadeira
    let sessaoAtual: SessaoDeCadeira?
    /// É o `previsaoDeFim` da sessão atual. A API NÃO recalcula pelo início real: sessão
    /// que começou atrasada continua com a liberação prevista antiga.
    let livreEm: Date?

    var id: String { cadeira.id }
}

struct CadeiraDoGiro: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let numero: Int
    let ativa: Bool
    let observacao: String?
    let criadaEm: Date
}

struct SessaoDeCadeira: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let paciente: String
    let pacienteId: String
    let cadeiraId: String?
    let protocolo: String?
    let estado: EstadoDaSessao
    let previsaoDeInicio: Date
    let previsaoDeFim: Date
    let inicioReal: Date?
    let fimReal: Date?
    let medicacaoLiberadaEm: Date?
}

struct JanelaLivreDeCadeira: Decodable, Sendable, Hashable, Identifiable {
    let cadeiraId: String
    let numero: Int
    let de: Date
    let ate: Date
    let minutos: Int

    var id: String { "\(cadeiraId)-\(de.timeIntervalSince1970)" }
}

struct ExpedienteDoGiro: Decodable, Sendable, Hashable {
    let abertura: Date
    let fechamento: Date
}

// MARK: - GET /painel/cadeiras/previsao/:pacienteId

struct PrevisaoDeOcupacao: Decodable, Sendable, Hashable {
    let paciente: Paciente
    let protocolo: String
    let complexidade: ComplexidadeDoPaciente
    let ocupacao: ComposicaoDaOcupacao

    struct Paciente: Decodable, Sendable, Hashable {
        let id: String
        let nome: String
    }
}

struct ComposicaoDaOcupacao: Decodable, Sendable, Hashable {
    let preparo: Int
    let preMedicacao: Int
    let infusao: Int
    let observacao: Int
    let virada: Int
    let total: Int
}

// MARK: - Escritas

/// Resposta do `POST /painel/cadeiras` (201 — inclusive quando a cadeira já existia: é upsert).
typealias CadeiraGravada = CadeiraDoGiro

/// Resposta do `POST /painel/cadeiras/sessoes` (201, com `ocupacao`) e do
/// `PATCH /painel/cadeiras/sessoes/:id` (200, sem `ocupacao`). Só o que o app confere.
struct SessaoGravada: Decodable, Sendable {
    let id: String
    let cadeiraId: String?
    let estado: EstadoDaSessao
    let previsaoDeInicio: Date
    let previsaoDeFim: Date
    let inicioReal: Date?
    let fimReal: Date?
    let ocupacao: ComposicaoDaOcupacao?
}

// MARK: - Enums com saída para o desconhecido

/// Estado da POLTRONA, derivado pela API do estado da sessão que a ocupa.
enum EstadoDaCadeira: Decodable, Sendable, Hashable {
    case disponivel, aguardandoMedicacao, emPreparo, ocupada, emObservacao
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        let bruto = try decoder.singleValueContainer().decode(String.self)
        switch bruto {
        case "DISPONIVEL": self = .disponivel
        case "AGUARDANDO_MEDICACAO": self = .aguardandoMedicacao
        case "EM_PREPARO": self = .emPreparo
        case "OCUPADA": self = .ocupada
        case "EM_OBSERVACAO": self = .emObservacao
        default: self = .desconhecido(bruto)
        }
    }

    var bruto: String {
        switch self {
        case .disponivel: "DISPONIVEL"
        case .aguardandoMedicacao: "AGUARDANDO_MEDICACAO"
        case .emPreparo: "EM_PREPARO"
        case .ocupada: "OCUPADA"
        case .emObservacao: "EM_OBSERVACAO"
        case .desconhecido(let b): b
        }
    }

    /// Na ordem em que acontecem — a mesma da legenda e da barra de composição.
    static let ordem: [EstadoDaCadeira] = [.aguardandoMedicacao, .emPreparo, .ocupada, .emObservacao, .disponivel]

    /// `ROTULO_DO_ESTADO_DA_CADEIRA` do contrato, palavra por palavra.
    var nome: String {
        switch self {
        case .disponivel: "Disponível"
        case .aguardandoMedicacao: "Aguardando medicação"
        case .emPreparo: "Em preparação"
        case .ocupada: "Ocupada"
        case .emObservacao: "Em observação"
        case .desconhecido(let b): b.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var tons: TonsDoGiro {
        switch self {
        case .ocupada: .acoAzul
        case .emObservacao: .indigo
        case .aguardandoMedicacao: .ameixa
        case .emPreparo: .vinhoRosa
        case .disponivel, .desconhecido: .livre
        }
    }

    var icone: String {
        switch self {
        case .disponivel: "chair.lounge"
        case .aguardandoMedicacao: "hourglass"
        case .emPreparo: "syringe"
        case .ocupada: "drop.fill"
        case .emObservacao: "eye"
        case .desconhecido: "questionmark"
        }
    }

    var ocupa: Bool { self != .disponivel }
}

/// Estado da SESSÃO de infusão — o que a equipe registra.
enum EstadoDaSessao: Sendable, Hashable, Decodable {
    case agendada, aguardandoMedicacao, emPreparo, emInfusao, emObservacao, concluida, cancelada
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        let bruto = try decoder.singleValueContainer().decode(String.self)
        self = EstadoDaSessao.todos.first { $0.bruto == bruto } ?? .desconhecido(bruto)
    }

    static let todos: [EstadoDaSessao] = [.agendada, .aguardandoMedicacao, .emPreparo, .emInfusao, .emObservacao, .concluida, .cancelada]

    var bruto: String {
        switch self {
        case .agendada: "AGENDADA"
        case .aguardandoMedicacao: "AGUARDANDO_MEDICACAO"
        case .emPreparo: "EM_PREPARO"
        case .emInfusao: "EM_INFUSAO"
        case .emObservacao: "EM_OBSERVACAO"
        case .concluida: "CONCLUIDA"
        case .cancelada: "CANCELADA"
        case .desconhecido(let b): b
        }
    }

    var nome: String {
        switch self {
        case .agendada: "Agendada"
        case .aguardandoMedicacao: "Aguardando medicação"
        case .emPreparo: "Em preparação"
        case .emInfusao: "Em infusão"
        case .emObservacao: "Em observação"
        case .concluida: "Concluída"
        case .cancelada: "Cancelada"
        case .desconhecido(let b): b.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// O estado da cadeira que esta sessão produz — espelho de `estadoDaCadeira` do contrato.
    /// AGENDADA não ocupa: a cadeira só fica presa quando o paciente chega.
    var estadoDaCadeira: EstadoDaCadeira {
        switch self {
        case .aguardandoMedicacao: .aguardandoMedicacao
        case .emPreparo: .emPreparo
        case .emInfusao: .ocupada
        case .emObservacao: .emObservacao
        default: .disponivel
        }
    }

    var encerrada: Bool { self == .concluida || self == .cancelada }
    var ocupaCadeira: Bool { estadoDaCadeira.ocupa }

    /// O próximo passo natural do fluxo, com o verbo que a enfermagem usa.
    var proximo: (estado: EstadoDaSessao, acao: String, icone: String)? {
        switch self {
        case .agendada: (.aguardandoMedicacao, "Paciente chegou", "figure.walk.arrival")
        case .aguardandoMedicacao: (.emPreparo, "Iniciar preparo", "syringe")
        case .emPreparo: (.emInfusao, "Iniciar infusão", "drop.fill")
        case .emInfusao: (.emObservacao, "Passar para observação", "eye")
        case .emObservacao: (.concluida, "Encerrar e liberar a cadeira", "checkmark.circle")
        default: nil
        }
    }
}

/// Complexidade da estratificação de risco — a mesma que o painel usa. Não é faixa
/// clínica de sintoma: nunca leva verde/amarelo/vermelho.
enum ComplexidadeDoPaciente: Decodable, Sendable, Hashable {
    case baixa, media, alta
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        let bruto = try decoder.singleValueContainer().decode(String.self)
        switch bruto {
        case "BAIXO": self = .baixa
        case "MEDIO": self = .media
        case "ALTO": self = .alta
        default: self = .desconhecido(bruto)
        }
    }

    var nome: String {
        switch self {
        case .baixa: "baixa"
        case .media: "média"
        case .alta: "alta"
        case .desconhecido(let b): b.lowercased()
        }
    }

    /// A regra por extenso (`calcularOcupacao` do contrato): a margem é declarada, não
    /// escondida dentro do tempo de infusão.
    var regra: String {
        switch self {
        case .baixa: "Complexidade baixa: tempos do protocolo, sem margem."
        case .media: "Complexidade média: +10% no preparo e na observação. A infusão não muda — o gotejamento é do medicamento."
        case .alta: "Complexidade alta: +20% no preparo e na observação. A infusão não muda — o gotejamento é do medicamento."
        case .desconhecido(let b): "Complexidade \(b.lowercased()): margem definida pela API."
        }
    }
}

// MARK: - Cor do giro (ADR-005 sem o petróleo)

/// A cor de cada estado de poltrona. Estado de cadeira NÃO é gravidade de paciente: nada
/// de verde, amarelo, vermelho ou cinza-silêncio aqui, e nada de lima. A paleta de dado do
/// ADR-005, sem o petróleo-teal (que no web pinta "em preparo" e aqui leria como verde).
/// Cadeira livre fica no cinza da estrutura: boa notícia operacional, não paciente estável.
struct TonsDoGiro: Hashable, Sendable {
    let tinta: Color
    let fundo: Color

    static let acoAzul = TonsDoGiro(tinta: Color(hex: 0x35597F), fundo: Color(hex: 0xE4ECF4))
    static let indigo = TonsDoGiro(tinta: Color(hex: 0x4C4A86), fundo: Color(hex: 0xE8E7F3))
    static let ameixa = TonsDoGiro(tinta: Color(hex: 0x74477A), fundo: Color(hex: 0xF1E8F3))
    static let vinhoRosa = TonsDoGiro(tinta: Color(hex: 0x8A4668), fundo: Color(hex: 0xF5E6ED))
    static let neutro = TonsDoGiro(tinta: Color(hex: 0x6F6F72), fundo: Color(hex: 0xECECED))
    /// Livre: o `--color-borda-forte` do web — estrutura, não dado.
    static let livre = TonsDoGiro(tinta: Cor.tinta.opacity(0.24), fundo: Cor.fundoBaixo)
}

// MARK: - Formato

enum FormatoDoGiro {
    /// "45 min", "2h", "2h05" — o `duracao` do web. Nulo vira "sem registro", nunca zero.
    static func duracao(_ minutos: Int?) -> String {
        guard let minutos else { return "sem registro" }
        if minutos < 60 { return "\(minutos) min" }
        let h = minutos / 60, m = minutos % 60
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }

    /// Duração por extenso para o VoiceOver: "2h05" se lê mal.
    static func duracaoFalada(_ minutos: Int?) -> String {
        guard let minutos else { return "sem registro" }
        if minutos < 60 { return "\(minutos) minutos" }
        let h = minutos / 60, m = minutos % 60
        let horas = h == 1 ? "1 hora" : "\(h) horas"
        return m == 0 ? horas : "\(horas) e \(m) minutos"
    }

    static func minutos(de inicio: Date, ate fim: Date) -> Int {
        max(0, Int((fim.timeIntervalSince(inicio) / 60).rounded(.down)))
    }
}

/// Mensagem honesta para a tela. Enquanto o `ClienteAPI` lê só `message`/`mensagem` e a
/// API responde `{ "erro": … }`, toda recusa chega aqui como "recusou o pedido (4xx)".
/// Trocamos pelo que a pessoa precisa saber naquele contexto.
enum MensagemDoGiro {
    static func de(_ erro: ErroDaAPI, contexto: String) -> String {
        if case .recusado(let texto) = erro {
            if texto.contains("(403)") || texto.localizedCaseInsensitiveContains("permiss") {
                return "Seu acesso não inclui o giro de cadeiras. Quem tem a permissão de atender o plantão pode fazer isto."
            }
            if texto.contains("(404)") { return "\(contexto) Este registro não existe mais — puxe a tela para atualizar." }
            if texto.hasPrefix("O AUREA recusou o pedido") { return contexto }
        }
        return erro.mensagem
    }
}
