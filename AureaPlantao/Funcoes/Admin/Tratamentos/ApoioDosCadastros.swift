import SwiftUI

// Peças comuns aos cadastros administrativos (tratamentos, ciclos, prescrições, catálogos e
// equipe). Nomes com "DeCadastro" de propósito: vivem nesta pasta, não no Sistema, e não
// podem colidir com os tipos do painel.

// MARK: - Data civil

// MARK: - Erros de cadastro

/// A API responde erro como `{ "erro": "…" }`, e o `ClienteAPI` só lê `message`/`mensagem`
/// — então a frase da API se perde e sobra o texto genérico do cliente ("Isto já foi feito
/// por outra pessoa." para qualquer 409). Aqui cada tela diz o que o 409/400 significa NELA.
/// Se o cliente passar a ler `erro`, a mensagem da própria API volta a valer sozinha.
enum MensagemDeCadastro {
    private static let conflitoGenerico = "Isto já foi feito por outra pessoa."
    private static let prefixoGenerico = "O AUREA recusou o pedido"

    static func texto(
        _ erro: ErroDaAPI,
        conflito: String? = nil,
        recusado: String? = nil,
        falhaDoServidor: String? = nil
    ) -> String {
        switch erro {
        case .conflito(let m) where m == conflitoGenerico:
            return conflito ?? m
        case .recusado(let m) where m.hasPrefix(prefixoGenerico):
            if m.contains("(403)") { return semAcesso }
            return recusado ?? "O AUREA recusou os dados. Confira os campos e tente de novo."
        case .servidor:
            return falhaDoServidor ?? erro.mensagem
        default:
            return erro.mensagem
        }
    }

    static let semAcesso = "Seu acesso não inclui esta ação. Peça a quem administra o AUREA."

    /// Para listas: 403 vira frase honesta em vez de "recusou o pedido (403)".
    static func paraCarga(_ erro: Error, semAcesso frase: String) -> ErroDaAPI {
        let e = ErroDaAPI(erro)
        if case .recusado(let m) = e, m.hasPrefix(prefixoGenerico), m.contains("(403)") {
            return .recusado(frase)
        }
        return e
    }
}

// MARK: - Modelos compartilhados

/// `{ id, nome }` — paciente e protocolo dentro de tratamento.
struct ReferenciaDeCadastro: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let nome: String
}

/// `{ id, nome, funcao }` — `medicoResponsavel` e `prescritaPor`. O `id` é do
/// Profissional, não do Usuário.
struct ProfissionalDeCadastro: Decodable, Sendable, Hashable {
    let id: String
    let nome: String
    let funcao: FuncaoProfissional
}

/// Item de `GET /admin/pacientes` — só o que a escolha de paciente usa.
struct PacienteParaEscolha: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let nome: String
    let dataNascimento: Date
    let diagnostico: String
    /// O protocolo do tratamento ATIVO, se houver. Nulo = sem tratamento em curso.
    let protocolo: ReferenciaDeCadastro?
}

struct PaginaDePacientesDoCadastro: Decodable, Sendable {
    let itens: [PacienteParaEscolha]
    let proximoCursor: String?
}

extension ClienteAPI {
    /// Todos os pacientes, página a página (limite máximo da API: 100). O cadastro precisa
    /// da lista inteira para escolher — um paciente na página 2 não pode sumir da busca.
    func todosOsPacientesDoCadastro() async throws -> [PacienteParaEscolha] {
        var todos: [PacienteParaEscolha] = []
        var cursor: String?
        repeat {
            var consulta = [URLQueryItem(name: "limite", value: "100")]
            if let cursor { consulta.append(URLQueryItem(name: "cursor", value: cursor)) }
            let pagina: PaginaDePacientesDoCadastro = try await obter("/admin/pacientes", consulta: consulta)
            todos += pagina.itens
            cursor = pagina.proximoCursor
        } while cursor != nil && todos.count < 5000
        return todos
    }
}

// MARK: - Peças visuais

