import Foundation

// Modelos do cadastro administrativo de pacientes (`/admin/pacientes*` e `/admin/agenda*`).
//
// Todos nasceram do `curl` com a conta admin@aurea.local sobre a base inteira de dev (28
// fichas abertas uma a uma), não do tipo do web — a tela do web nem chamava a API: guardava
// o cadastro em estado local. Achados que moldam os tipos abaixo:
// - A lista não traz contato, alergia nem hábito basal; só a ficha traz.
// - Alergia volta como `descricao` (a API junta "substância, reação: …" num texto só).
// - `dataNascimento` e `parouDeFumarEm` são DATA CIVIL gravadas como meia-noite UTC
//   (`1966-04-18T00:00:00.000Z`). Lidas no fuso de Brasília viram o dia anterior — por isso
//   passam sempre por `DataCivil`.
// - Erro da API vem em `{ "erro": "…" }`, chave que o `ClienteAPI` não lê (ver relatório).

// MARK: - Enums da API, tolerantes a valor novo

/// Um enum da API que não derruba a tela quando o servidor inventa um valor novo:
/// o valor desconhecido vira `.desconhecido(texto)` e aparece como veio.
protocol CodigoDoCadastro: Hashable, Sendable, Codable {
    static var conhecidos: [Self] { get }
    static func desconhecido(_ bruto: String) -> Self
    var bruto: String { get }
    var nome: String { get }
}

extension CodigoDoCadastro {
    init(bruto: String) {
        self = Self.conhecidos.first { $0.bruto == bruto } ?? .desconhecido(bruto)
    }

