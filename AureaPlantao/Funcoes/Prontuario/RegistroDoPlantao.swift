import Foundation

// Registro do plantão no prontuário: barreira, pendência, internação, contexto social e
// intervenção (conduta) numa sessão de check-in.
//
// 🔴 Modelado da RESPOSTA REAL de `GET /painel/pacientes/:id/historico` (curl com o token de
// enfermagem em 25/09/2026). O `Prontuario` compartilhado não traz `pendencias`,
// `contextoSocialAvaliadoEm` nem as `intervencoes` de cada sessão; em vez de pedir o
// histórico duas vezes (e registrar DUAS leituras de prontuário na auditoria LGPD), a mesma
// resposta é decodificada nos dois tipos — ver `FichaDoProntuario`.

/// O prontuário inteiro, numa leitura só: o tipo compartilhado + o que o registro precisa.
struct FichaDoProntuario: Decodable, Sendable {
    let prontuario: Prontuario
    let registro: RegistroDoProntuario

    init(from decoder: Decoder) throws {
        prontuario = try Prontuario(from: decoder)
        registro = try RegistroDoProntuario(from: decoder)
    }
}

struct RegistroDoProntuario: Decodable, Sendable {
    /// `null` = ninguém perguntou. É o que separa "não tem cuidador" de "não sabemos".
    let contextoSocialAvaliadoEm: Date?
    /// Só as abertas (a API filtra `resolvidaEm: null`), da data mais próxima para a mais distante.
    let pendencias: [Pendencia]
    let sessoesDeTriagem: [SessaoComIntervencoes]

    struct Pendencia: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let tipo: TipoDePendencia
        let descricao: String?
        /// Data CIVIL (`@db.Date`): chega como meia-noite UTC. Formatar em UTC — ver `DataCivil`.
        let referenteA: Date
    }

    struct SessaoComIntervencoes: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let intervencoes: [IntervencaoDaSessao]
    }

    struct IntervencaoDaSessao: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let conduta: String
        /// 🔴 `situacao` no banco e na resposta; o web chama de `situacaoDoSintoma`.
        let situacao: DesfechoDaIntervencao
        let contatoRealizadoEm: Date
        let registradaEm: Date
        let profissional: Profissional?

        struct Profissional: Decodable, Sendable, Hashable {
            let nome: String
            let funcao: String?
        }
    }

    /// As condutas de uma sessão, a mais recente primeiro. A API não ordena este `include`.
    func intervencoes(daSessao id: String) -> [IntervencaoDaSessao] {
        (sessoesDeTriagem.first { $0.id == id }?.intervencoes ?? [])
            .sorted { $0.registradaEm > $1.registradaEm }
    }
}

// MARK: - Enums da API (valor novo não derruba a tela)

/// `SituacaoDoSintoma` — o desfecho de uma intervenção. NÃO é classificação clínica: não
/// usa as cores de `Faixa`.
enum DesfechoDaIntervencao: Hashable, Sendable, Decodable {
    case resolvido, emAcompanhamento, aguardandoRetorno, reavaliar, encaminhadoAoPA
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        self.init(bruto: try decoder.singleValueContainer().decode(String.self))
    }

    init(bruto: String) {
        switch bruto {
        case "RESOLVIDO": self = .resolvido
        case "EM_ACOMPANHAMENTO": self = .emAcompanhamento
        case "AGUARDANDO_RETORNO": self = .aguardandoRetorno
        case "REAVALIAR": self = .reavaliar
        case "ENCAMINHADO_AO_PA": self = .encaminhadoAoPA
        default: self = .desconhecido(bruto)
        }
    }

    var bruto: String {
        switch self {
        case .resolvido: "RESOLVIDO"
        case .emAcompanhamento: "EM_ACOMPANHAMENTO"
        case .aguardandoRetorno: "AGUARDANDO_RETORNO"
        case .reavaliar: "REAVALIAR"
        case .encaminhadoAoPA: "ENCAMINHADO_AO_PA"
        case .desconhecido(let b): b
        }
    }

    /// Rótulos do web (`ROTULO_DO_DESFECHO`).
    var nome: String {
        switch self {
        case .resolvido: "Resolvido"
        case .emAcompanhamento: "Em acompanhamento"
        case .aguardandoRetorno: "Aguardando retorno"
        case .reavaliar: "Reavaliar"
        case .encaminhadoAoPA: "Encaminhado ao pronto atendimento"
        case .desconhecido(let b): b
        }
    }

    /// Exatamente o que `POST /painel/sessoes/:id/intervencoes` aceita, na ordem da conversa
    /// real: o que resolveu, o que continua aberto e, por último, o encaminhamento.
    static let registraveis: [DesfechoDaIntervencao] = [
        .resolvido, .emAcompanhamento, .aguardandoRetorno, .reavaliar, .encaminhadoAoPA,
    ]
}