/// Etiqueta de estado ADMINISTRATIVO ("Encerrado", "Inativo", "Desativada"). Neutra de
/// propósito: verde/amarelo/vermelho/cinza-silêncio são só classificação de paciente.
struct EtiquetaDeCadastro: View {
    let texto: String
    var enfatica = false

    var body: some View {
        Text(texto)
            .font(Tipo.rotulo)
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(enfatica ? Cor.azulProfundo : Cor.textoSuave)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(enfatica ? Cor.azulGelo.opacity(0.45) : Cor.fundoBaixo))
            .fixedSize()
    }
}

/// O cartão "de quem estamos falando" no topo de uma tela que depende de uma escolha
/// (paciente, tratamento). Vazio, convida a escolher; preenchido, mostra e deixa trocar.
struct CartaoDeEscolhaDeCadastro: View {
    let rotulo: String
    let titulo: String?
    var apoio: String?
    let convite: String
    let textoVazio: String
    let icone: String
    let escolher: () -> Void

    var body: some View {
        if let titulo {
            Button {
                Tato.selecao()
                escolher()
            } label: {
                HStack(spacing: 12) {
                    Iniciais(nome: titulo, tamanho: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rotulo).estiloDeRotulo()
                        Text(titulo).font(Tipo.destaque).foregroundStyle(Cor.texto).lineLimit(2)
                        if let apoio {
                            Text(apoio).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("Trocar")
                        .font(Tipo.apoioForte)
                        .foregroundStyle(Cor.azulProfundo)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.horizontal, Espaco.l)
                .padding(.vertical, Espaco.m)
                .cartaoDestaque(tom: Cor.auroraAco)
                .contentShape(.rect)
            }
            .buttonStyle(.pressionavel)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(rotulo): \(titulo)\(apoio.map { ", \($0)" } ?? "")")
            .accessibilityHint("Toque para trocar")
        } else {
            VStack(spacing: Espaco.l) {
                EstadoVazio(titulo: convite, texto: textoVazio, icone: icone)
                BotaoPrimario(titulo: convite, icone: icone, acao: escolher)
                    .padding(.horizontal, Espaco.l)
                    .padding(.bottom, Espaco.l)
            }
            .superficie()
        }
    }
}

/// Casca das folhas de escolha (paciente, tratamento): cancelar, título, busca e lista.
struct FolhaDeEscolhaDeCadastro<Lista: View>: View {
    let rotulo: String
    let titulo: String
    @Binding var busca: String
    @ViewBuilder let lista: Lista
    @Environment(\.dismiss) private var fechar

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancelar") { fechar() }
                    .font(Tipo.apoioForte)
                    .foregroundStyle(Cor.textoSuave)
                    .frame(minHeight: 44)
                Spacer()
            }
            .padding(.horizontal, Espaco.xl)
            .padding(.top, Espaco.s)

            ScrollView {
                VStack(alignment: .leading, spacing: Espaco.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rotulo).estiloDeRotulo()
                        Text(titulo).font(Tipo.titulo).foregroundStyle(Cor.texto)
                            .accessibilityAddTraits(.isHeader)
                    }
                    CampoDeEntrada(rotulo: "Buscar pelo nome", texto: $busca, botaoDoTeclado: .search)
                    lista
                }
                .padding(Espaco.xl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
    }
}

/// Busca sem acento e sem caixa: "sonia" acha "Sônia".
func casaComBuscaDeCadastro(_ texto: String, _ busca: String) -> Bool {
    let termo = busca.trimmingCharacters(in: .whitespaces)
    guard !termo.isEmpty else { return true }
    return texto.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil
}

// MARK: - Escolha de paciente

/// Escolhe um paciente do cadastro. `indisponivel` devolve o motivo de um paciente não
/// poder ser escolhido (ex.: já tem tratamento ativo) — ele aparece, apagado e explicado,
/// em vez de sumir sem explicação.
struct SeletorDePacienteDoCadastro: View {
    let titulo: String
    var indisponivel: (PacienteParaEscolha) -> String? = { _ in nil }
    let escolher: (PacienteParaEscolha) -> Void

    @State private var carga: Carga<[PacienteParaEscolha]> = .carregando
    @State private var busca = ""
    @Environment(\.dismiss) private var fechar

