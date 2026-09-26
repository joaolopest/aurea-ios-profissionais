import SwiftUI

// As folhas curtas que partem da ficha: contato, alergia, comorbidade e evento de agenda.
// Validação local espelha os limites do Zod da API — a mensagem de recusa da API não
// chega à tela (chave `erro`), então o que a API recusaria tem que ser pego aqui antes.

// MARK: - Contato

struct FormularioDeContato: View {
    let store: FichaDoPacienteStore
    let concluir: () -> Void

    @State private var tipo: TipoDeContatoDoCadastro? = .deEmergencia
    @State private var nome = ""
    @State private var telefone = ""
    @State private var relacao = ""
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Ficha de cadastro",
            titulo: "Novo contato",
            acao: "Adicionar contato",
            icone: "phone.badge.plus",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEscolha(rotulo: "De quem é o telefone", opcoes: TipoDeContatoDoCadastro.opcoes, selecionado: $tipo)
            CampoDeEntrada(rotulo: "Nome", texto: $nome, conteudo: .name)
            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "Telefone com DDD", texto: $telefone, teclado: .phonePad, conteudo: .telephoneNumber)
                if !telefone.isEmpty {
                    ApoioDeCampoDoCadastro(texto: Formato.telefone(telefone))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "Relação (opcional)", texto: $relacao)
                ApoioDeCampoDoCadastro(texto: tipo == .deEmergencia ? "Ex.: filha, esposo, vizinha." : "Ex.: próprio, celular do trabalho.")
            }
        }
    }

    private func enviar() async {
        let n = TextoDoCadastro.aparado(nome)
        let digitos = telefone.filter(\.isNumber)
        let problema: String? = {
            guard let tipo, TipoDeContatoDoCadastro.conhecidos.contains(tipo) else { return "Escolha de quem é o telefone." }
            if n.count < 2 { return "Informe o nome do contato." }
            if n.count > 180 { return "O nome passa de 180 caracteres." }
            if digitos.count < 10 || digitos.count > 13 { return "Informe o telefone com DDD (10 ou 11 dígitos)." }
            if TextoDoCadastro.aparado(relacao).count > 60 { return "A relação passa de 60 caracteres." }
            return nil
        }()
        if let problema {
            Tato.erro()
            erro = problema
            return
        }
        guard let tipo else { return }
        enviando = true
        erro = nil
        defer { enviando = false }
        do {
            // Só dígitos: o servidor guarda o que receber, e máscara no banco quebra o `tel:`.
            try await store.adicionar(NovoContatoDoCadastro(nome: n, telefone: digitos,
                                                            relacao: TextoDoCadastro.opcional(relacao), tipo: tipo))
            concluir()
        } catch {
            Tato.erro()
            erro = ErroDoCadastro.mensagem(error)
        }
    }
}

// MARK: - Alergia

/// A API guarda alergia num texto só: "substância, reação: …". Os dois campos daqui viram
/// essa frase no servidor — a tela diz isso para ninguém procurar a reação em outro lugar.
struct FormularioDeAlergia: View {
    let store: FichaDoPacienteStore
    let concluir: () -> Void

    @State private var substancia = ""
    @State private var reacao = ""
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Ficha de cadastro",
            titulo: "Nova alergia",
            acao: "Registrar alergia",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEntrada(rotulo: "Substância", texto: $substancia)
            CampoDeEntrada(rotulo: "Reação (opcional)", texto: $reacao)
            ApoioDeCampoDoCadastro(texto: "Fica registrada pela equipe e sem confirmação clínica — confirmar é de quem responde clinicamente pelo paciente. A reação é gravada junto da substância, numa frase só.")
        }
    }

    private func enviar() async {
        let s = TextoDoCadastro.aparado(substancia)
        let r = TextoDoCadastro.opcional(reacao)
        let problema: String? = {
            if s.count < 2 { return "Informe a substância." }
            if s.count > 200 { return "A substância passa de 200 caracteres." }
            // O servidor grava "substância, reação: …" numa coluna de 255.
            if let r, s.count + r.count + 10 > 255 { return "Substância e reação juntas passam do limite. Encurte a reação." }
            return nil
        }()
        if let problema {
            Tato.erro()
            erro = problema
            return
        }
        enviando = true
        erro = nil
        defer { enviando = false }
        do {
            try await store.adicionar(NovaAlergiaDoCadastro(substancia: s, reacao: r))
            concluir()
        } catch {
            Tato.erro()
            erro = ErroDoCadastro.mensagem(error)
        }
    }
}

// MARK: - Comorbidade

struct FormularioDeComorbidade: View {
    let store: FichaDoPacienteStore
    let concluir: () -> Void

