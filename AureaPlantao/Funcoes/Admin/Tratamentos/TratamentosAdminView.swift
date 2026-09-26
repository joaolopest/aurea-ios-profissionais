import SwiftUI

@MainActor
@Observable
final class TratamentosAdminStore {
    private(set) var carga: Carga<[TratamentoAdmin]> = .carregando
    private let api: ClienteAPI

    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/admin/tratamentos"))
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o cadastro de tratamentos."), anterior: anterior)
        }
    }

    /// Abre o tratamento e confere na lista relida que ele ficou gravado — o web mostrava
    /// "adicionado" e não gravava nada.
    func criar(pacienteId: String, protocoloId: String, iniciadoEm: Date) async -> String? {
        struct Corpo: Encodable, Sendable { let pacienteId: String; let protocoloId: String; let iniciadoEm: String }
        do {
            let criado: TratamentoAdmin = try await api.enviar(
                "/admin/tratamentos",
                corpo: Corpo(pacienteId: pacienteId, protocoloId: protocoloId, iniciadoEm: DataCivil.paraAPI(iniciadoEm))
            )
            await carregar()
            guard carga.valor?.contains(where: { $0.id == criado.id && $0.ativo }) == true else {
                return "O AUREA respondeu, mas o tratamento não apareceu na lista. Puxe para atualizar antes de tentar de novo."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(
                ErroDaAPI(error),
                conflito: "Este paciente já está em tratamento ativo. Encerre-o antes de iniciar outro.",
                recusado: "O AUREA recusou os dados do tratamento. Confira paciente, protocolo e data."
            )
        }
    }

    func encerrar(_ tratamento: TratamentoAdmin) async -> String? {
        do {
            let _: TratamentoEncerrado = try await api.atualizar("/admin/tratamentos/\(tratamento.id)/encerrar", corpo: Vazio())
            await carregar()
            guard carga.valor?.first(where: { $0.id == tratamento.id })?.ativo == false else {
                return "O AUREA respondeu, mas o tratamento lido de volta continua ativo. Puxe para atualizar e confira."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(ErroDaAPI(error), conflito: "Este tratamento já estava encerrado.")
        }
    }
}

/// Tratamentos: liga um paciente a um protocolo. Um paciente tem no máximo UM tratamento
/// ativo — com dois, a triagem não saberia que protocolo vale para o dia do ciclo.
struct TratamentosAdminView: View {
    @State private var store = TratamentosAdminStore()
    @State private var filtro: Filtro = .ativos
    @State private var criando = false
    @State private var aberto: TratamentoAdmin?
    @State private var ciclosDe: TratamentoAdmin?
    @State private var aviso: String?

    enum Filtro: Hashable { case ativos, encerrados, todos }

    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Cadastros",
                titulo: "Tratamentos",
                contexto: "Liga um paciente a um protocolo. Cada paciente tem no máximo um tratamento em andamento."
            )

            BotaoDeAcaoEmLinha(titulo: "Novo tratamento") { criando = true }

            ConteudoDaCarga(
                carga: store.carga,
                vazio: { $0.isEmpty },
                tituloVazio: "Nenhum tratamento cadastrado.",
                textoVazio: "Sem tratamento, o paciente não tem dia do ciclo e a triagem não sabe o protocolo. Abra o primeiro.",
                iconeVazio: "cross.vial",
                tentarDeNovo: { Task { await store.carregar() } }
            ) { tratamentos in
                indicadores(tratamentos)
                SeletorDePilulas(opcoes: [
                    OpcaoDeSeletor(id: Filtro.ativos, titulo: "Em andamento", contador: tratamentos.filter(\.ativo).count),
                    OpcaoDeSeletor(id: Filtro.encerrados, titulo: "Encerrados", contador: tratamentos.filter { !$0.ativo }.count),
                    OpcaoDeSeletor(id: Filtro.todos, titulo: "Todos", contador: tratamentos.count),
                ], selecionado: $filtro)
                .padding(.horizontal, -Espaco.margem)
                lista(filtrados(tratamentos))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(item: $ciclosDe) { CiclosAdminView(tratamento: $0) }
        .task { await store.carregar() }
        .avisoTemporario($aviso)
        .sheet(isPresented: $criando) {
            FolhaDeNovoTratamento(store: store) { mensagem in
                criando = false
                Tato.sucesso()
                aviso = mensagem
            }
        }
        .sheet(item: $aberto) { t in
            FolhaDoTratamento(tratamento: t, store: store, verCiclos: {
                aberto = nil
                ciclosDe = t
            }, encerrado: { mensagem in
                aberto = nil
                Tato.sucesso()
                aviso = mensagem
            })
        }
    }

    private func filtrados(_ lista: [TratamentoAdmin]) -> [TratamentoAdmin] {
        switch filtro {
        case .ativos: lista.filter(\.ativo)
        case .encerrados: lista.filter { !$0.ativo }
        case .todos: lista
        }
    }

    /// O total e como ele se divide: em andamento é quem o plantão acompanha hoje;
    /// encerrado sai da fila sem sumir do histórico; sem médico é lacuna de cadastro.
    private func indicadores(_ lista: [TratamentoAdmin]) -> some View {
        let ativos = lista.filter(\.ativo)
        return GradeDeIndicadoresDeCadastro(itens: [
            .init(rotulo: "Tratamentos", valor: "\(lista.count)"),
            .init(rotulo: "Em andamento", valor: "\(ativos.count)", apoio: "acompanhados pelo plantão"),
            .init(rotulo: "Encerrados", valor: "\(lista.count - ativos.count)", apoio: "fora da fila, no histórico"),
            .init(rotulo: "Sem médico", valor: "\(ativos.filter { $0.medicoResponsavel == nil }.count)", apoio: "em andamento sem responsável nomeado"),
        ])
    }

    @ViewBuilder
    private func lista(_ tratamentos: [TratamentoAdmin]) -> some View {
        if tratamentos.isEmpty {
            EstadoVazio(
                titulo: filtro == .encerrados ? "Nenhum tratamento encerrado." : "Nenhum tratamento em andamento.",
                texto: filtro == .encerrados ? "Quando um tratamento terminar, ele aparece aqui." : "Ninguém está em tratamento ativo agora.",
                icone: "cross.vial"
            )
            .superficie()
        } else {
            VStack(spacing: Espaco.s) {
                ForEach(Array(tratamentos.enumerated()), id: \.element.id) { i, t in
                    Button {
                        Tato.selecao()
                        aberto = t
                    } label: {
                        LinhaDeTratamento(tratamento: t)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
            .animation(Movimento.interface, value: tratamentos.map(\.id))
        }
    }
}

private struct LinhaDeTratamento: View {
    let tratamento: TratamentoAdmin

    var body: some View {
        LinhaPadrao(avatar: tratamento.paciente.nome, titulo: tratamento.paciente.nome, apoio: apoio) {
            if !tratamento.ativo { EtiquetaDeCadastro(texto: "Encerrado") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tratamento.paciente.nome). \(tratamento.protocolo.nome), início em \(DataCivil.porExtenso(tratamento.iniciadoEm))\(tratamento.ativo ? "" : ". Encerrado")")
        .accessibilityHint("Abre o tratamento")
    }

    private var apoio: String {
        var partes = [tratamento.protocolo.nome, "desde \(DataCivil.numerica(tratamento.iniciadoEm))"]
        if let medico = tratamento.medicoResponsavel { partes.append(medico.nome) }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Detalhe do tratamento

private struct FolhaDoTratamento: View {
    let tratamento: TratamentoAdmin
    let store: TratamentosAdminStore
    let verCiclos: () -> Void
    let encerrado: (String) -> Void

    @State private var confirmando = false
    @State private var encerrando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: tratamento.ativo ? "Tratamento em andamento" : "Tratamento encerrado",
            titulo: tratamento.paciente.nome,
            acao: "Ver ciclos",
            icone: "arrow.triangle.2.circlepath",
            erro: erro,
            enviar: verCiclos
        ) {
            VStack(alignment: .leading, spacing: Espaco.s) {
                LinhaDeFichaDeCadastro(rotulo: "Protocolo", valor: tratamento.protocolo.nome)
                LinhaDeFichaDeCadastro(rotulo: "Início", valor: DataCivil.numerica(tratamento.iniciadoEm))
                LinhaDeFichaDeCadastro(
                    rotulo: "Médico responsável",
                    valor: tratamento.medicoResponsavel.map { "\($0.nome) · \($0.funcao.nome)" } ?? "Não nomeado"
                )
                LinhaDeFichaDeCadastro(rotulo: "Situação", valor: tratamento.ativo ? "Em andamento" : "Encerrado")
            }
            .padding(Espaco.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie(raio: Raio.linha)

            if tratamento.ativo {
                VStack(alignment: .leading, spacing: Espaco.s) {
                    CabecalhoDeSecao(titulo: "Encerrar")
                    BotaoSecundario(titulo: encerrando ? "Encerrando…" : "Encerrar tratamento", icone: "stop.circle") {
                        Tato.selecao()
                        confirmando = true
                    }
                    .disabled(encerrando)
                    Text("Encerra com a data de hoje. O paciente sai do dia do ciclo e fica livre para um tratamento novo.")
                        .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Espaco.s)
            }
        }
        .presentationDetents([.large])
        .confirmationDialog(
            "Encerrar o tratamento de \(tratamento.paciente.nome)?",
            isPresented: $confirmando,
            titleVisibility: .visible
        ) {
            Button("Encerrar com a data de hoje") { Task { await encerrar() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(tratamento.protocolo.nome) deixa de valer para a triagem e o dia do ciclo. O AUREA não reabre tratamento encerrado.")
        }
    }

    private func encerrar() async {
        encerrando = true
        erro = nil
        let resultado = await store.encerrar(tratamento)
        encerrando = false
        if let resultado {
            Tato.erro()
            erro = resultado
        } else {
            encerrado("Tratamento de \(tratamento.paciente.nome) encerrado.")
        }
    }
}

// MARK: - Novo tratamento

private struct FolhaDeNovoTratamento: View {
    let store: TratamentosAdminStore
    let concluir: (String) -> Void

    @State private var paciente: PacienteParaEscolha?
    @State private var protocoloId: String?
    @State private var inicio = Date.now
    @State private var protocolos: Carga<[ProtocoloDoCatalogo]> = .carregando
    @State private var escolhendoPaciente = false
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Tratamentos",
            titulo: "Novo tratamento",
            acao: "Abrir tratamento",
            icone: "cross.vial",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEscolhaPorFolha(rotulo: "Paciente", valor: paciente?.nome, dica: "Escolher paciente") {
                escolhendoPaciente = true
            }

            if let lista = protocolos.valor {
                let ativos = lista.filter(\.ativo)
                CampoDeEscolha(
                    rotulo: "Protocolo",
                    opcoes: ativos.map { (valor: $0.id, nome: $0.nome) },
                    selecionado: $protocoloId,
                    dica: ativos.isEmpty ? "Nenhum protocolo ativo" : "Escolher protocolo"
                )
            } else if let falha = protocolos.erro {
                Label(falha.mensagem, systemImage: "wifi.exclamationmark")
                    .font(Tipo.apoio).foregroundStyle(Cor.texto)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Protocolo").estiloDeRotulo()
                    Esqueleto(altura: 52)
                }
            }

            CampoDeData(rotulo: "Início do tratamento", data: $inicio)
        }
        .presentationDetents([.large])
        .task { await carregarProtocolos() }
        .sheet(isPresented: $escolhendoPaciente) {
            SeletorDePacienteDoCadastro(
                titulo: "Quem começa o tratamento?",
                indisponivel: { p in
                    p.protocolo.map { "Já em tratamento (\($0.nome)). Encerre-o antes." }
                },
                escolher: { paciente = $0 }
            )
        }
    }

    private func carregarProtocolos() async {
        do {
            protocolos = .pronto(try await ClienteAPI.compartilhado.obter("/admin/protocolos"))
        } catch {
            protocolos = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui a lista de protocolos."), anterior: nil)
        }
    }

    private func enviar() async {
        guard let paciente else { return falhar("Escolha o paciente.") }
        guard let protocoloId else { return falhar("Escolha o protocolo.") }

        enviando = true
        erro = nil
        let resultado = await store.criar(pacienteId: paciente.id, protocoloId: protocoloId, iniciadoEm: inicio)
        enviando = false
        if let resultado { return falhar(resultado) }
        concluir("Tratamento de \(paciente.nome) aberto.")
    }

    private func falhar(_ mensagem: String) {
        Tato.erro()
        erro = mensagem
    }
}