enum TipoDeBarreira: Hashable, Sendable, Decodable {
    case transporte, autorizacao, financeira, ansiedade, redeDeApoio, distancia, trabalho, outra
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        self.init(bruto: try decoder.singleValueContainer().decode(String.self))
    }

    init(bruto: String) {
        self = Self.todos.first { $0.bruto == bruto } ?? .desconhecido(bruto)
    }

    static let todos: [TipoDeBarreira] = [
        .transporte, .autorizacao, .financeira, .ansiedade, .redeDeApoio, .distancia, .trabalho, .outra,
    ]

    var bruto: String {
        switch self {
        case .transporte: "TRANSPORTE"
        case .autorizacao: "AUTORIZACAO"
        case .financeira: "FINANCEIRA"
        case .ansiedade: "ANSIEDADE"
        case .redeDeApoio: "REDE_DE_APOIO"
        case .distancia: "DISTANCIA"
        case .trabalho: "TRABALHO"
        case .outra: "OUTRA"
        case .desconhecido(let b): b
        }
    }

    var nome: String {
        switch self {
        case .transporte: "Transporte"
        case .autorizacao: "Autorização do convênio"
        case .financeira: "Financeira"
        case .ansiedade: "Ansiedade"
        case .redeDeApoio: "Rede de apoio"
        case .distancia: "Distância"
        case .trabalho: "Trabalho"
        case .outra: "Outra"
        case .desconhecido(let b): b
        }
    }
}

enum TipoDePendencia: Hashable, Sendable, Decodable {
    case exame, autorizacao, consultaMedica, toxicidadeEmAcompanhamento, internacaoRecente, outra
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        self.init(bruto: try decoder.singleValueContainer().decode(String.self))
    }

    init(bruto: String) {
        self = Self.todos.first { $0.bruto == bruto } ?? .desconhecido(bruto)
    }

    static let todos: [TipoDePendencia] = [
        .exame, .autorizacao, .consultaMedica, .toxicidadeEmAcompanhamento, .internacaoRecente, .outra,
    ]

    var bruto: String {
        switch self {
        case .exame: "EXAME"
        case .autorizacao: "AUTORIZACAO"
        case .consultaMedica: "CONSULTA_MEDICA"
        case .toxicidadeEmAcompanhamento: "TOXICIDADE_EM_ACOMPANHAMENTO"
        case .internacaoRecente: "INTERNACAO_RECENTE"
        case .outra: "OUTRA"
        case .desconhecido(let b): b
        }
    }

    var nome: String {
        switch self {
        case .exame: "Exame pendente"
        case .autorizacao: "Autorização pendente"
        case .consultaMedica: "Consulta médica pendente"
        case .toxicidadeEmAcompanhamento: "Toxicidade em acompanhamento"
        case .internacaoRecente: "Internação recente"
        case .outra: "Outra"
        case .desconhecido(let b): b
        }
    }
}

// MARK: - Permissões

/// O que a pessoa pode gravar no prontuário. Espelha os guardas de `painel.ts`: o registro
/// operacional exige `ATENDER_PLANTAO`; a intervenção, `REGISTRAR_INTERVENCAO`. O médico de
/// demonstração só tem `VER_HISTORICO_DE_PACIENTE` — lê tudo, não grava nada.
struct PermissoesDoRegistro: Equatable, Sendable {
    let registrar: Bool
    let intervir: Bool

    init(_ permissoes: [String]) {
        registrar = permissoes.contains("ATENDER_PLANTAO")
        intervir = permissoes.contains("REGISTRAR_INTERVENCAO")
    }

