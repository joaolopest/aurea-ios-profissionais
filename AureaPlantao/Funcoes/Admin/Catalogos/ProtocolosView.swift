import SwiftUI

@MainActor
@Observable
final class ProtocolosDoCatalogoStore {
    private(set) var carga: Carga<[ProtocoloDoCatalogo]> = .carregando
    private let api: ClienteAPI

    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/admin/protocolos"))
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui o cadastro de protocolos."), anterior: anterior)
        }
    }

    func jaExiste(_ nome: String) -> Bool {
        carga.valor?.contains { $0.nome.compare(nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } == true
    }

    /// Grava e relê a lista: o que aparece é o que ficou salvo, com o id de verdade.
    func criar(nome: String, descricao: String?) async -> String? {
        struct Corpo: Encodable, Sendable { let nome: String; let descricao: String? }
        do {
            let criado: RegistroCriadoNoCatalogo = try await api.enviar("/admin/protocolos", corpo: Corpo(nome: nome, descricao: descricao))
            await carregar()
            guard carga.valor?.contains(where: { $0.id == criado.id }) == true else {
                return "O AUREA respondeu, mas o protocolo não apareceu na lista. Puxe para atualizar antes de tentar de novo."
            }
            return nil
        } catch {
            // Nome repetido derruba a rota com 500 (a unicidade do banco não é tratada).
            return MensagemDeCadastro.texto(
                ErroDaAPI(error),
                falhaDoServidor: "O AUREA não gravou o protocolo. Se já existe um com este nome, use outro; se não, tente de novo em instantes."
            )
        }
    }
}

/// Protocolos de quimioterapia do serviço: o que se escolhe ao abrir um tratamento e o que
/// restringe regras do algoritmo.
struct ProtocolosView: View {
    @State private var store = ProtocolosDoCatalogoStore()
    @State private var criando = false
    @State private var aviso: String?

    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Administração",
                titulo: "Protocolos",
                contexto: "Protocolos de tratamento usados para restringir regras e organizar o painel da equipe."
            )

            BotaoDeAcaoEmLinha(titulo: "Novo protocolo") { criando = true }

            ConteudoDaCarga(
                carga: store.carga,
                vazio: { $0.isEmpty },
                tituloVazio: "Nenhum protocolo cadastrado.",
                textoVazio: "Sem protocolo, não dá para abrir tratamento. Cadastre o primeiro.",
                iconeVazio: "list.bullet.clipboard",
                tentarDeNovo: { Task { await store.carregar() } }
            ) { protocolos in
                GradeDeIndicadoresDeCadastro(itens: [
                    .init(rotulo: "Protocolos", valor: "\(protocolos.count)"),
                    .init(rotulo: "Ativos", valor: "\(protocolos.filter(\.ativo).count)", apoio: "disponíveis ao abrir tratamento"),
                    .init(rotulo: "Inativos", valor: "\(protocolos.filter { !$0.ativo }.count)", apoio: "não aparecem ao abrir tratamento"),
                    .init(rotulo: "Sem descrição", valor: "\(protocolos.filter(\.semDescricao).count)", apoio: "escolhidos só pela sigla"),
                ])

                CabecalhoDeSecao(titulo: "Todos os protocolos", contagem: protocolos.count)
                    .padding(.top, Espaco.s)
                VStack(spacing: Espaco.s) {
                    ForEach(Array(protocolos.enumerated()), id: \.element.id) { i, p in
                        LinhaDeProtocolo(protocolo: p).entradaEscalonada(i)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await store.carregar() }
        .avisoTemporario($aviso)
        .sheet(isPresented: $criando) {
            FolhaDeNovoProtocolo(store: store) { nome in
                criando = false
                Tato.sucesso()
                aviso = "\(nome) cadastrado."
            }
        }
    }
}

private struct LinhaDeProtocolo: View {
    let protocolo: ProtocoloDoCatalogo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(protocolo.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                Spacer(minLength: 8)
                if !protocolo.ativo { EtiquetaDeCadastro(texto: "Inativo") }
            }
            Text(protocolo.semDescricao ? "Sem descrição — quem monta o tratamento escolhe só pela sigla." : (protocolo.descricao ?? ""))
                .font(Tipo.apoio)
                .foregroundStyle(protocolo.semDescricao ? Cor.textoFraco : Cor.textoSuave)
                .lineLimit(3)
            Text(detalhe)
                .font(Tipo.apoio)
                .monospacedDigit()
                .foregroundStyle(Cor.textoFraco)
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .accessibilityElement(children: .combine)
    }

    private var detalhe: String {
        (["ocupa a cadeira por \(protocolo.tempoDeCadeira)"] + protocolo.atributos).joined(separator: " · ")
    }
}

private struct FolhaDeNovoProtocolo: View {
    let store: ProtocolosDoCatalogoStore
    let concluir: (String) -> Void

    @State private var nome = ""
    @State private var descricao = ""
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Protocolos",
            titulo: "Novo protocolo",
            acao: "Cadastrar protocolo",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEntrada(rotulo: "Nome", texto: $nome)
            VStack(alignment: .leading, spacing: 6) {
                CampoDeTextoLongo(rotulo: "Descrição (opcional)", texto: $descricao, dica: "Esquema, drogas, intervalo entre ciclos")
                Text("Nome de protocolo costuma ser sigla. A descrição é o que deixa quem abre o tratamento conferir se é o certo.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("O protocolo nasce ativo, sem atributos de risco (imunoterapia, neutropenia) e com os tempos de cadeira padrão. O app ainda não edita esses campos.", systemImage: "info.circle")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .padding(Espaco.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficie(.afundado, raio: Raio.controle)
        }
        .presentationDetents([.large])
    }

    private func enviar() async {
        let nomeLimpo = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let descricaoLimpa = descricao.trimmingCharacters(in: .whitespacesAndNewlines)
        if nomeLimpo.count < 2 { return falhar("Informe o nome do protocolo.") }
        if nomeLimpo.count > 120 { return falhar("O nome passa de 120 caracteres. Use a sigla e ponha o resto na descrição.") }
        if descricaoLimpa.count > 4000 { return falhar("A descrição passa de 4.000 caracteres.") }
        if store.jaExiste(nomeLimpo) { return falhar("Já existe um protocolo chamado \(nomeLimpo).") }

        enviando = true
        erro = nil
        let resultado = await store.criar(nome: nomeLimpo, descricao: descricaoLimpa.isEmpty ? nil : descricaoLimpa)
        enviando = false
        if let resultado { return falhar(resultado) }
        concluir(nomeLimpo)
    }

    private func falhar(_ mensagem: String) {
        Tato.erro()
        erro = mensagem
    }
}
