import Foundation

/// `GET /painel/pacientes` — conferido com curl em 25/09/2026.
struct PaginaDePacientes: Decodable, Sendable {
    let itens: [PacienteDaLista]
    let proximoCursor: String?
}

struct PacienteDaLista: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let nome: String
    let dataNascimento: Date
    let diagnostico: String
    let protocolo: String?
    let emTratamento: Bool
    let diaDoCiclo: Int?
    let numeroDoCiclo: Int?
    /// 🔴 Aqui é TEXTO (`"Médico de demonstração"`). No histórico o mesmo campo é OBJETO
    /// `{nome, funcao}`. Mesmo nome, dois formatos — um tipo só quebraria um dos dois.
    let medicoAssistente: String?
    let responsavel: Responsavel?
    let ultimoCheckinEm: Date?
    let respondeuHoje: Bool

    struct Responsavel: Decodable, Sendable, Hashable {
        let nome: String
        let telefone: String
        let relacao: String?
        let deEmergencia: Bool
    }
}

/// `GET /painel/pacientes/:id/historico` — o prontuário. Cada abertura fica registrada
/// na API como `LEITURA_DE_HISTORICO` (LGPD); o app herda essa auditoria.
struct Prontuario: Decodable, Sendable {
    let id: String
    let nome: String
    let dataNascimento: Date
    let sexo: String
    let diagnostico: String
    let convenio: String?
    let protocolo: String?
    let numeroDoCiclo: Int?
    let diaDoCiclo: Int?
    let medicoAssistente: Pessoa?
    /// 🔴 `descricao`, não `substancia` — a lista de alergias do web renderizava vazia.
    let alergias: [Registro]
    let comorbidades: [Registro]
    let ecog: String
    let moraSozinho: Bool
    let dificuldadeDeTransporte: Bool
    let temCuidador: Bool
    let contatos: [Contato]
    let barreiras: [Barreira]
    let internacoes: [Internacao]
    let prescricoes: [Prescricao]
    let eventosDeAgenda: [Evento]
    let sessoesDeTriagem: [SessaoDeTriagem]

    struct Pessoa: Decodable, Sendable, Hashable {
        let nome: String
        let funcao: String
    }

    struct Registro: Decodable, Sendable, Hashable {
        let descricao: String
        let origem: String
        let confirmadaEm: Date?
    }

    struct Contato: Decodable, Sendable, Hashable {
        /// `CONTATO_DO_PACIENTE` | `CONTATO_DE_EMERGENCIA`
        let tipo: String
        let nome: String
        let telefone: String
        let relacao: String?
    }

    struct Barreira: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let tipo: String
        let descricao: String?
        let criadaEm: Date
    }

    struct Internacao: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let motivo: String
        let local: String?
        let iniciadaEm: Date
        let altaEm: Date?
    }

    struct Prescricao: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let posologia: String
        let iniciadaEm: Date
        let encerradaEm: Date?
        let medicamento: Medicamento
        let prescritaPor: Pessoa?

        struct Medicamento: Decodable, Sendable, Hashable {
            let nome: String
            let principioAtivo: String?
        }
    }

    struct Evento: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        /// 🔴 `CONSULTA_MEDICA`, não `CONSULTA` — rótulo em branco em três telas do web.
        let tipo: String
        let aconteceEm: Date
        let local: String?

        var nome: String {
            switch tipo {
            case "QUIMIOTERAPIA": "Sessão de quimioterapia"
            case "CONSULTA_MEDICA": "Consulta médica"
            case "CONSULTA_NUTRICAO": "Consulta com a nutrição"
            case "CONSULTA_PSICOLOGIA": "Consulta com a psicologia"
            default: tipo
            }
        }
    }

    struct SessaoDeTriagem: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        /// `CONCLUIDA` | `ABANDONADA` | `EM_ANDAMENTO`
        let estado: String
        let iniciadaEm: Date
        let concluidaEm: Date?
        let classificacoes: [ClassificacaoDaSessao]
    }

    struct ClassificacaoDaSessao: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        /// `CLASSIFICADA` | `NAO_CLASSIFICADA`
        let situacao: String
        let resultado: Classificacao?
        /// 🔴 `motivoDeNaoClassificar`, não `motivo` — a explicação nunca aparecia no web.
        let motivoDeNaoClassificar: String?
        let calculadaEm: Date
        let conjunto: Conjunto
        let explicacao: Explicacao

        struct Conjunto: Decodable, Sendable, Hashable {
            let versao: String
            let validadoClinicamente: Bool
        }

        /// A explicação é JSON livre no banco: sessão abandonada vem sem `porSintoma`.
        struct Explicacao: Decodable, Sendable, Hashable {
            let porSintoma: [PorSintoma]?
            let sintomasNaoRespondidos: [Sintoma]?

            struct PorSintoma: Decodable, Sendable, Hashable {
                let sintoma: Sintoma
                let classificacao: Classificacao
                let regrasDisparadas: [RegraDisparada]
            }
        }
    }

    /// A classificação mais recente de cada sessão, da mais nova para a mais antiga.
    var checkins: [(sessao: SessaoDeTriagem, classificacao: ClassificacaoDaSessao?)] {
        sessoesDeTriagem.map { ($0, $0.classificacoes.first) }
    }
}

/// `GET /autenticacao/eu`
struct QuemSou: Decodable, Sendable {
    let id: String
    let perfil: String
    let permissoes: [String]
    let perfilDetalhado: Detalhe?

    struct Detalhe: Decodable, Sendable {
        let nome: String
        let funcao: String?
    }

    var funcaoPorExtenso: String {
        switch perfilDetalhado?.funcao {
        case "ENFERMEIRO": "Enfermagem"
        case "MEDICO": "Medicina"
        case "TECNICO_DE_ENFERMAGEM": "Técnico de enfermagem"
        case let outra?: outra.capitalized
        case nil: "Equipe"
        }
    }
}

/// `POST /autenticacao/entrar`
struct RespostaDeEntrada: Decodable, Sendable {
    let token: String
    let expiraEm: Date
    let perfil: String
    let precisaVerPrimeiroAcesso: Bool
}
