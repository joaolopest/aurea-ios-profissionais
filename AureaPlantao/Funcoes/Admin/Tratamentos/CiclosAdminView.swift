import SwiftUI

@MainActor
@Observable
final class CiclosAdminStore {
    private(set) var carga: Carga<[CicloAdmin]>? = nil
    private(set) var tratamento: TratamentoAdmin?
    private let api: ClienteAPI

    nonisolated init(tratamento: TratamentoAdmin? = nil, api: ClienteAPI = .compartilhado) {
        self.api = api
        self._tratamento = tratamento
    }

    func escolher(_ t: TratamentoAdmin) async {
        tratamento = t
        carga = .carregando
        await carregar()
    }

    func carregar() async {
        guard let tratamento else { return }
        let anterior = carga?.valor
        do {
            carga = .pronto(try await api.obter("/admin/tratamentos/\(tratamento.id)/ciclos"))
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o cadastro de ciclos."), anterior: anterior)
        }
    }

    var proximoNumero: Int { (carga?.valor?.map(\.numero).max() ?? 0) + 1 }

    func numeroJaExiste(_ n: Int) -> Bool { carga?.valor?.contains { $0.numero == n } == true }

    private struct CorpoDeCriacao: Encodable, Sendable {
        let numero: Int
        let sessaoRealizadaEm: String
        let previsaoDaProximaSessao: String?
    }

    /// Codifica `previsaoDaProximaSessao: null` de propósito: no PATCH, `null` apaga a
    /// previsão e a chave ausente deixa como está — são coisas diferentes.
    private struct CorpoDeEdicao: Encodable, Sendable {
        let sessaoRealizadaEm: String
        let previsaoDaProximaSessao: String?

