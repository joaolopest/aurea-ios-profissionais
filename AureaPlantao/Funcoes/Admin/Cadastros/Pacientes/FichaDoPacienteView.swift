import SwiftUI

/// As folhas que partem da ficha. Uma por vez, por `.sheet(item:)`.
enum FolhaDaFicha: Identifiable {
    case editar(FichaDoCadastro)
    case contato
    case alergia
    case comorbidade
    case novoEvento
    case editarEvento(EventoDeAgendaDoCadastro)

    var id: String {
        switch self {
        case .editar: "editar"
        case .contato: "contato"
        case .alergia: "alergia"
        case .comorbidade: "comorbidade"
        case .novoEvento: "novoEvento"
        case .editarEvento(let e): "evento-\(e.id)"
        }
    }
}

/// A ficha de cadastro, na ordem em que a recepção preenche: quem é → como falar com ele
/// → a que é alérgico e o que já tem → como vive → quando volta ao serviço.
struct FichaDoPacienteView: View {
    let rota: RotaDaFichaDoCadastro
    let aoAlterar: () async -> Void
    @State private var store: FichaDoPacienteStore
    @State private var folha: FolhaDaFicha?
    @State private var remocao: RemocaoNaFicha?
    @State private var removendo = false
    @State private var aviso: String?
    @State private var erroDeRemocao: String?

