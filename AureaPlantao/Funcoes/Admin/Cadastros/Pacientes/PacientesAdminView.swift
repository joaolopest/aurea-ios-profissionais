import SwiftUI

/// Rota da ficha — só o que a lista já sabe, para o título aparecer antes da carga.
struct RotaDaFichaDoCadastro: Hashable, Identifiable {
    let id: String
    let nome: String
}

/// Tradução dos erros que o `ClienteAPI` não sabe ler nesta rota.
///
/// A API do cadastro manda a mensagem em `{ "erro": "…" }`, e o cliente só lê `message` /
/// `mensagem` — então todo 4xx daqui chega como o texto genérico "O AUREA recusou o pedido
/// (NNN).". Até o cliente aprender a chave, a tela diz a coisa certa pelo código.
enum ErroDoCadastro {
    static func traduzir(_ erro: ErroDaAPI) -> ErroDaAPI {
        guard case .recusado(let m) = erro else { return erro }
        if m.contains("(403)") { return .recusado("Seu acesso não inclui o cadastro de pacientes. Peça a permissão de cadastros a quem administra o AUREA.") }
        if m.contains("(404)") { return .recusado("Este registro não existe mais no AUREA. Puxe para atualizar a ficha.") }
        if m.contains("(400)") { return .recusado("O AUREA recusou os dados. Confira os campos e tente de novo.") }
        return erro
    }

    static func mensagem(_ erro: Error) -> String {
        traduzir(ErroDaAPI(erro)).mensagem
    }
}

@MainActor
@Observable
final class PacientesAdminStore {
    private(set) var carga: Carga<[PacienteDoCadastro]> = .carregando
    var busca = ""
    private let api: ClienteAPI

    init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    /// A rota não tem busca no servidor: a lista é pequena (dezenas), então vem inteira,
    /// página a página, e a busca roda aqui. O teto de páginas impede laço infinito se um
    /// cursor vier corrompido.
    func carregar() async {
        let anterior = carga.valor
        do {
            var todos: [PacienteDoCadastro] = []
            var cursor: String?
            for _ in 0..<50 {
                var consulta = [URLQueryItem(name: "limite", value: "100")]
                if let cursor { consulta.append(URLQueryItem(name: "cursor", value: cursor)) }
                let pagina: PaginaDoCadastroDePacientes = try await api.obter("/admin/pacientes", consulta: consulta)
                todos += pagina.itens
                guard let proximo = pagina.proximoCursor else { break }
                cursor = proximo
            }
            carga = .pronto(todos)
        } catch {
            carga = .falhou(ErroDoCadastro.traduzir(ErroDaAPI(error)), anterior: anterior)
        }
    }

    /// Nome, diagnóstico e protocolo, sem acento e sem caixa. Com 3 dígitos ou mais, olha
    /// também o CPF — é como a recepção procura quem está com o documento na mão.
    var filtrados: [PacienteDoCadastro] {
        let todos = carga.valor ?? []
        let termo = busca.trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty else { return todos }
        let digitos = CPFDoCadastro.normalizar(termo)
        let buscaPorCPF = digitos.count >= 3 && digitos.count == termo.filter { !".-".contains($0) }.count
        return todos.filter { p in
            if buscaPorCPF { return CPFDoCadastro.normalizar(p.cpf).contains(digitos) }
            return [p.nome, p.diagnostico, p.protocolo?.nome ?? ""].contains { TextoDoCadastro.contem($0, termo) }
        }
    }

    var semProtocolo: Int { (carga.valor ?? []).filter { $0.protocolo == nil }.count }
}