    @State private var descricao = ""
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Ficha de cadastro",
            titulo: "Nova comorbidade",
            acao: "Registrar comorbidade",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeTextoLongo(rotulo: "Descrição", texto: $descricao, dica: "Ex.: hipertensão arterial controlada", linhas: 2)
            ApoioDeCampoDoCadastro(texto: "Fica registrada pela equipe e sem confirmação clínica.")
        }
    }

    private func enviar() async {
        let d = TextoDoCadastro.aparado(descricao)
        if d.count < 2 || d.count > 255 {
            Tato.erro()
            erro = d.count < 2 ? "Descreva a comorbidade." : "A descrição passa de 255 caracteres."
            return
        }
        enviando = true
        erro = nil
        defer { enviando = false }
        do {
            try await store.adicionar(NovaComorbidadeDoCadastro(descricao: d))
            concluir()
        } catch {
            Tato.erro()
            erro = ErroDoCadastro.mensagem(error)
        }
    }
}

// MARK: - Evento de agenda

/// Agendar ou corrigir um evento. O profissional responsável fica de fora: a API aceita o
/// id, mas a lista de profissionais mora numa rota de outra permissão (usuários), e pedir
/// um UUID digitado seria pior que não pedir.
struct FormularioDeEvento: View {
    let pacienteId: String
    let evento: EventoDeAgendaDoCadastro?
    let store: FichaDoPacienteStore
    let concluir: () -> Void

    @State private var tipo: TipoDeEventoDoCadastro?
    @State private var quando: Date
    @State private var local: String
    @State private var observacoes: String
    @State private var enviando = false
    @State private var erro: String?

    init(pacienteId: String, evento: EventoDeAgendaDoCadastro?, store: FichaDoPacienteStore, concluir: @escaping () -> Void) {
        self.pacienteId = pacienteId
        self.evento = evento
        self.store = store
        self.concluir = concluir
        _tipo = State(initialValue: evento?.tipo)
        _quando = State(initialValue: evento?.aconteceEm ?? Self.proximaHoraCheia())
        _local = State(initialValue: evento?.local ?? "")
        _observacoes = State(initialValue: evento?.observacoes ?? "")
    }

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Agenda do paciente",
            titulo: evento == nil ? "Agendar" : "Editar evento",
            acao: evento == nil ? "Agendar evento" : "Salvar alterações",
            icone: "calendar.badge.plus",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEscolha(rotulo: "Tipo", opcoes: TipoDeEventoDoCadastro.opcoes, selecionado: $tipo)
            CampoDeData(rotulo: "Data e hora", data: $quando, comHora: true)
            CampoDeEntrada(rotulo: "Local (opcional)", texto: $local)
            CampoDeTextoLongo(rotulo: "Observações (opcional)", texto: $observacoes,
                              dica: "Ex.: trazer os exames de sangue", linhas: 3)
            ApoioDeCampoDoCadastro(texto: "O paciente vê o evento na agenda do app dele.")
        }
    }

    private func enviar() async {
        let l = TextoDoCadastro.opcional(local)
        let o = TextoDoCadastro.opcional(observacoes)
        let problema: String? = {
            guard let tipo, TipoDeEventoDoCadastro.conhecidos.contains(tipo) else { return "Escolha o tipo do evento." }
            if (l?.count ?? 0) > 180 { return "O local passa de 180 caracteres." }
            if (o?.count ?? 0) > 4000 { return "As observações passam de 4.000 caracteres." }
            return nil
        }()
        if let problema {
            Tato.erro()
            erro = problema
            return
        }
        guard let tipo else { return }
        enviando = true
        erro = nil
        defer { enviando = false }
        do {
            let instante = InstanteDoCadastro.paraAPI(quando)
            if let evento {
                try await store.alterar(evento, para: AlteracaoDeEventoDoCadastro(tipo: tipo, aconteceEm: instante, local: l, observacoes: o))
            } else {
                try await store.agendar(NovoEventoDeAgendaDoCadastro(pacienteId: pacienteId, tipo: tipo, aconteceEm: instante, local: l, observacoes: o))
            }
            concluir()
        } catch {
            Tato.erro()
            erro = ErroDoCadastro.mensagem(error)
        }
    }

    private static func proximaHoraCheia() -> Date {
        let cal = Calendar.current
        let daquiAUmaHora = Date.now.addingTimeInterval(3600)
        var partes = cal.dateComponents([.year, .month, .day, .hour], from: daquiAUmaHora)
        partes.minute = 0
        return cal.date(from: partes) ?? daquiAUmaHora
    }
}