    init(rota: RotaDaFichaDoCadastro, aoAlterar: @escaping () async -> Void) {
        self.rota = rota
        self.aoAlterar = aoAlterar
        _store = State(initialValue: FichaDoPacienteStore(pacienteId: rota.id))
    }

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Ficha de cadastro",
                titulo: store.carga.valor?.nome ?? rota.nome,
                contexto: store.carga.valor?.diagnostico
            )

            if let erroDeRemocao {
                Label(erroDeRemocao, systemImage: "exclamationmark.circle")
                    .font(Tipo.apoio).foregroundStyle(Cor.texto)
                    .padding(Espaco.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficie(.afundado, raio: Raio.controle)
            }

            ConteudoDaCarga(
                carga: store.carga,
                linhasDeEsqueleto: 6,
                tentarDeNovo: { Task { await store.carregar() } }
            ) { ficha in
                conteudo(ficha)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { if store.carga.valor == nil { await store.carregar() } }
        .encerraSessaoNo401(store.carga.erro)
        .avisoTemporario($aviso)
        .sheet(item: $folha) { f in
            folhaView(f).presentationDetents([.large])
        }
        .confirmationDialog(
            remocao?.pergunta ?? "",
            isPresented: Binding(get: { remocao != nil }, set: { if !$0 { remocao = nil } }),
            titleVisibility: .visible,
            presenting: remocao
        ) { r in
            // Sem `role: .destructive`: o vermelho do sistema é faixa clínica neste app.
            Button(r.acao) { Task { await remover(r) } }
            Button("Manter", role: .cancel) {}
        } message: { _ in
            Text("A remoção vale para toda a equipe e não tem desfazer.")
        }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private func conteudo(_ ficha: FichaDoCadastro) -> some View {
        IdentificacaoDaFicha(ficha: ficha)

        BotaoSecundario(titulo: "Editar cadastro", icone: "pencil") {
            Tato.selecao()
            folha = .editar(ficha)
        }

        contatos(ficha)
        itensClinicos(titulo: "Alergias", itens: ficha.alergias, acao: "Registrar alergia",
                      vazio: "Nenhuma alergia registrada. Se o paciente negou alergias, isso também é informação — registre “Nega alergias”.") {
            folha = .alergia
        } remover: { remocao = .alergia($0) }
        itensClinicos(titulo: "Comorbidades", itens: ficha.comorbidades, acao: "Registrar comorbidade",
                      vazio: "Nenhuma comorbidade registrada.") {
            folha = .comorbidade
        } remover: { remocao = .comorbidade($0) }
        HistoriaDeVida(ficha: ficha)
        agenda

        Text("Cadastrado em \(Formato.diaCompleto(ficha.criadoEm)).")
            .font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
            .padding(.horizontal, 4)
    }

    private func contatos(_ ficha: FichaDoCadastro) -> some View {
        let todos = ficha.contatos.doPaciente + ficha.contatos.deEmergencia
        return VStack(alignment: .leading, spacing: 10) {
            CabecalhoComAcao(titulo: "Contatos", contagem: todos.count, acao: "Adicionar contato") {
                folha = .contato
            }
            VStack(alignment: .leading, spacing: 0) {
                GrupoDeContatos(titulo: "Do paciente", contatos: ficha.contatos.doPaciente,
                                vazio: "Sem telefone do próprio paciente.") { remocao = .contato($0) }
                Rectangle().fill(Cor.filete).frame(height: 0.75)
                GrupoDeContatos(titulo: "De emergência", contatos: ficha.contatos.deEmergencia,
                                vazio: "Sem contato de emergência: numa urgência, não há para quem ligar.") { remocao = .contato($0) }
            }
            .superficie()
        }
    }

    private func itensClinicos(
        titulo: String, itens: [ItemClinicoDoCadastro], acao: String, vazio: String,
        adicionar: @escaping () -> Void, remover: @escaping (ItemClinicoDoCadastro) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CabecalhoComAcao(titulo: titulo, contagem: itens.count, acao: acao, adicionar: adicionar)
            VStack(alignment: .leading, spacing: 0) {
                if itens.isEmpty {
                    Text(vazio)
                        .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Espaco.l)
                } else {
                    ForEach(Array(itens.enumerated()), id: \.element.id) { i, item in
                        LinhaRemovivel(
                            rotuloDeRemocao: "Remover \(titulo.lowercased().dropLast()) \(item.descricao)",
                            ultima: i == itens.count - 1,
                            remover: { remover(item) }
                        ) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.descricao).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                                Text("\(item.origem.nome) · \(item.confirmada ? "confirmada" : "não confirmada") · \(Formato.diaCompleto(item.criadaEm))")
                                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie()
        }
    }

    private var agenda: some View {
        let eventos = store.eventos
        return VStack(alignment: .leading, spacing: 10) {
            CabecalhoComAcao(titulo: "Agenda", contagem: eventos.isEmpty ? nil : eventos.count, acao: "Agendar") {
                folha = .novoEvento
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(eventos.enumerated()), id: \.element.id) { i, evento in
                    LinhaRemovivel(
                        rotuloDeRemocao: "Remover \(evento.tipo.nome.lowercased())",
                        ultima: false,
                        remover: { remocao = .evento(evento) }
                    ) {
                        Button {
                            Tato.selecao()
                            folha = .editarEvento(evento)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: evento.tipo.icone)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Cor.azulProfundo)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Cor.azulGelo.opacity(0.35)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(evento.tipo.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                                    Text(InstanteDoCadastro.exibir(evento.aconteceEm))
                                        .font(Tipo.apoio).monospacedDigit().foregroundStyle(Cor.textoSuave)
                                    if let local = evento.local {
                                        Text(local).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pressionavel)
                        .accessibilityHint("Abre a edição do evento")
                    }
                    .entradaEscalonada(i)
                }
                Text(eventos.isEmpty
                     ? "O AUREA ainda não devolve a agenda para o perfil administrativo. O que você agendar aqui aparece nesta ficha até o app fechar — para corrigir, é nessa janela."
                     : "Só aparecem os eventos agendados neste aparelho desde que o app abriu: o AUREA ainda não devolve a agenda para o perfil administrativo.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Espaco.l)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie()
        }
    }

    // MARK: Folhas

    @ViewBuilder
    private func folhaView(_ f: FolhaDaFicha) -> some View {
        switch f {
        case .editar(let ficha):
            FormularioDeEdicaoDoPaciente(ficha: ficha, store: store) { concluir("Cadastro atualizado.") }
        case .contato:
            FormularioDeContato(store: store) { concluir("Contato adicionado.") }
        case .alergia:
            FormularioDeAlergia(store: store) { concluir("Alergia registrada.") }
        case .comorbidade:
            FormularioDeComorbidade(store: store) { concluir("Comorbidade registrada.") }
        case .novoEvento:
            FormularioDeEvento(pacienteId: store.pacienteId, evento: nil, store: store) { concluir("Evento agendado.") }
        case .editarEvento(let evento):
            FormularioDeEvento(pacienteId: store.pacienteId, evento: evento, store: store) { concluir("Evento alterado.") }
        }
    }

    private func concluir(_ mensagem: String) {
        folha = nil
        erroDeRemocao = nil
        Tato.sucesso()
        aviso = mensagem
        Task { await aoAlterar() }
    }

    private func remover(_ r: RemocaoNaFicha) async {
        guard !removendo else { return }
        removendo = true
        defer { removendo = false }
        do {
            try await store.remover(r)
            erroDeRemocao = nil
            Tato.sucesso()
            aviso = r.feito
        } catch {
            Tato.erro()
            withAnimation(Movimento.chegada) { erroDeRemocao = ErroDoCadastro.mensagem(error) }
        }
    }
}

// MARK: - Identificação

/// O destaque da ficha: o que identifica a pessoa e o que falta para ela ser tratada.
private struct IdentificacaoDaFicha: View {
    let ficha: FichaDoCadastro
    @State private var cpfVisivel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CPF · login do paciente").estiloDeRotulo()
                    Text(cpfVisivel ? CPFDoCadastro.formatado(ficha.cpf) : CPFDoCadastro.mascarado(ficha.cpf))
                        .font(Tipo.colunaForte)
                        .foregroundStyle(Cor.texto)
                        .contentTransition(.opacity)
                        .privacySensitive()
                }
                Spacer()
                Button {
                    Tato.selecao()
                    withAnimation(Movimento.toque) { cpfVisivel.toggle() }
                } label: {
                    Image(systemName: cpfVisivel ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cor.azulProfundo)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressionavel)
                .accessibilityLabel(cpfVisivel ? "Ocultar CPF" : "Mostrar CPF")
            }

            Rectangle().fill(Cor.filete).frame(height: 0.75)

            VStack(alignment: .leading, spacing: 10) {
                Dado(rotulo: "Nascimento", valor: "\(DataCivil.numerica(ficha.dataNascimento)) · \(DataCivil.idade(ficha.dataNascimento)) anos")
                Dado(rotulo: "Sexo", valor: ficha.sexo.nome)
                Dado(rotulo: "Convênio", valor: ficha.convenio ?? "não informado", fraco: ficha.convenio == nil)
                Dado(rotulo: "Tipo sanguíneo", valor: ficha.tipoSanguineo ?? "não informado", fraco: ficha.tipoSanguineo == nil)
                Dado(rotulo: "Hábito intestinal basal",
                     valor: ficha.habitoIntestinalBasal.map { "\($0) \($0 == 1 ? "evacuação" : "evacuações") por dia" }
                        ?? "não informado — diarreia sem referência para comparar",
                     fraco: ficha.habitoIntestinalBasal == nil)
                Dado(rotulo: "Tratamento",
                     valor: ficha.tratamento.map { "\($0.protocolo.nome), desde \(DataCivil.numerica($0.iniciadoEm))" }
                        ?? "sem tratamento ativo — não entra em tratamento",
                     fraco: ficha.tratamento == nil)
            }
        }
        .padding(Espaco.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartaoDestaque(tom: Cor.auroraIndigo)
    }
}

