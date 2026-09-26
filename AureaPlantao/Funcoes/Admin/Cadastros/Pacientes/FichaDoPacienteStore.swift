import Foundation

/// Eventos de agenda criados neste aparelho, desde que o app abriu.
///
/// Existe porque a API não tem `GET` de agenda para o perfil administrativo: `POST`,
/// `PATCH` e `DELETE /admin/agenda` existem, mas a leitura só sai no histórico clínico
/// (`/painel/pacientes/:id/historico`), que exige permissão de plantão. Sem isto, o evento
/// recém-criado sumiria da tela e ninguém conseguiria corrigir um horário digitado errado.
/// Vive só na memória, como todo dado de paciente no app.
@MainActor
@Observable
final class AgendaCriadaNestaSessao {
    static let compartilhada = AgendaCriadaNestaSessao()
    private(set) var porPaciente: [String: [EventoDeAgendaDoCadastro]] = [:]

    func eventos(de pacienteId: String) -> [EventoDeAgendaDoCadastro] {
        (porPaciente[pacienteId] ?? []).sorted { $0.aconteceEm < $1.aconteceEm }
    }

    func guardar(_ evento: EventoDeAgendaDoCadastro) {
        var lista = porPaciente[evento.pacienteId] ?? []
        lista.removeAll { $0.id == evento.id }
        lista.append(evento)
        porPaciente[evento.pacienteId] = lista
    }

    func esquecer(_ evento: EventoDeAgendaDoCadastro) {
        porPaciente[evento.pacienteId]?.removeAll { $0.id == evento.id }
    }
}

/// A ficha de um paciente e todas as escritas que partem dela.
///
/// Depois de CADA escrita a ficha é relida do servidor. Não é desperdício: é a prova de
/// que gravou (o web já teve formulário que devolvia 200 e não salvava nada) e é o que
/// mantém a tela igual ao banco quando outra pessoa mexe no mesmo cadastro.
@MainActor
@Observable
final class FichaDoPacienteStore {
    private(set) var carga: Carga<FichaDoCadastro> = .carregando
    let pacienteId: String
    private let api: ClienteAPI
    let agenda: AgendaCriadaNestaSessao

    init(pacienteId: String, api: ClienteAPI = .compartilhado, agenda: AgendaCriadaNestaSessao = .compartilhada) {
        self.pacienteId = pacienteId
        self.api = api
        self.agenda = agenda
    }

    private var base: String { "/admin/pacientes/\(pacienteId)" }

    var eventos: [EventoDeAgendaDoCadastro] { agenda.eventos(de: pacienteId) }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter(base))
        } catch {
            carga = .falhou(ErroDoCadastro.traduzir(ErroDaAPI(error)), anterior: anterior)
        }
    }

    // MARK: Cadastro

    func salvar(_ alteracao: AlteracaoDoPacienteDoCadastro) async throws {
        let _: RespostaDeEscritaDoCadastro = try await api.atualizar(base, corpo: alteracao)
        await carregar()
    }

    // MARK: Contatos, alergias, comorbidades

    func adicionar(_ contato: NovoContatoDoCadastro) async throws {
        let _: RespostaDeEscritaDoCadastro = try await api.enviar("\(base)/contatos", corpo: contato)
        await carregar()
    }

    func adicionar(_ alergia: NovaAlergiaDoCadastro) async throws {
        let _: RespostaDeEscritaDoCadastro = try await api.enviar("\(base)/alergias", corpo: alergia)
        await carregar()
    }

    func adicionar(_ comorbidade: NovaComorbidadeDoCadastro) async throws {
        let _: RespostaDeEscritaDoCadastro = try await api.enviar("\(base)/comorbidades", corpo: comorbidade)
        await carregar()
    }

    func remover(_ remocao: RemocaoNaFicha) async throws {
        switch remocao {
        case .contato(let c): try await api.remover("\(base)/contatos/\(c.id)")
        case .alergia(let a): try await api.remover("\(base)/alergias/\(a.id)")
        case .comorbidade(let c): try await api.remover("\(base)/comorbidades/\(c.id)")
        case .evento(let e):
            try await api.remover("/admin/agenda/\(e.id)")
            agenda.esquecer(e)
            return
        }
        await carregar()
    }

    // MARK: Agenda

    func agendar(_ evento: NovoEventoDeAgendaDoCadastro) async throws {
        let criado: EventoDeAgendaDoCadastro = try await api.enviar("/admin/agenda", corpo: evento)
        agenda.guardar(criado)
    }

    /// O `PATCH` devolve o evento como ficou gravado — é ele que volta para a tela, não o
    /// que foi digitado.
    func alterar(_ evento: EventoDeAgendaDoCadastro, para alteracao: AlteracaoDeEventoDoCadastro) async throws {
        let gravado: EventoDeAgendaDoCadastro = try await api.atualizar("/admin/agenda/\(evento.id)", corpo: alteracao)
        agenda.guardar(gravado)
    }
}

/// O que a pessoa pediu para remover, à espera da confirmação.
enum RemocaoNaFicha: Identifiable {
    case contato(ContatoDoCadastro)
    case alergia(ItemClinicoDoCadastro)
    case comorbidade(ItemClinicoDoCadastro)
    case evento(EventoDeAgendaDoCadastro)

    var id: String {
        switch self {
        case .contato(let c): "contato-\(c.id)"
        case .alergia(let a): "alergia-\(a.id)"
        case .comorbidade(let c): "comorbidade-\(c.id)"
        case .evento(let e): "evento-\(e.id)"
        }
    }

    var pergunta: String {
        switch self {
        case .contato(let c): "Remover o contato \(c.nome)?"
        case .alergia(let a): "Remover a alergia “\(a.descricao)”?"
        case .comorbidade(let c): "Remover a comorbidade “\(c.descricao)”?"
        case .evento(let e): "Remover \(e.tipo.nome.lowercased()) de \(InstanteDoCadastro.exibir(e.aconteceEm))?"
        }
    }

    var acao: String {
        switch self {
        case .contato: "Remover contato"
        case .alergia: "Remover alergia"
        case .comorbidade: "Remover comorbidade"
        case .evento: "Remover evento"
        }
    }

    var feito: String {
        switch self {
        case .contato: "Contato removido."
        case .alergia: "Alergia removida."
        case .comorbidade: "Comorbidade removida."
        case .evento: "Evento removido da agenda."
        }
    }
}