    init(from decoder: Decoder) throws {
        self.init(bruto: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(bruto)
    }

    /// Opções para `CampoDeEscolha`.
    static var opcoes: [(valor: Self, nome: String)] { conhecidos.map { ($0, $0.nome) } }
}

enum SexoDoCadastro: CodigoDoCadastro {
    case feminino, masculino, outro, naoInformado, desconhecido(String)
    static let conhecidos: [Self] = [.feminino, .masculino, .outro, .naoInformado]
    var bruto: String {
        switch self {
        case .feminino: "FEMININO"
        case .masculino: "MASCULINO"
        case .outro: "OUTRO"
        case .naoInformado: "NAO_INFORMADO"
        case .desconhecido(let s): s
        }
    }
    var nome: String {
        switch self {
        case .feminino: "Feminino"
        case .masculino: "Masculino"
        case .outro: "Outro"
        case .naoInformado: "Não informado"
        case .desconhecido(let s): s
        }
    }
}

enum TabagismoDoCadastro: CodigoDoCadastro {
    case nuncaFumou, exFumante, fumanteAtual, naoInformado, desconhecido(String)
    static let conhecidos: [Self] = [.nuncaFumou, .exFumante, .fumanteAtual, .naoInformado]
    var bruto: String {
        switch self {
        case .nuncaFumou: "NUNCA_FUMOU"
        case .exFumante: "EX_FUMANTE"
        case .fumanteAtual: "FUMANTE_ATUAL"
        case .naoInformado: "NAO_INFORMADO"
        case .desconhecido(let s): s
        }
    }
    var nome: String {
        switch self {
        case .nuncaFumou: "Nunca fumou"
        case .exFumante: "Ex-fumante"
        case .fumanteAtual: "Fuma atualmente"
        case .naoInformado: "Não informado"
        case .desconhecido(let s): s
        }
    }
}

enum AtividadeFisicaDoCadastro: CodigoDoCadastro {
    case sedentario, leve, moderada, intensa, naoInformado, desconhecido(String)
    static let conhecidos: [Self] = [.sedentario, .leve, .moderada, .intensa, .naoInformado]
    var bruto: String {
        switch self {
        case .sedentario: "SEDENTARIO"
        case .leve: "LEVE"
        case .moderada: "MODERADA"
        case .intensa: "INTENSA"
        case .naoInformado: "NAO_INFORMADO"
        case .desconhecido(let s): s
        }
    }
    var nome: String {
        switch self {
        case .sedentario: "Sedentário"
        case .leve: "Leve"
        case .moderada: "Moderada"
        case .intensa: "Intensa"
        case .naoInformado: "Não informado"
        case .desconhecido(let s): s
        }
    }
}

enum ConsumoDeAlcoolDoCadastro: CodigoDoCadastro {
    case naoBebe, social, frequente, naoInformado, desconhecido(String)
    static let conhecidos: [Self] = [.naoBebe, .social, .frequente, .naoInformado]
    var bruto: String {
        switch self {
        case .naoBebe: "NAO_BEBE"
        case .social: "SOCIAL"
        case .frequente: "FREQUENTE"
        case .naoInformado: "NAO_INFORMADO"
        case .desconhecido(let s): s
        }
    }
    var nome: String {
        switch self {
        case .naoBebe: "Não bebe"
        case .social: "Social"
        case .frequente: "Frequente"
        case .naoInformado: "Não informado"
        case .desconhecido(let s): s
        }
    }
}

enum TipoDeContatoDoCadastro: CodigoDoCadastro {
    case doPaciente, deEmergencia, desconhecido(String)
    static let conhecidos: [Self] = [.doPaciente, .deEmergencia]
    var bruto: String {
        switch self {
        case .doPaciente: "CONTATO_DO_PACIENTE"
        case .deEmergencia: "CONTATO_DE_EMERGENCIA"
        case .desconhecido(let s): s
        }
    }
    var nome: String {
        switch self {
        case .doPaciente: "Do paciente"
        case .deEmergencia: "De emergência"
        case .desconhecido(let s): s
        }
    }
}

enum OrigemDaInformacaoDoCadastro: CodigoDoCadastro {
    case equipe, paciente, desconhecido(String)
    static let conhecidos: [Self] = [.equipe, .paciente]
    var bruto: String {
        switch self {
        case .equipe: "EQUIPE"
        case .paciente: "PACIENTE"
        case .desconhecido(let s): s
        }
    }
    var nome: String {
        switch self {
        case .equipe: "registrada pela equipe"
        case .paciente: "relatada pelo paciente"
        case .desconhecido(let s): s.lowercased()
        }
    }
}

enum TipoDeEventoDoCadastro: CodigoDoCadastro {
    case quimioterapia, consultaMedica, consultaNutricao, consultaPsicologia, desconhecido(String)
    static let conhecidos: [Self] = [.quimioterapia, .consultaMedica, .consultaNutricao, .consultaPsicologia]
    var bruto: String {
        switch self {
        case .quimioterapia: "QUIMIOTERAPIA"
        case .consultaMedica: "CONSULTA_MEDICA"
        case .consultaNutricao: "CONSULTA_NUTRICAO"
        case .consultaPsicologia: "CONSULTA_PSICOLOGIA"
        case .desconhecido(let s): s
        }
    }
    var nome: String {
        switch self {
        case .quimioterapia: "Quimioterapia"
        case .consultaMedica: "Consulta médica"
        case .consultaNutricao: "Consulta de nutrição"
        case .consultaPsicologia: "Consulta de psicologia"
        case .desconhecido(let s): s
        }
    }
    var icone: String {
        switch self {
        case .quimioterapia: "cross.vial"
        case .consultaMedica: "stethoscope"
        case .consultaNutricao: "fork.knife"
        case .consultaPsicologia: "bubble.left.and.text.bubble.right"
        case .desconhecido: "calendar"
        }
    }
}

// MARK: - Lista

/// `GET /admin/pacientes?limite=&cursor=` — `{ itens, proximoCursor }`, ordem de criação,
/// mais recente primeiro. Sem parâmetro de busca: a busca é feita aqui, sobre a lista toda.
struct PaginaDoCadastroDePacientes: Decodable, Sendable {
    let itens: [PacienteDoCadastro]
    let proximoCursor: String?
}

struct ProtocoloDoCadastro: Decodable, Hashable, Sendable {
    let id: String
    let nome: String
}

struct PacienteDoCadastro: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let nome: String
    /// Identidade de login. Mostrado sempre mascarado na lista; nunca vai para log.
    let cpf: String
    let dataNascimento: Date
    let sexo: SexoDoCadastro
    let diagnostico: String
    /// Protocolo do tratamento ativo. `null` = ainda não pode entrar em tratamento.
    let protocolo: ProtocoloDoCadastro?
}

