import Foundation

// Contrato de `apps/api/src/rotas/gestao-de-usuarios.ts`, modelado da resposta real
// (`curl` com admin@, 25/09/2026) e não do tipo TypeScript do web — o web desta tela
// era uma lista local que nunca falou com a API.

/// Função do profissional (enum `FuncaoProfissional` do schema). Função nova — o serviço
/// quer FARMACEUTICO, que o backend ainda não tem — aparece com o nome cru em vez de
/// derrubar a lista inteira.
enum FuncaoProfissional: Sendable, Hashable, Codable {
    case medico
    case enfermeiro
    case tecnicoDeEnfermagem
    case nutricionista
    case psicologo
    case desconhecido(String)

    /// As que o backend aceita hoje no cadastro. `desconhecido` nunca é oferecido.
    static let conhecidas: [FuncaoProfissional] = [.medico, .enfermeiro, .tecnicoDeEnfermagem, .nutricionista, .psicologo]

    init(bruto: String) {
        switch bruto {
        case "MEDICO": self = .medico
        case "ENFERMEIRO": self = .enfermeiro
        case "TECNICO_DE_ENFERMAGEM": self = .tecnicoDeEnfermagem
        case "NUTRICIONISTA": self = .nutricionista
        case "PSICOLOGO": self = .psicologo
        default: self = .desconhecido(bruto)
        }
    }

    var bruto: String {
        switch self {
        case .medico: "MEDICO"
        case .enfermeiro: "ENFERMEIRO"
        case .tecnicoDeEnfermagem: "TECNICO_DE_ENFERMAGEM"
        case .nutricionista: "NUTRICIONISTA"
        case .psicologo: "PSICOLOGO"
        case .desconhecido(let valor): valor
        }
    }