    var body: some View {
        FolhaDeEscolhaDeCadastro(rotulo: "Cadastro de pacientes", titulo: titulo, busca: $busca) {
            ConteudoDaCarga(
                carga: carga,
                linhasDeEsqueleto: 6,
                vazio: { $0.isEmpty },
                tituloVazio: "Nenhum paciente cadastrado.",
                textoVazio: "Cadastre o paciente em Cadastros › Pacientes antes de continuar.",
                iconeVazio: "person",
                tentarDeNovo: { Task { await carregar() } }
            ) { pacientes in
                let filtrados = pacientes.filter { casaComBuscaDeCadastro($0.nome, busca) }
                if filtrados.isEmpty {
                    Text("Ninguém com “\(busca)” no nome.")
                        .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        .padding(.horizontal, 4)
                }
                LazyVStack(spacing: Espaco.s) {
                    ForEach(filtrados) { p in linha(p) }
                }
            }
        }
        .task { await carregar() }
    }

    private func linha(_ p: PacienteParaEscolha) -> some View {
        let motivo = indisponivel(p)
        return Button {
            Tato.selecao()
            escolher(p)
            fechar()
        } label: {
            LinhaPadrao(avatar: p.nome, titulo: p.nome, apoio: motivo ?? apoio(p), mostrarSeta: false)
                .opacity(motivo == nil ? 1 : 0.55)
        }
        .buttonStyle(.pressionavel)
        .disabled(motivo != nil)
        .accessibilityLabel("\(p.nome). \(motivo ?? apoio(p))")
    }

    private func apoio(_ p: PacienteParaEscolha) -> String {
        let nascimento = "nasc. \(DataCivil.numerica(p.dataNascimento))"
        if let protocolo = p.protocolo { return "\(protocolo.nome) · \(nascimento)" }
        return "\(p.diagnostico) · \(nascimento)"
    }

    private func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await ClienteAPI.compartilhado.todosOsPacientesDoCadastro())
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o cadastro de pacientes."), anterior: anterior)
        }
    }
}

// MARK: - Indicadores em grade

/// Quatro (ou três) indicadores em duas colunas — a "linha de indicadores" do web, dobrada
/// para caber no iPhone. O primeiro é o destaque.
struct GradeDeIndicadoresDeCadastro: View {
    struct Item: Identifiable {
        let rotulo: String
        let valor: String
        var apoio: String?
        var id: String { rotulo }
    }

    let itens: [Item]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Espaco.s, alignment: .top),
                            GridItem(.flexible(), spacing: Espaco.s, alignment: .top)],
                  spacing: Espaco.s) {
            ForEach(Array(itens.enumerated()), id: \.element.id) { i, item in
                CartaoDeIndicador(rotulo: item.rotulo, valor: item.valor, apoio: item.apoio, destaque: i == 0)
            }
        }
    }
}

// MARK: - Campo que abre uma folha de escolha

/// Mesma casca do `CampoDeEscolha`, mas para listas grandes (pacientes, tratamentos) que
/// precisam de busca: o toque abre uma folha em vez de um menu.
struct CampoDeEscolhaPorFolha: View {
    let rotulo: String
    let valor: String?
    var dica = "Escolher"
    let abrir: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rotulo).estiloDeRotulo().accessibilityHidden(true)
            Button {
                Tato.selecao()
                abrir()
            } label: {
                HStack {
                    Text(valor ?? dica)
                        .font(Tipo.corpo)
                        .foregroundStyle(valor == nil ? Cor.textoFraco : Cor.texto)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Cor.textoFraco)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .superficie(.afundado, raio: Raio.controle)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(rotulo): \(valor ?? "não escolhido")")
            .accessibilityHint("Abre a lista para escolher")
        }
    }
}

/// Linha "rótulo … valor" das fichas de detalhe.
struct LinhaDeFichaDeCadastro: View {
    let rotulo: String
    let valor: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(rotulo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
            Spacer(minLength: 12)
            Text(valor).font(Tipo.apoioForte).monospacedDigit().foregroundStyle(Cor.texto)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