// MARK: - Ficha

/// `GET /admin/pacientes/:id`.
struct FichaDoCadastro: Decodable, Sendable {
    let id: String
    let nome: String
    let cpf: String
    let dataNascimento: Date
    let sexo: SexoDoCadastro
    let diagnostico: String
    let convenio: String?
    let tipoSanguineo: String?
    let habitoIntestinalBasal: Int?
    let criadoEm: Date
    let contatos: Contatos
    let alergias: [ItemClinicoDoCadastro]
    let comorbidades: [ItemClinicoDoCadastro]
    let tabagismo: TabagismoDoCadastro
    let parouDeFumarEm: Date?
    let atividadeFisica: AtividadeFisicaDoCadastro
    let descricaoDaAtividade: String?
    let consumoDeAlcool: ConsumoDeAlcoolDoCadastro
    let tratamento: Tratamento?

    struct Contatos: Decodable, Sendable {
        let doPaciente: [ContatoDoCadastro]
        let deEmergencia: [ContatoDoCadastro]
    }

    struct Tratamento: Decodable, Sendable {
        let protocolo: ProtocoloDoCadastro
        let iniciadoEm: Date
    }
}

struct ContatoDoCadastro: Decodable, Identifiable, Sendable {
    let id: String
    let tipo: TipoDeContatoDoCadastro
    let nome: String
    let telefone: String
    let relacao: String?
}

/// Alergia ou comorbidade — a API devolve o mesmo formato para as duas.
struct ItemClinicoDoCadastro: Decodable, Identifiable, Sendable {
    let id: String
    let descricao: String
    let origem: OrigemDaInformacaoDoCadastro
    let confirmadaEm: Date?
    let criadaEm: Date
    let confirmada: Bool
}

/// `POST /admin/agenda` e `PATCH /admin/agenda/:id` devolvem o evento inteiro.
/// Não existe `GET` de agenda para quem tem só `GERENCIAR_CADASTROS`.
struct EventoDeAgendaDoCadastro: Decodable, Identifiable, Sendable {
    let id: String
    let pacienteId: String
    let tipo: TipoDeEventoDoCadastro
    let aconteceEm: Date
    let local: String?
    let profissionalId: String?
    let observacoes: String?
    let criadoEm: Date
}

/// Resposta de escrita da qual a tela só precisa do id (a ficha é relida depois).
struct RespostaDeEscritaDoCadastro: Decodable, Sendable {
    let id: String
}

// MARK: - Corpos de envio

/// `POST /admin/pacientes`. Só os campos que o servidor GRAVA: a história de vida
/// (tabagismo, atividade, álcool) é aceita com 201 e jogada fora na criação — conferido
/// com leitura de volta. Ela entra pela edição, que grava.
struct NovoPacienteDoCadastro: Encodable, Sendable {
    let nome: String
    let cpf: String
    let dataNascimento: String
    let sexo: SexoDoCadastro
    let diagnostico: String
    let convenio: String?
    let tipoSanguineo: String?
    let habitoIntestinalBasal: Int?
    let senhaProvisoria: String
}