    /// Mesmo rótulo do web (`ROTULO_DA_FUNCAO`).
    var nome: String {
        switch self {
        case .medico: "Médico"
        case .enfermeiro: "Enfermeiro"
        case .tecnicoDeEnfermagem: "Técnico de enfermagem"
        case .nutricionista: "Nutricionista"
        case .psicologo: "Psicólogo"
        // Nome cru, legível: FARMACEUTICO → "Farmaceutico". Sem inventar acento.
        case .desconhecido(let valor): valor.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    init(from decoder: Decoder) throws {
        self.init(bruto: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(bruto)
    }
}

/// Permissão de acesso (enum `Permissao` do schema). Concessão nominal e auditável: cada
/// uma é dada a uma pessoa, por alguém, numa data.
enum PermissaoDeAcesso: Sendable, Hashable, Codable, Identifiable {
    case atenderPlantao
    case verHistoricoDePaciente
    case registrarIntervencao
    case editarAlgoritmo
    case publicarAlgoritmo
    case editarOrientacao
    case gerenciarCadastros
    case gerenciarUsuarios
    case exportarConjuntoDePesquisa
    case desconhecida(String)

    var id: String { bruto }

    init(bruto: String) {
        switch bruto {
        case "ATENDER_PLANTAO": self = .atenderPlantao
        case "VER_HISTORICO_DE_PACIENTE": self = .verHistoricoDePaciente
        case "REGISTRAR_INTERVENCAO": self = .registrarIntervencao
        case "EDITAR_ALGORITMO": self = .editarAlgoritmo
        case "PUBLICAR_ALGORITMO": self = .publicarAlgoritmo
        case "EDITAR_ORIENTACAO": self = .editarOrientacao
        case "GERENCIAR_CADASTROS": self = .gerenciarCadastros
        case "GERENCIAR_USUARIOS": self = .gerenciarUsuarios
        case "EXPORTAR_CONJUNTO_DE_PESQUISA": self = .exportarConjuntoDePesquisa
        default: self = .desconhecida(bruto)
        }
    }

    var bruto: String {
        switch self {
        case .atenderPlantao: "ATENDER_PLANTAO"
        case .verHistoricoDePaciente: "VER_HISTORICO_DE_PACIENTE"
        case .registrarIntervencao: "REGISTRAR_INTERVENCAO"
        case .editarAlgoritmo: "EDITAR_ALGORITMO"
        case .publicarAlgoritmo: "PUBLICAR_ALGORITMO"
        case .editarOrientacao: "EDITAR_ORIENTACAO"
        case .gerenciarCadastros: "GERENCIAR_CADASTROS"
        case .gerenciarUsuarios: "GERENCIAR_USUARIOS"
        case .exportarConjuntoDePesquisa: "EXPORTAR_CONJUNTO_DE_PESQUISA"
        case .desconhecida(let valor): valor
        }
    }

    var nome: String {
        switch self {
        case .atenderPlantao: "Atender plantão"
        case .verHistoricoDePaciente: "Ver histórico de paciente"
        case .registrarIntervencao: "Registrar conduta"
        case .editarAlgoritmo: "Editar algoritmo"
        case .publicarAlgoritmo: "Publicar algoritmo"
        case .editarOrientacao: "Editar orientação"
        case .gerenciarCadastros: "Gerenciar cadastros"
        case .gerenciarUsuarios: "Gerenciar usuários"
        case .exportarConjuntoDePesquisa: "Exportar conjunto de pesquisa"
        case .desconhecida(let valor): valor.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// O que a permissão deixa fazer, em português de gente. As duas do conflito dizem
    /// o porquê da separação — é o comentário do schema (regra 6 do ADR-001) na tela.
    var explicacao: String {
        switch self {
        case .atenderPlantao:
            "Recebe a fila do plantão e os pedidos de contato, e responde um paciente por vez. Não vai junto com Editar algoritmo."
        case .verHistoricoDePaciente:
            "Abre o prontuário e o histórico de check-ins e classificações, sem receber a fila."
        case .registrarIntervencao:
            "Registra a conduta tomada depois de falar com o paciente."
        case .editarAlgoritmo:
            "Cria e altera as regras que classificam todos os pacientes de uma vez. Quem edita o algoritmo muda o risco de todo mundo; quem está de plantão atende um. Por isso nunca vão juntas."
        case .publicarAlgoritmo:
            "Coloca em uso um conjunto de regras revisado e consulta o registro de acessos."
        case .editarOrientacao:
            "Escreve os textos que o paciente lê depois de cada check-in."
        case .gerenciarCadastros:
            "Cadastra pacientes, tratamentos, ciclos, prescrições, protocolos e medicamentos."
        case .gerenciarUsuarios:
            "Cria contas da equipe, muda permissões e desativa acessos, como nesta tela."
        case .exportarConjuntoDePesquisa:
            "Exporta os dados anonimizados para pesquisa."
        case .desconhecida:
            "Permissão que este app ainda não conhece. Ela é mantida como está ao salvar."
        }
    }

    enum Grupo: String, CaseIterable {
        case cuidado = "Cuidado ao paciente"
        case algoritmo = "Algoritmo e conteúdo"
        case administracao = "Administração"
    }

    var grupo: Grupo? {
        switch self {
        case .atenderPlantao, .verHistoricoDePaciente, .registrarIntervencao: .cuidado
        case .editarAlgoritmo, .publicarAlgoritmo, .editarOrientacao: .algoritmo
        case .gerenciarCadastros, .gerenciarUsuarios, .exportarConjuntoDePesquisa: .administracao
        case .desconhecida: nil
        }
    }

    static let conhecidas: [PermissaoDeAcesso] = [
        .atenderPlantao, .verHistoricoDePaciente, .registrarIntervencao,
        .editarAlgoritmo, .publicarAlgoritmo, .editarOrientacao,
        .gerenciarCadastros, .gerenciarUsuarios, .exportarConjuntoDePesquisa,
    ]

    /// A combinação que a API recusa com 422 (regra 6 do ADR-001).
    static func temCombinacaoProibida(_ conjunto: Set<PermissaoDeAcesso>) -> Bool {
        conjunto.contains(.editarAlgoritmo) && conjunto.contains(.atenderPlantao)
    }

    init(from decoder: Decoder) throws {
        self.init(bruto: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(bruto)
    }
}

/// Item de `GET /admin/usuarios`. Só PROFISSIONAL e ADMINISTRADOR.
struct ContaDaEquipe: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    /// `Usuario.email` é opcional no schema (paciente entra por CPF); aqui sempre veio.
    let email: String?
    let perfil: String
    let ativo: Bool
    let ultimoAcessoEm: Date?
    let criadoEm: Date
    /// Nulo para conta antiga sem ficha de profissional (o admin@ da seed).
    let profissional: Ficha?
    let permissoes: [PermissaoDeAcesso]

    struct Ficha: Decodable, Sendable, Hashable {
        let nome: String
        let funcao: FuncaoProfissional
        let registroDoConselho: String?
    }

    var nome: String { profissional?.nome ?? email ?? "Conta sem nome" }

    var ehAdministracao: Bool { perfil == "ADMINISTRADOR" }

    var semRegistroDoConselho: Bool {
        guard let profissional else { return false }
        return (profissional.registroDoConselho ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Tipo de conta que o cadastro pode criar (`perfil` do POST).
enum TipoDeContaDaEquipe: String, Sendable, Hashable, CaseIterable {
    case profissional = "PROFISSIONAL"
    case administrador = "ADMINISTRADOR"

    var nome: String {
        switch self {
        case .profissional: "Equipe (painel do plantão)"
        case .administrador: "Administração (cadastros e algoritmo)"
        }
    }
}
