import SwiftUI

/// O que a pessoa logada pode fazer. Vem de `GET /autenticacao/eu`.
///
/// O AUREA não separa por profissão: médico e enfermeira são o mesmo perfil `PROFISSIONAL`,
/// e o que muda é a lista de PERMISSÕES (concessão nominal e auditável, regra 6 do schema).
/// Por isso o app não pergunta "é médico?" — pergunta "pode atender o plantão?". Uma função
/// nova (farmacêutico, por exemplo) funciona sem mudar o app: basta receber as permissões.
struct Acesso: Equatable, Sendable {
    let perfil: String
    let permissoes: Set<String>

    init(perfil: String, permissoes: [String]) {
        self.perfil = perfil
        self.permissoes = Set(permissoes)
    }

    func tem(_ algumaDestas: String...) -> Bool {
        algumaDestas.contains { permissoes.contains($0) }
    }

    var ehAdministrador: Bool { perfil == "ADMINISTRADOR" }

    /// Os destinos que esta pessoa vê, na ordem do menu. O guarda de cada um espelha o
    /// `exigirPermissao` da rota na API — mostrar uma tela que devolve 403 é mentir.
    var destinos: [Destino] {
        Destino.allCases.filter { $0.perfil == perfil && $0.permitido(self) }
    }

    /// Os que viram aba. O resto vai para "Mais".
    var abas: [Destino] {
        let principais = destinos.filter(\.ehAba)
        return destinos.count > principais.count ? principais + [.mais] : principais
    }

    var secundarios: [Destino] {
        destinos.filter { !$0.ehAba && $0 != .mais }
    }
}

/// Todos os lugares do app. Painel = perfil PROFISSIONAL; admin = perfil ADMINISTRADOR —
/// a mesma divisão do web (`/painel` e `/admin`).
enum Destino: String, CaseIterable, Identifiable, Sendable {
    // Painel
    case plantao, contatos, pacientes, intervencoes, cadeiras, toxicidade, navegacao
    // Admin
    case inicioAdmin, limiares, cadastros, orientacoes, protocolos, medicamentos, equipe, acessos, pesquisa
    // Comum
    case mais

    var id: String { rawValue }

    var perfil: String? {
        switch self {
        case .plantao, .contatos, .pacientes, .intervencoes, .cadeiras, .toxicidade, .navegacao: "PROFISSIONAL"
        case .inicioAdmin, .limiares, .cadastros, .orientacoes, .protocolos, .medicamentos, .equipe, .acessos, .pesquisa: "ADMINISTRADOR"
        case .mais: nil
        }
    }

    /// Espelho dos guardas da API (`apps/api/src/rotas/*.ts`).
    func permitido(_ a: Acesso) -> Bool {
        switch self {
        // painel.ts `comAcesso`: ATENDER_PLANTAO ou VER_HISTORICO_DE_PACIENTE
        case .plantao, .pacientes, .intervencoes, .toxicidade, .navegacao:
            a.tem("ATENDER_PLANTAO", "VER_HISTORICO_DE_PACIENTE")
        // atendimento.ts `dePlantao` e cadeiras.ts `comAcesso`: ATENDER_PLANTAO
        case .contatos, .cadeiras:
            a.tem("ATENDER_PLANTAO")
        case .inicioAdmin:
            true
        // admin.ts `comLeitura`
        case .limiares:
            a.tem("EDITAR_ALGORITMO", "PUBLICAR_ALGORITMO", "GERENCIAR_CADASTROS")
        // GET /admin/orientacoes é `comLeitura`; editar exige EDITAR_ORIENTACAO (a tela decide)
        case .orientacoes:
            a.tem("EDITAR_ALGORITMO", "PUBLICAR_ALGORITMO", "GERENCIAR_CADASTROS")
        case .cadastros, .protocolos, .medicamentos:
            a.tem("GERENCIAR_CADASTROS")
        case .equipe:
            a.tem("GERENCIAR_USUARIOS")
        // admin.ts: registro de acessos exige PUBLICAR_ALGORITMO
        case .acessos:
            a.tem("PUBLICAR_ALGORITMO")
        case .pesquisa:
            a.tem("EXPORTAR_CONJUNTO_DE_PESQUISA")
        case .mais:
            true
        }
    }

    var ehAba: Bool {
        switch self {
        case .plantao, .contatos, .pacientes, .inicioAdmin, .limiares, .cadastros: true
        default: false
        }
    }

    var nome: String {
        switch self {
        case .plantao: "Plantão"
        case .contatos: "Contatos"
        case .pacientes: "Pacientes"
        case .intervencoes: "Condutas"
        case .cadeiras: "Cadeiras"
        case .toxicidade: "Toxicidade"
        case .navegacao: "Navegação"
        case .inicioAdmin: "Início"
        case .limiares: "Algoritmo"
        case .cadastros: "Cadastros"
        case .orientacoes: "Orientações"
        case .protocolos: "Protocolos"
        case .medicamentos: "Medicamentos"
        case .equipe: "Equipe"
        case .acessos: "Acessos"
        case .pesquisa: "Pesquisa"
        case .mais: "Mais"
        }
    }

    /// A linha que explica o destino no menu "Mais".
    var descricao: String {
        switch self {
        case .intervencoes: "Condutas registradas e o que falta reavaliar"
        case .cadeiras: "Giro das cadeiras de infusão, ao vivo"
        case .toxicidade: "Sintomas por protocolo, na janela que você escolher"
        case .navegacao: "Internados, barreiras e pendências do serviço"
        case .orientacoes: "O que o paciente lê depois de cada check-in"
        case .protocolos: "Protocolos de quimioterapia do serviço"
        case .medicamentos: "Catálogo usado nas prescrições"
        case .equipe: "Contas, funções e permissões da equipe"
        case .acessos: "Quem abriu o quê, e quando — LGPD"
        case .pesquisa: "Exportação do conjunto de pesquisa"
        default: ""
        }
    }

    var icone: String {
        switch self {
        case .plantao: "waveform.path.ecg"
        case .contatos: "phone.arrow.down.left"
        case .pacientes: "person.2"
        case .intervencoes: "checklist"
        case .cadeiras: "chair.lounge"
        case .toxicidade: "chart.bar.xaxis"
        case .navegacao: "map"
        case .inicioAdmin: "square.grid.2x2"
        case .limiares: "slider.horizontal.3"
        case .cadastros: "person.text.rectangle"
        case .orientacoes: "text.book.closed"
        case .protocolos: "list.bullet.clipboard"
        case .medicamentos: "pills"
        case .equipe: "person.badge.key"
        case .acessos: "lock.doc"
        case .pesquisa: "square.and.arrow.up"
        case .mais: "ellipsis"
        }
    }

    var iconeAtivo: String {
        switch self {
        case .contatos: "phone.arrow.down.left.fill"
        case .pacientes: "person.2.fill"
        case .cadastros: "person.text.rectangle.fill"
        case .inicioAdmin: "square.grid.2x2.fill"
        default: icone
        }
    }

    /// Tom da aurora. Só azuis — nada que lembre faixa clínica.
    var tom: Color {
        switch self {
        case .plantao, .inicioAdmin: Cor.auroraCeu
        case .contatos, .limiares, .cadeiras: Cor.auroraAco
        case .pacientes, .cadastros, .mais: Cor.auroraIndigo
        default: Cor.auroraCeu
        }
    }
}