private struct Dado: View {
    let rotulo: String
    let valor: String
    var fraco = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rotulo).estiloDeRotulo()
            Text(valor)
                .font(fraco ? Tipo.apoio : Tipo.corpo)
                .monospacedDigit()
                .foregroundStyle(fraco ? Cor.textoFraco : Cor.texto)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Blocos

private struct CabecalhoComAcao: View {
    let titulo: String
    var contagem: Int?
    let acao: String
    let adicionar: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            CabecalhoDeSecao(titulo: titulo, contagem: contagem)
            BotaoDeAcaoEmLinha(titulo: acao, icone: "plus", acao: adicionar)
        }
        .padding(.top, Espaco.s)
    }
}

/// Linha com a lixeira à direita. Lista em `VStack` não tem `swipeActions` — e o gesto
/// escondido é o pior lugar para uma ação que apaga dado de paciente. A lixeira fica à
/// vista, discreta, e sempre pede confirmação.
private struct LinhaRemovivel<Conteudo: View>: View {
    let rotuloDeRemocao: String
    var ultima = false
    let remover: () -> Void
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                conteudo.frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Tato.selecao()
                    remover()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Cor.textoFraco)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressionavel)
                .accessibilityLabel(rotuloDeRemocao)
            }
            .padding(.leading, Espaco.l)
            .padding(.trailing, Espaco.xs)
            .padding(.vertical, 8)
            if !ultima {
                Rectangle().fill(Cor.filete).frame(height: 0.75).padding(.leading, Espaco.l)
            }
        }
    }
}

private struct GrupoDeContatos: View {
    let titulo: String
    let contatos: [ContatoDoCadastro]
    let vazio: String
    let remover: (ContatoDoCadastro) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titulo).estiloDeRotulo()
                .padding(.horizontal, Espaco.l)
                .padding(.top, 14)
                .padding(.bottom, contatos.isEmpty ? 4 : 0)
            if contatos.isEmpty {
                Text(vazio)
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Espaco.l)
                    .padding(.bottom, 14)
            } else {
                ForEach(Array(contatos.enumerated()), id: \.element.id) { i, c in
                    LinhaRemovivel(rotuloDeRemocao: "Remover o contato \(c.nome)",
                                   ultima: i == contatos.count - 1,
                                   remover: { remover(c) }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                            Text([Formato.telefone(c.telefone), c.relacao].compactMap { $0 }.joined(separator: " · "))
                                .font(Tipo.apoio).monospacedDigit().foregroundStyle(Cor.textoSuave)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct HistoriaDeVida: View {
    let ficha: FichaDoCadastro

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CabecalhoDeSecao(titulo: "História de vida").padding(.top, Espaco.s)
            VStack(alignment: .leading, spacing: 10) {
                Dado(rotulo: "Tabagismo", valor: tabagismo, fraco: ficha.tabagismo == .naoInformado)
                Dado(rotulo: "Atividade física", valor: atividade, fraco: ficha.atividadeFisica == .naoInformado)
                Dado(rotulo: "Álcool", valor: ficha.consumoDeAlcool.nome, fraco: ficha.consumoDeAlcool == .naoInformado)
                Text("“Não informado” quer dizer que ninguém perguntou — não que a pessoa negou. Para mudar, use Editar cadastro.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(Espaco.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie()
        }
    }

    private var tabagismo: String {
        if ficha.tabagismo == .exFumante, let parou = ficha.parouDeFumarEm {
            return "Ex-fumante, parou em \(DataCivil.numerica(parou))"
        }
        return ficha.tabagismo.nome
    }

    private var atividade: String {
        guard let d = ficha.descricaoDaAtividade else { return ficha.atividadeFisica.nome }
        return "\(ficha.atividadeFisica.nome) · \(d)"
    }
}
