import SwiftUI

@MainActor
@Observable
final class PrescricoesAdminStore {
    private(set) var carga: Carga<[PrescricaoAdmin]>? = nil
    private(set) var paciente: PacienteParaEscolha?
    private let api: ClienteAPI

    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func escolher(_ p: PacienteParaEscolha) async {
        paciente = p
        carga = .carregando
        await carregar()
    }

    func carregar() async {
        guard let paciente else { return }
        let anterior = carga?.valor
        do {
            carga = .pronto(try await api.obter("/admin/pacientes/\(paciente.id)/prescricoes"))
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o cadastro de prescrições."), anterior: anterior)
        }
    }

    func criar(medicamentoId: String, posologia: String, iniciadaEm: Date) async -> String? {
        guard let paciente else { return "Escolha o paciente." }
        struct Corpo: Encodable, Sendable { let medicamentoId: String; let posologia: String; let iniciadaEm: String }
        do {
            let criada: PrescricaoAdmin = try await api.enviar(
                "/admin/pacientes/\(paciente.id)/prescricoes",
                corpo: Corpo(medicamentoId: medicamentoId, posologia: posologia, iniciadaEm: DataCivil.paraAPI(iniciadaEm))
            )
            await carregar()
            guard carga?.valor?.contains(where: { $0.id == criada.id && $0.ativa }) == true else {
                return "O AUREA respondeu, mas a prescrição não apareceu na lista. Puxe para atualizar antes de tentar de novo."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(
                ErroDaAPI(error),
                recusado: "O AUREA recusou a prescrição. A posologia precisa ter entre 2 e 255 caracteres."
            )
        }
    }

    func encerrar(_ prescricao: PrescricaoAdmin) async -> String? {
        do {
            let _: PrescricaoEncerrada = try await api.atualizar("/admin/prescricoes/\(prescricao.id)/encerrar", corpo: Vazio())
            await carregar()
            guard carga?.valor?.first(where: { $0.id == prescricao.id })?.ativa == false else {
                return "O AUREA respondeu, mas a prescrição lida de volta continua ativa. Puxe para atualizar e confira."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(ErroDaAPI(error), conflito: "Esta prescrição já estava encerrada.")
        }
    }
}

/// Prescrições de um paciente. Importa além do prontuário: a orientação que o paciente lê
/// só nomeia remédio com prescrição ATIVA para ele.
struct PrescricoesAdminView: View {
    @State private var store = PrescricoesAdminStore()
    @State private var escolhendo = false
    @State private var criando = false
    @State private var aberta: PrescricaoAdmin?
    @State private var aviso: String?

    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Cadastros",
                titulo: "Prescrições",
                contexto: "Associa um medicamento e a posologia a um paciente. A orientação só cita remédio com prescrição ativa."
            )

            CartaoDeEscolhaDeCadastro(
                rotulo: "Paciente",
                titulo: store.paciente?.nome,
                apoio: store.paciente.map { $0.protocolo?.nome ?? $0.diagnostico },
                convite: "Escolher paciente",
                textoVazio: "Prescrição é de uma pessoa. Escolha o paciente para ver e registrar os remédios dele.",
                icone: "person.crop.circle",
                escolher: { escolhendo = true }
            )

            if let carga = store.carga {
                BotaoDeAcaoEmLinha(titulo: "Nova prescrição") { criando = true }

                ConteudoDaCarga(
                    carga: carga,
                    vazio: { $0.isEmpty },
                    tituloVazio: "Nenhuma prescrição.",
                    textoVazio: "Sem prescrição ativa, a orientação ao paciente não nomeia remédio nenhum.",
                    iconeVazio: "pills",
                    tentarDeNovo: { Task { await store.carregar() } }
                ) { prescricoes in
                    let ativas = prescricoes.filter(\.ativa)
                    let encerradas = prescricoes.filter { !$0.ativa }
                    GradeDeIndicadoresDeCadastro(itens: [
                        .init(rotulo: "Prescrições", valor: "\(prescricoes.count)"),
                        .init(rotulo: "Ativas", valor: "\(ativas.count)", apoio: "a orientação pode citar"),
                    ])
                    secao("Ativas", ativas)
                    secao("Encerradas", encerradas)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .avisoTemporario($aviso)
        .sheet(isPresented: $escolhendo) {
            SeletorDePacienteDoCadastro(titulo: "De quem são as prescrições?") { p in
                Task { await store.escolher(p) }
            }
        }
        .sheet(isPresented: $criando) {
            FolhaDeNovaPrescricao(store: store) { mensagem in
                criando = false
                Tato.sucesso()
                aviso = mensagem
            }
        }
        .sheet(item: $aberta) { p in
            FolhaDaPrescricao(prescricao: p, store: store) { mensagem in
                aberta = nil
                Tato.sucesso()
                aviso = mensagem
            }
        }
    }

    @ViewBuilder
    private func secao(_ titulo: String, _ lista: [PrescricaoAdmin]) -> some View {
        if !lista.isEmpty {
            CabecalhoDeSecao(titulo: titulo, contagem: lista.count)
                .padding(.top, Espaco.s)
            VStack(spacing: Espaco.s) {
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, p in
                    Button {
                        Tato.selecao()
                        aberta = p
                    } label: {
                        LinhaDePrescricao(prescricao: p)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
        }
    }
}

private struct LinhaDePrescricao: View {
    let prescricao: PrescricaoAdmin

    var body: some View {
        LinhaPadrao(icone: "pills", titulo: prescricao.medicamento.nome, apoio: apoio) {
            if !prescricao.ativa { EtiquetaDeCadastro(texto: "Encerrada") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prescricao.medicamento.nome). \(apoio)\(prescricao.ativa ? "" : ". Encerrada")")
    }

    private var apoio: String {
        "\(prescricao.posologia) · \(periodoDaPrescricao(prescricao))"
    }
}

private func periodoDaPrescricao(_ p: PrescricaoAdmin) -> String {
    let inicio = DataCivil.numerica(p.iniciadaEm)
    if let fim = p.encerradaEm { return "\(inicio) a \(DataCivil.numerica(fim))" }
    return "desde \(inicio)"
}

// MARK: - Detalhe e encerramento

private struct FolhaDaPrescricao: View {
    let prescricao: PrescricaoAdmin
    let store: PrescricoesAdminStore
    let encerrada: (String) -> Void

    @State private var confirmando = false
    @State private var enviando = false
    @State private var erro: String?
    @Environment(\.dismiss) private var fechar

    var body: some View {
        FolhaDeFormulario(
            rotulo: prescricao.ativa ? "Prescrição ativa" : "Prescrição encerrada",
            titulo: prescricao.medicamento.nome,
            acao: prescricao.ativa ? "Encerrar prescrição" : "Fechar",
            icone: prescricao.ativa ? "stop.circle" : "xmark",
            enviando: enviando,
            erro: erro,
            enviar: {
                if prescricao.ativa { confirmando = true } else { fechar() }
            }
        ) {
            VStack(alignment: .leading, spacing: Espaco.s) {
                LinhaDeFichaDeCadastro(rotulo: "Posologia", valor: prescricao.posologia)
                LinhaDeFichaDeCadastro(rotulo: "Princípio ativo", valor: prescricao.medicamento.principioAtivo ?? "Não informado")
                LinhaDeFichaDeCadastro(rotulo: "Início", valor: DataCivil.numerica(prescricao.iniciadaEm))
                LinhaDeFichaDeCadastro(rotulo: "Fim", valor: prescricao.encerradaEm.map(DataCivil.numerica) ?? "Em uso")
                LinhaDeFichaDeCadastro(rotulo: "Prescrita por", valor: prescricao.prescritaPor?.nome ?? "Não informado")
            }
            .padding(Espaco.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie(raio: Raio.linha)

            if prescricao.ativa {
                Text("Encerrar grava a data de hoje como fim. A partir daí a orientação ao paciente deixa de citar \(prescricao.medicamento.nome).")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .presentationDetents([.large])
        .confirmationDialog("Encerrar \(prescricao.medicamento.nome)?", isPresented: $confirmando, titleVisibility: .visible) {
            Button("Encerrar com a data de hoje") { Task { await encerrar() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O AUREA não reabre prescrição encerrada. Se o remédio voltar, registre uma prescrição nova.")
        }
    }

    private func encerrar() async {
        enviando = true
        erro = nil
        let resultado = await store.encerrar(prescricao)
        enviando = false
        if let resultado {
            Tato.erro()
            erro = resultado
        } else {
            encerrada("\(prescricao.medicamento.nome) encerrado.")
        }
    }
}

// MARK: - Nova prescrição

private struct FolhaDeNovaPrescricao: View {
    let store: PrescricoesAdminStore
    let concluir: (String) -> Void

    @State private var medicamentos: Carga<[MedicamentoDoCatalogo]> = .carregando
    @State private var medicamentoId: String?
    @State private var posologia = ""
    @State private var inicio = Date.now
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: store.paciente?.nome,
            titulo: "Nova prescrição",
            acao: "Registrar prescrição",
            icone: "pills",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            if let lista = medicamentos.valor {
                VStack(alignment: .leading, spacing: 6) {
                    CampoDeEscolha(
                        rotulo: "Medicamento",
                        opcoes: lista.map { (valor: $0.id, nome: $0.nome) },
                        selecionado: $medicamentoId,
                        dica: lista.isEmpty ? "Catálogo vazio" : "Escolher medicamento"
                    )
                    if lista.isEmpty {
                        Text("Cadastre o remédio em Medicamentos antes de prescrever.")
                            .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    }
                }
            } else if let falha = medicamentos.erro {
                Label(falha.mensagem, systemImage: "wifi.exclamationmark")
                    .font(Tipo.apoio).foregroundStyle(Cor.texto)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Medicamento").estiloDeRotulo()
                    Esqueleto(altura: 52)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                CampoDeTextoLongo(rotulo: "Posologia", texto: $posologia, dica: "8 mg, via oral, a cada 8 horas se enjoo", linhas: 3)
                Text("Dose, via e frequência num texto só — é assim que o prontuário e a orientação mostram.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CampoDeData(rotulo: "Início", data: $inicio)
        }
        .presentationDetents([.large])
        .task { await carregarMedicamentos() }
    }

    private func carregarMedicamentos() async {
        do {
            medicamentos = .pronto(try await ClienteAPI.compartilhado.obter("/admin/medicamentos"))
        } catch {
            medicamentos = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o catálogo de medicamentos."), anterior: nil)
        }
    }

    private func enviar() async {
        let texto = posologia.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let medicamentoId else { return falhar("Escolha o medicamento.") }
        if texto.count < 2 { return falhar("Escreva a posologia: dose, via e frequência.") }
        if texto.count > 255 { return falhar("A posologia passa de 255 caracteres. Resuma.") }

        enviando = true
        erro = nil
        let resultado = await store.criar(medicamentoId: medicamentoId, posologia: texto, iniciadaEm: inicio)
        enviando = false
        if let resultado { return falhar(resultado) }
        let nome = medicamentos.valor?.first { $0.id == medicamentoId }?.nome ?? "Prescrição"
        concluir("\(nome) prescrito.")
    }

    private func falhar(_ mensagem: String) {
        Tato.erro()
        erro = mensagem
    }
}