    static let nenhuma = PermissoesDoRegistro([])
}

// MARK: - Gravação

/// As escritas do registro. Cada uma devolve sem corpo: a tela RECARREGA o prontuário depois,
/// porque o que aparece tem que ser o que o servidor guardou (lição da tarefa 072 do web:
/// conduta que aparecia na tela e morria no recarregar).
struct GravacaoDoRegistro: Sendable {
    var api: ClienteAPI = .compartilhado

    struct NovaBarreira: Encodable, Sendable {
        let tipo: String
        let descricao: String?
    }

    struct NovaPendencia: Encodable, Sendable {
        let tipo: String
        /// `yyyy-MM-dd`.
        let referenteA: String
        let descricao: String?
    }

    struct NovaInternacao: Encodable, Sendable {
        let motivo: String
        let local: String?
        let iniciadaEm: String
        let altaEm: String?
    }

    struct ContextoSocial: Encodable, Sendable, Equatable {
        var moraSozinho: Bool
        var dificuldadeDeTransporte: Bool
        var temCuidador: Bool
    }

    struct NovaIntervencao: Encodable, Sendable {
        let conduta: String
        let situacao: String
        /// ISO 8601. Obrigatório na API: é o que mede "do alerta ao contato".
        let contatoRealizadoEm: String
    }

    /// Corpo vazio das resoluções (`{}`).
    private struct Nada: Encodable, Sendable {}

    func registrarBarreira(pacienteId: String, _ corpo: NovaBarreira) async throws {
        try await api.enviarSemResposta("/painel/pacientes/\(pacienteId)/barreiras", corpo: corpo)
    }

    func resolverBarreira(_ id: String) async throws {
        try await api.enviarSemResposta("/painel/barreiras/\(id)/resolucao", corpo: Nada())
    }

    func registrarPendencia(pacienteId: String, _ corpo: NovaPendencia) async throws {
        try await api.enviarSemResposta("/painel/pacientes/\(pacienteId)/pendencias", corpo: corpo)
    }

    func resolverPendencia(_ id: String) async throws {
        try await api.enviarSemResposta("/painel/pendencias/\(id)/resolucao", corpo: Nada())
    }

    func registrarInternacao(pacienteId: String, _ corpo: NovaInternacao) async throws {
        try await api.enviarSemResposta("/painel/pacientes/\(pacienteId)/internacoes", corpo: corpo)
    }

    func gravarContextoSocial(pacienteId: String, _ corpo: ContextoSocial) async throws {
        let _: Vazio = try await api.atualizar("/painel/pacientes/\(pacienteId)/contexto-social", corpo: corpo)
    }

    func registrarIntervencao(sessaoId: String, _ corpo: NovaIntervencao) async throws {
        try await api.enviarSemResposta("/painel/sessoes/\(sessaoId)/intervencoes", corpo: corpo)
    }

    static func instante(_ data: Date) -> String {
        data.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }
}

/// Texto de falha de gravação. Registro clínico que não salvou não pode passar por salvo —
/// e a mensagem diz o que fazer.
///
/// ⚠️ A API manda o texto em `{"erro": "…"}`, e o `ClienteAPI` só lê `message`/`mensagem`:
/// todo 4xx chega aqui como "O AUREA recusou o pedido (NNN)." Até o cliente ler `erro`,
/// o código é o que sobra para decidir.
enum FalhaDeGravacao {
    static func mensagem(_ erro: Error, acao: String) -> String {
        let e = ErroDaAPI(erro)
        switch e {
        case .recusado(let m) where m.contains("(403)"):
            return "Seu acesso não inclui \(acao). Nada foi gravado."
        case .recusado(let m) where m.contains("(404)"):
            return "Este registro não existe mais. Feche e abra o prontuário de novo."
        case .recusado(let m) where m.contains("(400)"):
            return "O AUREA recusou os dados. Confira os campos e tente de novo."
        case .semConexao:
            return "Sem conexão com o AUREA. Nada foi gravado — tente de novo quando a rede voltar."
        default:
            return e.mensagem
        }
    }
}

extension String {
    /// Texto aparado, ou `nil` se ficou vazio (a API recusa descrição vazia).
    var aparadoOuNulo: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
