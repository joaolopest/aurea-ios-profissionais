import Foundation

// `GET /painel/navegacao` (painel.ts, "Blocos 6, 9, 10 e 11"). Sem parâmetros de consulta —
// o web chama sem nenhum, e a rota não lê `query`.
//
// 🔴 Modelado a partir da resposta REAL (curl com enfermagem@ e medico@, 25/09/2026). Os
// alertas pré-tratamento vieram vazios no banco de dev; o formato deles foi lido de duas
// pendências criadas "(teste app)" para amanhã e resolvidas em seguida:
//   { id, pacienteId, paciente (TEXTO, o nome), tipo, descricao (nulo quando não há),
//     referenteA ("2026-09-26T00:00:00.000Z" — coluna @db.Date serializada como
//     meia-noite UTC) }
// `tempoMedioDeRespostaEmMinutos` é nulo quando nenhuma intervenção tem as duas datas.

struct PainelDeNavegacao: Decodable, Sendable, Equatable {
    let indicadores: Indicadores
    let barreiras: [Barreira]
    let alertasPreTratamento: [AlertaPreTratamento]
    let mural: Mural

    struct Indicadores: Decodable, Sendable, Equatable {
        let pacientesAcompanhados: Int
        let intervencoesRealizadas: Int
        let tempoMedioDeRespostaEmMinutos: Int?
        let encaminhamentos: Int
        let internacoesNotificadas: Int
        let tratamentosSuspensos: Int
        let pacientesSemRedeDeApoio: Int
        let pacientesComDificuldadeDeAcesso: Int
    }

    struct Barreira: Decodable, Sendable, Equatable {
        let tipo: TipoDeBarreiraNoMapa
        let quantidade: Int
    }

    struct AlertaPreTratamento: Decodable, Sendable, Equatable, Identifiable {
        let id: String
        let pacienteId: String
        /// O nome, em texto — não um objeto como em outras rotas.
        let paciente: String
        let tipo: TipoDePendenciaNoMapa
        let descricao: String?
        /// Dia civil. Mantido como texto: lido como instante, a meia-noite UTC vira 21 h do
        /// dia ANTERIOR em Brasília, e "amanhã" apareceria com a data de hoje.
        let referenteA: String
    }

    struct Mural: Decodable, Sendable, Equatable {
        let pacientesInternados: Int
        let tratamentosSuspensos: Int
        let pendenciasParaAmanha: Int
        let barreirasAbertas: Int
    }
}

/// Tipo de barreira de acesso. Valor novo não derruba a tela: aparece cru.
enum TipoDeBarreiraNoMapa: Decodable, Sendable, Equatable, Hashable {
    case transporte, autorizacao, financeira, ansiedade, redeDeApoio, distancia, trabalho, outra
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        let bruto = try decoder.singleValueContainer().decode(String.self)
        switch bruto {
        case "TRANSPORTE": self = .transporte
        case "AUTORIZACAO": self = .autorizacao
        case "FINANCEIRA": self = .financeira
        case "ANSIEDADE": self = .ansiedade
        case "REDE_DE_APOIO": self = .redeDeApoio
        case "DISTANCIA": self = .distancia
        case "TRABALHO": self = .trabalho
        case "OUTRA": self = .outra
        default: self = .desconhecido(bruto)
        }
    }

    var nome: String {
        switch self {
        case .transporte: "Transporte"
        case .autorizacao: "Autorização"
        case .financeira: "Financeira"
        case .ansiedade: "Ansiedade"
        case .redeDeApoio: "Rede de apoio"
        case .distancia: "Distância"
        case .trabalho: "Trabalho"
        case .outra: "Outra"
        case .desconhecido(let c): c
        }
    }
}

/// Tipo de pendência pré-tratamento (`pendenciaSchema` em painel.ts).
enum TipoDePendenciaNoMapa: Decodable, Sendable, Equatable, Hashable {
    case exame, autorizacao, consultaMedica, toxicidadeEmAcompanhamento, internacaoRecente, outra
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        let bruto = try decoder.singleValueContainer().decode(String.self)
        switch bruto {
        case "EXAME": self = .exame
        case "AUTORIZACAO": self = .autorizacao
        case "CONSULTA_MEDICA": self = .consultaMedica
        case "TOXICIDADE_EM_ACOMPANHAMENTO": self = .toxicidadeEmAcompanhamento
        case "INTERNACAO_RECENTE": self = .internacaoRecente
        case "OUTRA": self = .outra
        default: self = .desconhecido(bruto)
        }
    }

    var nome: String {
        switch self {
        case .exame: "Exame pendente"
        case .autorizacao: "Autorização pendente"
        case .consultaMedica: "Consulta médica pendente"
        case .toxicidadeEmAcompanhamento: "Toxicidade em acompanhamento"
        case .internacaoRecente: "Internação recente"
        case .outra: "Outra pendência"
        case .desconhecido(let c): c
        }
    }

    var icone: String {
        switch self {
        case .exame: "testtube.2"
        case .autorizacao: "doc.badge.clock"
        case .consultaMedica: "stethoscope"
        case .toxicidadeEmAcompanhamento: "waveform.path.ecg"
        case .internacaoRecente: "bed.double"
        case .outra, .desconhecido: "exclamationmark.circle"
        }
    }
}
