import SwiftUI

@MainActor
@Observable
final class MedicamentosDoCatalogoStore {
    private(set) var carga: Carga<[MedicamentoDoCatalogo]> = .carregando
    private let api: ClienteAPI

    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/admin/medicamentos"))
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o catálogo de medicamentos."), anterior: anterior)
        }
    }

    func jaExiste(_ nome: String) -> Bool {
        carga.valor?.contains { $0.nome.compare(nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } == true
    }

    func criar(nome: String, principioAtivo: String?) async -> String? {
        struct Corpo: Encodable, Sendable { let nome: String; let principioAtivo: String? }
        do {
            let criado: RegistroCriadoNoCatalogo = try await api.enviar("/admin/medicamentos", corpo: Corpo(nome: nome, principioAtivo: principioAtivo))
            await carregar()
            guard carga.valor?.contains(where: { $0.id == criado.id }) == true else {
                return "O AUREA respondeu, mas o medicamento não apareceu na lista. Puxe para atualizar antes de tentar de novo."
            }
            return nil
        } catch {
            // Nome repetido derruba a rota com 500 (a unicidade do banco não é tratada).
            return MensagemDeCadastro.texto(
                ErroDaAPI(error),
                falhaDoServidor: "O AUREA não gravou o medicamento. Se já existe um com este nome, use outro; se não, tente de novo em instantes."
            )
        }
    }
}

/// O catálogo de medicamentos: o que as prescrições usam e o que as orientações podem
/// nomear (só nomeiam remédio prescrito e ativo para aquele paciente).
struct MedicamentosView: View {
    @State private var store = MedicamentosDoCatalogoStore()
    @State private var criando = false
    @State private var aviso: String?

    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Administração",
                titulo: "Medicamentos",
                contexto: "Medicamentos usados nas prescrições e nas orientações da equipe."
            )

            BotaoDeAcaoEmLinha(titulo: "Novo medicamento") { criando = true }

            ConteudoDaCarga(
                carga: store.carga,
                vazio: { $0.isEmpty },
                tituloVazio: "Nenhum medicamento cadastrado.",
                textoVazio: "Sem medicamento no catálogo, não dá para registrar prescrição. Cadastre o primeiro.",
                iconeVazio: "pills",
                tentarDeNovo: { Task { await store.carregar() } }
            ) { medicamentos in
                // Dois fatos: quantos existem e quantos estão incompletos. O que pede
                // trabalho é a FALTA — ninguém deveria ter de subtrair para achá-la.
                GradeDeIndicadoresDeCadastro(itens: [
                    .init(rotulo: "Medicamentos", valor: "\(medicamentos.count)"),
                    .init(rotulo: "Sem princípio ativo", valor: "\(medicamentos.filter(\.semPrincipioAtivo).count)", apoio: "não dá para conferir interação"),
                ])

                CabecalhoDeSecao(titulo: "Todos os medicamentos", contagem: medicamentos.count)
                    .padding(.top, Espaco.s)
                VStack(spacing: Espaco.s) {
                    ForEach(Array(medicamentos.enumerated()), id: \.element.id) { i, m in
                        LinhaPadrao(
                            icone: "pills",
                            titulo: m.nome,
                            apoio: m.semPrincipioAtivo ? "Princípio ativo não informado" : m.principioAtivo,
                            mostrarSeta: false
                        )
                        .accessibilityElement(children: .combine)
                        .entradaEscalonada(i)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await store.carregar() }
        .avisoTemporario($aviso)
        .sheet(isPresented: $criando) {
            FolhaDeNovoMedicamento(store: store) { nome in
                criando = false
                Tato.sucesso()
                aviso = "\(nome) entrou no catálogo."
            }
        }
    }
}

private struct FolhaDeNovoMedicamento: View {
    let store: MedicamentosDoCatalogoStore
    let concluir: (String) -> Void

    @State private var nome = ""
    @State private var principioAtivo = ""
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Medicamentos",
            titulo: "Novo medicamento",
            acao: "Cadastrar medicamento",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEntrada(rotulo: "Nome", texto: $nome)
            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "Princípio ativo (opcional)", texto: $principioAtivo)
                Text("Sem o princípio ativo não dá para conferir interação entre remédios.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
            }
        }
        .presentationDetents([.large])
    }

    private func enviar() async {
        let nomeLimpo = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let principio = principioAtivo.trimmingCharacters(in: .whitespacesAndNewlines)
        if nomeLimpo.count < 2 { return falhar("Informe o nome do medicamento.") }
        if nomeLimpo.count > 160 || principio.count > 160 { return falhar("Nome e princípio ativo têm até 160 caracteres.") }
        if store.jaExiste(nomeLimpo) { return falhar("\(nomeLimpo) já está no catálogo.") }

        enviando = true
        erro = nil
        let resultado = await store.criar(nome: nomeLimpo, principioAtivo: principio.isEmpty ? nil : principio)
        enviando = false
        if let resultado { return falhar(resultado) }
        concluir(nomeLimpo)
    }

    private func falhar(_ mensagem: String) {
        Tato.erro()
        erro = mensagem
    }
}