/// `PATCH /admin/pacientes/:id` — só o que mudou. Campo ausente = "não mexi";
/// `null` explícito = "limpei". Por isso cada campo é opcional de opcional.
struct AlteracaoDoPacienteDoCadastro: Encodable, Sendable {
    var nome: String??
    var dataNascimento: String??
    var sexo: SexoDoCadastro??
    var diagnostico: String??
    var convenio: String??
    var tipoSanguineo: String??
    var habitoIntestinalBasal: Int??
    var tabagismo: TabagismoDoCadastro??
    var parouDeFumarEm: String??
    var atividadeFisica: AtividadeFisicaDoCadastro??
    var descricaoDaAtividade: String??
    var consumoDeAlcool: ConsumoDeAlcoolDoCadastro??

    var vazia: Bool {
        nome == nil && dataNascimento == nil && sexo == nil && diagnostico == nil
            && convenio == nil && tipoSanguineo == nil && habitoIntestinalBasal == nil
            && tabagismo == nil && parouDeFumarEm == nil && atividadeFisica == nil
            && descricaoDaAtividade == nil && consumoDeAlcool == nil
    }

    private enum Chave: String, CodingKey {
        case nome, dataNascimento, sexo, diagnostico, convenio, tipoSanguineo, habitoIntestinalBasal
        case tabagismo, parouDeFumarEm, atividadeFisica, descricaoDaAtividade, consumoDeAlcool
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Chave.self)
        try Self.escrever(nome, em: &c, chave: .nome)
        try Self.escrever(dataNascimento, em: &c, chave: .dataNascimento)
        try Self.escrever(sexo, em: &c, chave: .sexo)
        try Self.escrever(diagnostico, em: &c, chave: .diagnostico)
        try Self.escrever(convenio, em: &c, chave: .convenio)
        try Self.escrever(tipoSanguineo, em: &c, chave: .tipoSanguineo)
        try Self.escrever(habitoIntestinalBasal, em: &c, chave: .habitoIntestinalBasal)
        try Self.escrever(tabagismo, em: &c, chave: .tabagismo)
        try Self.escrever(parouDeFumarEm, em: &c, chave: .parouDeFumarEm)
        try Self.escrever(atividadeFisica, em: &c, chave: .atividadeFisica)
        try Self.escrever(descricaoDaAtividade, em: &c, chave: .descricaoDaAtividade)
        try Self.escrever(consumoDeAlcool, em: &c, chave: .consumoDeAlcool)
    }

    private static func escrever<T: Encodable>(
        _ valor: T??, em c: inout KeyedEncodingContainer<Chave>, chave: Chave
    ) throws {
        switch valor {
        case .none: break
        case .some(.none): try c.encodeNil(forKey: chave)
        case .some(.some(let v)): try c.encode(v, forKey: chave)
        }
    }
}

struct NovoContatoDoCadastro: Encodable, Sendable {
    let nome: String
    let telefone: String
    let relacao: String?
    let tipo: TipoDeContatoDoCadastro
}

struct NovaAlergiaDoCadastro: Encodable, Sendable {
    let substancia: String
    let reacao: String?
}

struct NovaComorbidadeDoCadastro: Encodable, Sendable {
    let descricao: String
}

struct NovoEventoDeAgendaDoCadastro: Encodable, Sendable {
    let pacienteId: String
    let tipo: TipoDeEventoDoCadastro
    let aconteceEm: String
    let local: String?
    let observacoes: String?
}

/// Edição de evento: aqui o `null` limpa local e observações, então vão sempre explícitos.
struct AlteracaoDeEventoDoCadastro: Encodable, Sendable {
    let tipo: TipoDeEventoDoCadastro
    let aconteceEm: String
    let local: String?
    let observacoes: String?

    private enum Chave: String, CodingKey { case tipo, aconteceEm, local, observacoes }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Chave.self)
        try c.encode(tipo, forKey: .tipo)
        try c.encode(aconteceEm, forKey: .aconteceEm)
        if let local { try c.encode(local, forKey: .local) } else { try c.encodeNil(forKey: .local) }
        if let observacoes { try c.encode(observacoes, forKey: .observacoes) } else { try c.encodeNil(forKey: .observacoes) }
    }
}