        enum CodingKeys: String, CodingKey { case sessaoRealizadaEm, previsaoDaProximaSessao }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(sessaoRealizadaEm, forKey: .sessaoRealizadaEm)
            try c.encode(previsaoDaProximaSessao, forKey: .previsaoDaProximaSessao)
        }
    }

    func criar(numero: Int, sessao: Date, previsao: Date?) async -> String? {
        guard let tratamento else { return "Escolha o tratamento." }
        do {
            let criado: CicloAdmin = try await api.enviar(
                "/admin/tratamentos/\(tratamento.id)/ciclos",
                corpo: CorpoDeCriacao(
                    numero: numero,
                    sessaoRealizadaEm: DataCivil.paraAPI(sessao),
                    previsaoDaProximaSessao: previsao.map(DataCivil.paraAPI)
                )
            )
            await carregar()
            guard carga?.valor?.contains(where: { $0.id == criado.id }) == true else {
                return "O AUREA respondeu, mas o ciclo não apareceu na lista. Puxe para atualizar antes de tentar de novo."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(
                ErroDaAPI(error),
                conflito: "Este tratamento já tem um ciclo com este número.",
                recusado: "O AUREA recusou os dados do ciclo. Confira o número e as datas."
            )
        }
    }

    func editar(_ ciclo: CicloAdmin, sessao: Date, previsao: Date?) async -> String? {
        let sessaoTexto = DataCivil.paraAPI(sessao)
        let previsaoTexto = previsao.map(DataCivil.paraAPI)
        do {
            let _: CicloAdmin = try await api.atualizar(
                "/admin/ciclos/\(ciclo.id)",
                corpo: CorpoDeEdicao(sessaoRealizadaEm: sessaoTexto, previsaoDaProximaSessao: previsaoTexto)
            )
            await carregar()
            guard let lido = carga?.valor?.first(where: { $0.id == ciclo.id }),
                  DataCivil.chave(lido.sessaoRealizadaEm) == sessaoTexto,
                  lido.previsaoDaProximaSessao.map(DataCivil.chave) == previsaoTexto else {
                return "O AUREA respondeu, mas o ciclo lido de volta não bate com o que foi salvo. Puxe para atualizar e confira."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(ErroDaAPI(error), recusado: "O AUREA recusou as datas. Confira e tente de novo.")
        }
    }
}

/// Ciclos: a sessão realizada dentro de um tratamento e a previsão da próxima. É daqui que
/// sai o "dia do ciclo" que a triagem usa.
struct CiclosAdminView: View {
    @State private var store: CiclosAdminStore
    @State private var escolhendo = false
    @State private var registrando = false
    @State private var editando: CicloAdmin?
    @State private var aviso: String?

    nonisolated init() {
        _store = State(initialValue: CiclosAdminStore())
    }

    /// Entrada vinda de Tratamentos, com o tratamento já escolhido.
    nonisolated init(tratamento: TratamentoAdmin) {
        _store = State(initialValue: CiclosAdminStore(tratamento: tratamento))
    }

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Cadastros",
                titulo: "Ciclos",
                contexto: "Registra a sessão realizada dentro de um tratamento e projeta a próxima."
            )

            CartaoDeEscolhaDeCadastro(
                rotulo: "Tratamento",
                titulo: store.tratamento?.paciente.nome,
                apoio: store.tratamento.map { t in
                    "\(t.protocolo.nome) · desde \(DataCivil.numerica(t.iniciadoEm))\(t.ativo ? "" : " · encerrado")"
                },
                convite: "Escolher tratamento",
                textoVazio: "Ciclo pertence a um tratamento. Escolha de quem são os ciclos que você quer ver ou registrar.",
                icone: "arrow.triangle.2.circlepath",
                escolher: { escolhendo = true }
            )

            if let carga = store.carga {
                BotaoDeAcaoEmLinha(titulo: "Registrar ciclo") { registrando = true }

                ConteudoDaCarga(
                    carga: carga,
                    vazio: { $0.isEmpty },
                    tituloVazio: "Nenhum ciclo registrado.",
                    textoVazio: "Registre a primeira sessão feita neste tratamento para o dia do ciclo começar a contar.",
                    iconeVazio: "arrow.triangle.2.circlepath",
                    tentarDeNovo: { Task { await store.carregar() } }
                ) { ciclos in
                    indicadores(ciclos)
                    CabecalhoDeSecao(titulo: "Ciclos deste tratamento", contagem: ciclos.count)
                        .padding(.top, Espaco.s)
                    VStack(spacing: Espaco.s) {
                        ForEach(Array(ciclos.enumerated()), id: \.element.id) { i, c in
                            Button {
                                Tato.selecao()
                                editando = c
                            } label: {
                                LinhaDeCiclo(ciclo: c, ehOUltimo: c.id == ciclos.max(by: { $0.numero < $1.numero })?.id)
                            }
                            .buttonStyle(.pressionavel)
                            .entradaEscalonada(i)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { if store.carga == nil, let t = store.tratamento { await store.escolher(t) } }
        .avisoTemporario($aviso)
        .sheet(isPresented: $escolhendo) {
            SeletorDeTratamentoDoCadastro { t in Task { await store.escolher(t) } }
        }
        .sheet(isPresented: $registrando) {
            FolhaDeCiclo(store: store, ciclo: nil) { mensagem in
                registrando = false
                Tato.sucesso()
                aviso = mensagem
            }
        }
        .sheet(item: $editando) { c in
            FolhaDeCiclo(store: store, ciclo: c) { mensagem in
                editando = nil
                Tato.sucesso()
                aviso = mensagem
            }
        }
    }

    /// Por tratamento, a pergunta é QUANDO: a última sessão e a próxima. A previsão que
    /// conta é a do último ciclo — as anteriores já foram cumpridas pelo ciclo seguinte.
    /// Previsão vencida é a do último ciclo que passou sem sessão registrada.
    private func indicadores(_ ciclos: [CicloAdmin]) -> some View {
        let ultimo = ciclos.max { $0.numero < $1.numero }
        let proxima: GradeDeIndicadoresDeCadastro.Item = {
            guard let previsao = ultimo?.previsaoDaProximaSessao else {
                return .init(rotulo: "Próxima sessão", valor: "—", apoio: "sem previsão: fora da agenda")
            }
            let vencida = DataCivil.chave(previsao) < DataCivil.hoje
            return .init(rotulo: "Próxima sessão", valor: DataCivil.curta(previsao),
                         apoio: vencida ? "vencida: a data passou sem sessão registrada" : "prevista, não agendada")
        }()
        return GradeDeIndicadoresDeCadastro(itens: [
            .init(rotulo: "Ciclos", valor: "\(ciclos.count)", apoio: ultimo.map { "o atual é o \($0.numero)º" }),
            .init(rotulo: "Última sessão", valor: ultimo.map { DataCivil.curta($0.sessaoRealizadaEm) } ?? "—",
                  apoio: ultimo.map { "ciclo \($0.numero)" }),
            proxima,
        ])
    }
}

private struct LinhaDeCiclo: View {
    let ciclo: CicloAdmin
    let ehOUltimo: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(ciclo.numero)")
                .font(Tipo.destaque)
                .monospacedDigit()
                .foregroundStyle(Cor.azulProfundo)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Cor.azulGelo.opacity(0.35)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Ciclo \(ciclo.numero)").font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                Text("Sessão em \(DataCivil.numerica(ciclo.sessaoRealizadaEm))")
                    .font(Tipo.apoio).monospacedDigit().foregroundStyle(Cor.textoSuave)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("Próxima").estiloDeRotulo()
                Text(ciclo.previsaoDaProximaSessao.map(DataCivil.numerica) ?? "sem previsão")
                    .font(Tipo.apoioForte).monospacedDigit()
                    .foregroundStyle(ehOUltimo ? Cor.texto : Cor.textoFraco)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ciclo \(ciclo.numero). Sessão em \(DataCivil.porExtenso(ciclo.sessaoRealizadaEm)). \(ciclo.previsaoDaProximaSessao.map { "Próxima prevista para \(DataCivil.porExtenso($0))" } ?? "Sem previsão da próxima")")
        .accessibilityHint("Abre para corrigir as datas")
    }
}

// MARK: - Registrar ou corrigir ciclo

private struct FolhaDeCiclo: View {
    let store: CiclosAdminStore
    let ciclo: CicloAdmin?
    let concluir: (String) -> Void

    @State private var numero: Int
    @State private var sessao: Date
    @State private var temPrevisao: Bool
    @State private var previsao: Date
    @State private var enviando = false
    @State private var erro: String?

    init(store: CiclosAdminStore, ciclo: CicloAdmin?, concluir: @escaping (String) -> Void) {
        self.store = store
        self.ciclo = ciclo
        self.concluir = concluir
        let sessaoInicial = ciclo.map { DataCivil.paraSeletor($0.sessaoRealizadaEm) } ?? .now
        _numero = State(initialValue: ciclo?.numero ?? store.proximoNumero)
        _sessao = State(initialValue: sessaoInicial)
        _temPrevisao = State(initialValue: ciclo?.previsaoDaProximaSessao != nil)
        _previsao = State(initialValue: ciclo?.previsaoDaProximaSessao.map(DataCivil.paraSeletor)
                          ?? Calendar.current.date(byAdding: .day, value: 21, to: sessaoInicial) ?? sessaoInicial)
    }

    var body: some View {
        FolhaDeFormulario(
            rotulo: store.tratamento?.paciente.nome,
            titulo: ciclo.map { "Ciclo \($0.numero)" } ?? "Registrar ciclo",
            acao: ciclo == nil ? "Registrar ciclo" : "Salvar datas",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            if ciclo == nil {
                CampoNumerico(rotulo: "Número do ciclo", valor: $numero, faixa: 1...99)
            }
            CampoDeData(rotulo: "Data da sessão realizada", data: $sessao, intervalo: Date.distantPast...Date.now)
            CampoInterruptor(
                titulo: "Já há previsão da próxima sessão",
                explicacao: "É previsão, não compromisso agendado: a data real depende de exame, de contagem de leucócitos e da agenda do serviço.",
                ligado: $temPrevisao
            )
            if temPrevisao {
                CampoDeData(rotulo: "Previsão da próxima sessão", data: $previsao, intervalo: sessao...Date.distantFuture)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Movimento.interface, value: temPrevisao)
        .presentationDetents([.large])
    }

    private func enviar() async {
        let previsaoFinal = temPrevisao ? previsao : nil
        if let previsaoFinal, DataCivil.paraAPI(previsaoFinal) <= DataCivil.paraAPI(sessao) {
            return falhar("A previsão da próxima sessão precisa vir depois da sessão realizada.")
        }
        enviando = true
        erro = nil
        let resultado: String?
        if let ciclo {
            resultado = await store.editar(ciclo, sessao: sessao, previsao: previsaoFinal)
        } else {
            if store.numeroJaExiste(numero) {
                enviando = false
                return falhar("Este tratamento já tem o ciclo \(numero). Corrija as datas dele na lista, ou use outro número.")
            }
            resultado = await store.criar(numero: numero, sessao: sessao, previsao: previsaoFinal)
        }
        enviando = false
        if let resultado { return falhar(resultado) }
        concluir(ciclo == nil ? "Ciclo \(numero) registrado." : "Datas do ciclo \(numero) salvas.")
    }

    private func falhar(_ mensagem: String) {
        Tato.erro()
        erro = mensagem
    }
}

// MARK: - Escolha de tratamento

private struct SeletorDeTratamentoDoCadastro: View {
    let escolher: (TratamentoAdmin) -> Void

    @State private var carga: Carga<[TratamentoAdmin]> = .carregando
    @State private var busca = ""
    @Environment(\.dismiss) private var fechar

    var body: some View {
        FolhaDeEscolhaDeCadastro(rotulo: "Tratamentos", titulo: "De quem são os ciclos?", busca: $busca) {
            ConteudoDaCarga(
                carga: carga,
                linhasDeEsqueleto: 6,
                vazio: { $0.isEmpty },
                tituloVazio: "Nenhum tratamento cadastrado.",
                textoVazio: "Abra um tratamento em Cadastros › Tratamentos antes de registrar ciclo.",
                iconeVazio: "cross.vial",
                tentarDeNovo: { Task { await carregar() } }
            ) { lista in
                let filtrados = lista.filter {
                    casaComBuscaDeCadastro($0.paciente.nome, busca) || casaComBuscaDeCadastro($0.protocolo.nome, busca)
                }
                if filtrados.isEmpty {
                    Text("Nenhum tratamento com “\(busca)”.")
                        .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        .padding(.horizontal, 4)
                }
                LazyVStack(spacing: Espaco.s) {
                    ForEach(filtrados) { t in
                        Button {
                            Tato.selecao()
                            escolher(t)
                            fechar()
                        } label: {
                            LinhaPadrao(
                                avatar: t.paciente.nome,
                                titulo: t.paciente.nome,
                                apoio: "\(t.protocolo.nome) · desde \(DataCivil.numerica(t.iniciadoEm))",
                                mostrarSeta: false
                            ) {
                                if !t.ativo { EtiquetaDeCadastro(texto: "Encerrado") }
                            }
                        }
                        .buttonStyle(.pressionavel)
                        .accessibilityLabel("\(t.paciente.nome), \(t.protocolo.nome)\(t.ativo ? "" : ", encerrado")")
                    }
                }
            }
        }
        .task { await carregar() }
    }

    private func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await ClienteAPI.compartilhado.obter("/admin/tratamentos"))
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o cadastro de tratamentos."), anterior: anterior)
        }
    }
}