/// Pacientes (admin): a ficha de cadastro de cada pessoa em tratamento — quem é, como
/// falar com ela, a que é alérgica. Não é o prontuário clínico: aquele é da enfermagem.
struct PacientesAdminView: View {
    @State private var store = PacientesAdminStore()
    @State private var criando = false
    @State private var recemCriado: RotaDaFichaDoCadastro?
    @State private var aviso: String?

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Cadastros",
                titulo: "Pacientes",
                contexto: "Identificação, diagnóstico e contatos da pessoa em tratamento."
            )

            AvisoDeDadoSintetico()

            if let lista = store.carga.valor, !lista.isEmpty {
                Indicadores(total: lista.count, semProtocolo: store.semProtocolo)
            }

            HStack(alignment: .center) {
                CabecalhoDeSecao(titulo: "Todos os pacientes", contagem: store.carga.valor?.count)
                BotaoDeAcaoEmLinha(titulo: "Novo paciente", icone: "plus") { criando = true }
            }
            .padding(.top, Espaco.s)

            if store.carga.valor?.isEmpty == false {
                CampoDeBuscaDoCadastro(texto: $store.busca)
            }

            ConteudoDaCarga(
                carga: store.carga,
                vazio: { $0.isEmpty },
                tituloVazio: "Nenhum paciente cadastrado.",
                textoVazio: "Cadastre o primeiro paciente para ele poder entrar no app e responder o check-in.",
                iconeVazio: "person.text.rectangle",
                tentarDeNovo: { Task { await store.carregar() } }
            ) { _ in
                lista
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { if store.carga.valor == nil { await store.carregar() } }
        .encerraSessaoNo401(store.carga.erro)
        .avisoTemporario($aviso)
        .sheet(isPresented: $criando) {
            FormularioDeNovoPaciente { criado in
                criando = false
                Tato.sucesso()
                aviso = "Paciente cadastrado."
                Task {
                    await store.carregar()
                    // Direto para a ficha: o próximo passo natural é o contato de emergência.
                    recemCriado = criado
                }
            }
            .presentationDetents([.large])
        }
        .navigationDestination(for: RotaDaFichaDoCadastro.self) { rota in
            FichaDoPacienteView(rota: rota) { await store.carregar() }
        }
        .navigationDestination(item: $recemCriado) { rota in
            FichaDoPacienteView(rota: rota) { await store.carregar() }
        }
    }

    @ViewBuilder
    private var lista: some View {
        let filtrados = store.filtrados
        if filtrados.isEmpty {
            EstadoVazio(titulo: "Ninguém com “\(store.busca)”.",
                        texto: "A busca olha nome, diagnóstico, protocolo e, com números, o CPF.",
                        icone: "magnifyingglass")
                .superficie()
        } else {
            LazyVStack(spacing: Espaco.s) {
                ForEach(Array(filtrados.enumerated()), id: \.element.id) { i, p in
                    NavigationLink(value: RotaDaFichaDoCadastro(id: p.id, nome: p.nome)) {
                        LinhaDePacienteDoCadastro(paciente: p)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
        }
    }
}

/// Decisão do projeto (ADR do Comitê de Ética): até a aprovação, nome, CPF e diagnóstico
/// de pessoa real não entram. A tela lembra disso onde se cadastra, não num rodapé.
private struct AvisoDeDadoSintetico: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Cor.textoSuave)
            VStack(alignment: .leading, spacing: 3) {
                Text("Dado sintético até a aprovação do Comitê de Ética")
                    .font(Tipo.apoioForte).foregroundStyle(Cor.texto)
                Text("Todo paciente aqui é fictício. Nome, CPF e diagnóstico de pessoa real não entram no sistema antes da aprovação — vale para esta tela, para print e para apresentação.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(.afundado, raio: Raio.linha)
        .accessibilityElement(children: .combine)
    }
}

/// A fileira diz o que FALTA no cadastro, não o que ele repete (comentário do web).
/// A lista da API não traz contato nem hábito basal, então aqui só cabe a lacuna que ela
/// sustenta: paciente sem protocolo ativo.
private struct Indicadores: View {
    let total: Int
    let semProtocolo: Int

    var body: some View {
        HStack(spacing: Espaco.s) {
            CartaoDeIndicador(rotulo: "Cadastrados", valor: "\(total)", destaque: true)
            CartaoDeIndicador(rotulo: "Sem protocolo", valor: "\(semProtocolo)",
                              apoio: "não entram em tratamento")
                .opacity(semProtocolo == 0 ? 0.6 : 1)
        }
    }
}

private struct CampoDeBuscaDoCadastro: View {
    @Binding var texto: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Cor.textoFraco)
                .accessibilityHidden(true)
            TextField("Nome, diagnóstico, protocolo ou CPF", text: $texto)
                .font(Tipo.corpo)
                .foregroundStyle(Cor.texto)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Buscar paciente")
            if !texto.isEmpty {
                Button { texto = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Cor.textoFraco)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .superficie(.afundado, raio: Raio.controle)
    }
}

private struct LinhaDePacienteDoCadastro: View {
    let paciente: PacienteDoCadastro

    var body: some View {
        let idade = DataCivil.idade(paciente.dataNascimento)
        HStack(alignment: .top, spacing: 12) {
            Iniciais(nome: paciente.nome, tamanho: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(paciente.nome)
                        .font(Tipo.corpoForte).foregroundStyle(Cor.texto).lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(idade) anos")
                        .font(Tipo.apoioForte).monospacedDigit().foregroundStyle(Cor.textoSuave)
                        .fixedSize()
                }
                Text(paciente.diagnostico)
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave).lineLimit(2)
                HStack(spacing: 10) {
                    Text(CPFDoCadastro.mascarado(paciente.cpf))
                        .font(Tipo.coluna).foregroundStyle(Cor.textoFraco)
                    Text(paciente.protocolo?.nome ?? "sem protocolo")
                        .font(Tipo.apoio)
                        .foregroundStyle(paciente.protocolo == nil ? Cor.textoFraco : Cor.azulProfundo)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Cor.textoFraco.opacity(0.7))
                .padding(.top, 12)
        }
        .padding(14)
        .frame(minHeight: 66)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(paciente.nome), \(idade) anos. \(paciente.diagnostico). \(paciente.protocolo.map { "Protocolo \($0.nome)" } ?? "Sem protocolo").")
        .accessibilityHint("Abre a ficha de cadastro")
    }
}
