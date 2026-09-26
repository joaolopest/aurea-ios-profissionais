import SwiftUI

@MainActor
@Observable
final class EquipeStore {
    private(set) var carga: Carga<[ContaDaEquipe]> = .carregando
    private let api: ClienteAPI

    /// `nonisolated`: a tela é criada por `telaSecundaria(_:)`, que não roda no MainActor.
    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/admin/usuarios"))
        } catch {
            carga = .falhou(MensagemDeCadastro.paraCarga(error, semAcesso: "Seu acesso não inclui a gestão de usuários."), anterior: anterior)
        }
    }

    struct NovoProfissional: Encodable, Sendable {
        let nome: String
        let email: String
        let funcao: FuncaoProfissional
        let registroDoConselho: String?
        let perfil: String
        let permissoes: [PermissaoDeAcesso]
        let senhaProvisoria: String
    }

    private struct ContaCriada: Decodable, Sendable { let id: String }
    private struct PermissoesSalvas: Decodable, Sendable { let id: String }
    private struct AtivoSalvo: Decodable, Sendable { let id: String; let ativo: Bool }

    /// Cria a conta e confere na lista que ela ficou gravada — a tela do web "salvava"
    /// só na memória e dizia que tinha salvo.
    func criar(_ novo: NovoProfissional) async -> String? {
        do {
            let criada: ContaCriada = try await api.enviar("/admin/usuarios/profissional", corpo: novo)
            await carregar()
            guard carga.valor?.contains(where: { $0.id == criada.id }) == true else {
                return "O AUREA respondeu, mas a conta não apareceu na lista. Puxe para atualizar antes de tentar de novo."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(
                ErroDaAPI(error),
                conflito: "Já existe uma conta com este e-mail.",
                recusado: "O AUREA recusou os dados. Confira o e-mail, a função e a senha provisória (8 caracteres ou mais)."
            )
        }
    }

    func salvarPermissoes(_ conta: ContaDaEquipe, _ permissoes: Set<PermissaoDeAcesso>) async -> String? {
        struct Corpo: Encodable, Sendable { let permissoes: [PermissaoDeAcesso] }
        let ordenadas = permissoes.sorted { $0.bruto < $1.bruto }
        do {
            let _: PermissoesSalvas = try await api.atualizar("/admin/usuarios/\(conta.id)/permissoes", corpo: Corpo(permissoes: ordenadas))
            await carregar()
            let gravadas = Set(carga.valor?.first { $0.id == conta.id }?.permissoes ?? [])
            guard gravadas == permissoes else {
                return "O AUREA respondeu, mas as permissões lidas de volta não batem com as escolhidas. Puxe para atualizar e confira."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(
                ErroDaAPI(error),
                recusado: "O AUREA recusou esta combinação. Editar algoritmo e Atender plantão não podem ficar juntas."
            )
        }
    }

    func alterarAtivo(_ conta: ContaDaEquipe, para ativo: Bool) async -> String? {
        struct Corpo: Encodable, Sendable { let ativo: Bool }
        do {
            let _: AtivoSalvo = try await api.atualizar("/admin/usuarios/\(conta.id)/ativo", corpo: Corpo(ativo: ativo))
            await carregar()
            guard carga.valor?.first(where: { $0.id == conta.id })?.ativo == ativo else {
                return "O AUREA respondeu, mas a conta lida de volta não mudou. Puxe para atualizar e confira."
            }
            return nil
        } catch {
            return MensagemDeCadastro.texto(ErroDaAPI(error))
        }
    }
}

/// Equipe: quem entra no AUREA, com que função e podendo o quê.
///
/// A regra que a tela precisa deixar visível é a do schema: quem edita o algoritmo muda o
/// risco de todos os pacientes de uma vez; quem está de plantão responde por um. São
/// concessões separadas, e a API recusa as duas juntas — a tela explica antes de recusar.
struct EquipeView: View {
    @State private var store = EquipeStore()
    @State private var filtro: Filtro = .ativas
    @State private var criando = false
    @State private var contaAberta: ContaDaEquipe?
    @State private var aviso: String?
    @Environment(Sessao.self) private var sessao

    enum Filtro: Hashable { case ativas, desativadas }

    /// `nonisolated`: `telaSecundaria(_:)` (Mais) e o hub de Cadastros criam esta tela
    /// fora do MainActor.
    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Administração",
                titulo: "Equipe",
                contexto: "Profissionais e usuários do sistema, com função e permissões de acesso."
            )

            BotaoDeAcaoEmLinha(titulo: "Novo profissional", icone: "person.badge.plus") { criando = true }

            ConteudoDaCarga(
                carga: store.carga,
                vazio: { $0.isEmpty },
                tituloVazio: "Ninguém cadastrado.",
                textoVazio: "Cadastre o primeiro profissional para que alguém possa entrar no AUREA.",
                iconeVazio: "person.badge.key",
                tentarDeNovo: { Task { await store.carregar() } }
            ) { contas in
                indicadores(contas)
                SeletorDePilulas(opcoes: [
                    OpcaoDeSeletor(id: Filtro.ativas, titulo: "Ativas", contador: contas.filter(\.ativo).count),
                    OpcaoDeSeletor(id: Filtro.desativadas, titulo: "Desativadas", contador: contas.filter { !$0.ativo }.count),
                ], selecionado: $filtro)
                .padding(.horizontal, -Espaco.margem)
                lista(contas.filter { filtro == .ativas ? $0.ativo : !$0.ativo })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await store.carregar() }
        .avisoTemporario($aviso)
        .sheet(isPresented: $criando) {
            FolhaDeNovoProfissional(store: store) { nome in
                criando = false
                Tato.sucesso()
                aviso = "\(nome) já pode entrar."
            }
        }
        .sheet(item: $contaAberta) { conta in
            FolhaDaContaDaEquipe(conta: conta, store: store, ehVoce: conta.id == sessao.eu?.id) { mensagem in
                contaAberta = nil
                Tato.sucesso()
                aviso = mensagem
            }
        }
    }

    /// Um número de capacidade e três de lacuna: quem administra a equipe precisa saber
    /// quem NÃO consegue trabalhar — ausência não tem selo na lista.
    private func indicadores(_ contas: [ContaDaEquipe]) -> some View {
        let ativas = contas.filter(\.ativo)
        return GradeDeIndicadoresDeCadastro(itens: [
            .init(rotulo: "Contas ativas", valor: "\(ativas.count)", apoio: contas.count > ativas.count ? "\(contas.count - ativas.count) desativadas" : nil),
            .init(rotulo: "Atendem plantão", valor: "\(ativas.filter { $0.permissoes.contains(.atenderPlantao) }.count)", apoio: "recebem a fila do dia"),
            .init(rotulo: "Sem permissão", valor: "\(ativas.filter { $0.permissoes.isEmpty }.count)", apoio: "entram e não encontram nada"),
            .init(rotulo: "Sem registro", valor: "\(ativas.filter(\.semRegistroDoConselho).count)", apoio: "sem conselho, não assinam conduta"),
        ])
    }

    @ViewBuilder
    private func lista(_ contas: [ContaDaEquipe]) -> some View {
        if contas.isEmpty {
            EstadoVazio(
                titulo: filtro == .ativas ? "Nenhuma conta ativa." : "Nenhuma conta desativada.",
                texto: filtro == .ativas ? "Sem conta ativa, ninguém entra no AUREA." : "Contas desativadas aparecem aqui e podem ser reativadas.",
                icone: "person.badge.key"
            )
            .superficie()
        } else {
            VStack(spacing: Espaco.s) {
                ForEach(Array(contas.enumerated()), id: \.element.id) { i, conta in
                    Button {
                        Tato.selecao()
                        contaAberta = conta
                    } label: {
                        LinhaDaConta(conta: conta, ehVoce: conta.id == sessao.eu?.id)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
            .animation(Movimento.interface, value: contas.map(\.id))
        }
    }
}

private struct LinhaDaConta: View {
    let conta: ContaDaEquipe
    let ehVoce: Bool

    var body: some View {
        LinhaPadrao(avatar: conta.nome, titulo: conta.nome, apoio: apoio) {
            VStack(alignment: .trailing, spacing: 4) {
                if ehVoce { EtiquetaDeCadastro(texto: "Você", enfatica: true) }
                if conta.ehAdministracao { EtiquetaDeCadastro(texto: "Admin") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rotuloAcessivel)
        .accessibilityHint("Abre permissões e acesso")
    }

    private var apoio: String {
        var partes: [String] = []
        if let ficha = conta.profissional {
            partes.append(ficha.funcao.nome)
            if let registro = ficha.registroDoConselho, !registro.isEmpty { partes.append(registro) }
        } else {
            partes.append("Sem ficha de profissional")
        }
        let n = conta.permissoes.count
        partes.append(n == 0 ? "sem permissão" : n == 1 ? "1 permissão" : "\(n) permissões")
        return partes.joined(separator: " · ")
    }

    private var rotuloAcessivel: String {
        var texto = "\(conta.nome). \(apoio)"
        if conta.ehAdministracao { texto += ". Conta de administração" }
        if ehVoce { texto += ". É a sua conta" }
        if !conta.ativo { texto += ". Desativada" }
        return texto
    }
}

// MARK: - Permissões (lista explicada)

/// As nove permissões, em três grupos, cada uma com o que ela deixa fazer. O conflito
/// Editar algoritmo × Atender plantão aparece no momento em que acontece, com o motivo.
private struct ListaDePermissoesExplicadas: View {
    @Binding var selecionadas: Set<PermissaoDeAcesso>
    var bloqueada = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            ForEach(PermissaoDeAcesso.Grupo.allCases, id: \.self) { grupo in
                VStack(alignment: .leading, spacing: Espaco.s) {
                    CabecalhoDeSecao(titulo: grupo.rawValue)
                    ForEach(PermissaoDeAcesso.conhecidas.filter { $0.grupo == grupo }) { p in
                        CampoInterruptor(titulo: p.nome, explicacao: p.explicacao, ligado: ligacao(p))
                            .disabled(bloqueada)
                    }
                }
            }

            let novas = selecionadas.filter { $0.grupo == nil }.sorted { $0.bruto < $1.bruto }
            if !novas.isEmpty {
                VStack(alignment: .leading, spacing: Espaco.s) {
                    CabecalhoDeSecao(titulo: "Outras")
                    ForEach(novas) { p in
                        LinhaPadrao(icone: "questionmark.key.filled", titulo: p.nome, apoio: p.explicacao, mostrarSeta: false)
                    }
                }
            }

            if PermissaoDeAcesso.temCombinacaoProibida(selecionadas) {
                AvisoDeConflitoDePermissoes()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Movimento.interface, value: PermissaoDeAcesso.temCombinacaoProibida(selecionadas))
    }

    private func ligacao(_ p: PermissaoDeAcesso) -> Binding<Bool> {
        Binding(
            get: { selecionadas.contains(p) },
            set: { ligado in
                if ligado { selecionadas.insert(p) } else { selecionadas.remove(p) }
            }
        )
    }
}

private struct AvisoDeConflitoDePermissoes: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cor.azulProfundo)
            VStack(alignment: .leading, spacing: 4) {
                Text("Editar algoritmo e Atender plantão não vão juntas.")
                    .font(Tipo.apoioForte).foregroundStyle(Cor.texto)
                Text("Quem edita o algoritmo muda o risco de todos os pacientes de uma vez; quem está de plantão responde por um. A separação é de propósito, e o AUREA recusa as duas na mesma conta. Desligue uma delas para salvar.")
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

// MARK: - Novo profissional

private struct FolhaDeNovoProfissional: View {
    let store: EquipeStore
    let concluir: (String) -> Void

    @State private var nome = ""
    @State private var email = ""
    @State private var funcao: FuncaoProfissional? = nil
    @State private var registro = ""
    @State private var tipo: TipoDeContaDaEquipe? = .profissional
    @State private var senha = ""
    @State private var permissoes: Set<PermissaoDeAcesso> = []
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Equipe",
            titulo: "Novo profissional",
            acao: "Criar conta",
            icone: "person.badge.plus",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEntrada(rotulo: "Nome completo", texto: $nome, conteudo: .name)
            CampoDeEntrada(rotulo: "E-mail de acesso", texto: $email, teclado: .emailAddress, conteudo: .emailAddress)
            CampoDeEscolha(
                rotulo: "Função",
                opcoes: FuncaoProfissional.conhecidas.map { (valor: $0, nome: $0.nome) },
                selecionado: $funcao
            )
            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "Registro do conselho (opcional)", texto: $registro)
                Text("Ex.: CRM-SE 000000. Sem registro, a pessoa não assina conduta.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
            }
            VStack(alignment: .leading, spacing: 6) {
                CampoDeEscolha(
                    rotulo: "Tipo de conta",
                    opcoes: TipoDeContaDaEquipe.allCases.map { (valor: $0, nome: $0.nome) },
                    selecionado: $tipo
                )
                Text("Conta de equipe abre o painel do plantão; conta de administração abre cadastros e algoritmo. As permissões dizem o que cada uma pode fazer lá dentro.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "Senha provisória", texto: $senha, seguro: true, conteudo: .newPassword)
                Text("Pelo menos 8 caracteres. Entregue pessoalmente, nunca por e-mail; a pessoa troca em Conta.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ListaDePermissoesExplicadas(selecionadas: $permissoes)
                .padding(.top, Espaco.s)
        }
        .presentationDetents([.large])
    }

    private func enviar() async {
        let nomeLimpo = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailLimpo = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let registroLimpo = registro.trimmingCharacters(in: .whitespacesAndNewlines)

        if nomeLimpo.count < 2 { return falhar("Informe o nome completo.") }
        if emailLimpo.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) == nil { return falhar("Informe um e-mail válido — é com ele que a pessoa entra.") }
        guard let funcao else { return falhar("Escolha a função.") }
        guard let tipo else { return falhar("Escolha o tipo de conta.") }
        if senha.count < 8 { return falhar("A senha provisória precisa de pelo menos 8 caracteres.") }
        if PermissaoDeAcesso.temCombinacaoProibida(permissoes) {
            return falhar("Desligue Editar algoritmo ou Atender plantão — as duas não vão na mesma conta.")
        }

        enviando = true
        erro = nil
        let resultado = await store.criar(.init(
            nome: nomeLimpo,
            email: emailLimpo,
            funcao: funcao,
            registroDoConselho: registroLimpo.isEmpty ? nil : registroLimpo,
            perfil: tipo.rawValue,
            permissoes: permissoes.sorted { $0.bruto < $1.bruto },
            senhaProvisoria: senha
        ))
        enviando = false
        if let resultado { return falhar(resultado) }
        concluir(nomeLimpo)
    }

    private func falhar(_ mensagem: String) {
        Tato.erro()
        erro = mensagem
    }
}

// MARK: - Conta (permissões e acesso)

private struct FolhaDaContaDaEquipe: View {
    let conta: ContaDaEquipe
    let store: EquipeStore
    let ehVoce: Bool
    let concluir: (String) -> Void

    @State private var permissoes: Set<PermissaoDeAcesso>
    @State private var enviando = false
    @State private var erro: String?
    @State private var confirmandoAcesso = false
    @State private var alterandoAcesso = false
    @Environment(\.dismiss) private var fechar

    init(conta: ContaDaEquipe, store: EquipeStore, ehVoce: Bool, concluir: @escaping (String) -> Void) {
        self.conta = conta
        self.store = store
        self.ehVoce = ehVoce
        self.concluir = concluir
        _permissoes = State(initialValue: Set(conta.permissoes))
    }

    private var mudou: Bool { permissoes != Set(conta.permissoes) }

    var body: some View {
        FolhaDeFormulario(
            rotulo: conta.ehAdministracao ? "Conta de administração" : "Conta de equipe",
            titulo: conta.nome,
            acao: mudou ? "Salvar permissões" : "Fechar",
            icone: mudou ? "checkmark" : "xmark",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await salvar() } }
        ) {
            ficha
            if ehVoce {
                Label("Esta é a sua conta. Peça a outra pessoa com Gerenciar usuários para mudar suas permissões ou seu acesso — assim ninguém se tranca fora do AUREA.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .padding(Espaco.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficie(.afundado, raio: Raio.controle)
            }
            if !conta.ativo {
                Label("Conta desativada: a pessoa não entra e as permissões ficam guardadas até reativar.", systemImage: "pause.circle")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .padding(Espaco.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficie(.afundado, raio: Raio.controle)
            }
            ListaDePermissoesExplicadas(selecionadas: $permissoes, bloqueada: ehVoce)
                .padding(.top, Espaco.s)
            if !ehVoce {
                acesso.padding(.top, Espaco.s)
            }
        }
        .presentationDetents([.large])
        .confirmationDialog(
            conta.ativo ? "Desativar a conta de \(conta.nome)?" : "Reativar a conta de \(conta.nome)?",
            isPresented: $confirmandoAcesso,
            titleVisibility: .visible
        ) {
            Button(conta.ativo ? "Desativar e encerrar as sessões" : "Reativar conta") {
                Task { await alterarAcesso() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(conta.ativo
                 ? "A pessoa sai do AUREA agora, em todos os aparelhos, e não consegue entrar de novo até alguém reativar. O histórico e as permissões ficam guardados."
                 : "A pessoa volta a entrar com a senha que já tinha, com as permissões guardadas.")
        }
    }

    private var ficha: some View {
        VStack(alignment: .leading, spacing: Espaco.s) {
            linhaDaFicha("Função", conta.profissional?.funcao.nome ?? "Sem ficha de profissional")
            linhaDaFicha("Registro do conselho", conta.profissional?.registroDoConselho ?? "Não informado")
            linhaDaFicha("E-mail", conta.email ?? "Não informado")
            linhaDaFicha("Último acesso", conta.ultimoAcessoEm.map { "\(Formato.dia($0)) · \(Formato.hora($0))" } ?? "Nunca entrou")
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
    }

    private func linhaDaFicha(_ rotulo: String, _ valor: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(rotulo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
            Spacer(minLength: 12)
            Text(valor).font(Tipo.apoioForte).foregroundStyle(Cor.texto)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var acesso: some View {
        VStack(alignment: .leading, spacing: Espaco.s) {
            CabecalhoDeSecao(titulo: "Acesso")
            BotaoSecundario(
                titulo: alterandoAcesso ? "Salvando…" : (conta.ativo ? "Desativar conta" : "Reativar conta"),
                icone: conta.ativo ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark"
            ) {
                Tato.selecao()
                confirmandoAcesso = true
            }
            .disabled(alterandoAcesso)
            Text(conta.ativo
                 ? "Desativar encerra na hora todas as sessões abertas desta pessoa."
                 : "Reativar devolve o acesso com as permissões acima.")
                .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
        }
    }

    private func salvar() async {
        guard mudou, !ehVoce else { return fechar() }
        if PermissaoDeAcesso.temCombinacaoProibida(permissoes) {
            Tato.erro()
            erro = "Desligue Editar algoritmo ou Atender plantão — as duas não vão na mesma conta."
            return
        }
        enviando = true
        erro = nil
        let resultado = await store.salvarPermissoes(conta, permissoes)
        enviando = false
        if let resultado {
            Tato.erro()
            erro = resultado
        } else {
            concluir("Permissões de \(conta.nome) salvas.")
        }
    }

    private func alterarAcesso() async {
        alterandoAcesso = true
        erro = nil
        let novo = !conta.ativo
        let resultado = await store.alterarAtivo(conta, para: novo)
        alterandoAcesso = false
        if let resultado {
            Tato.erro()
            erro = resultado
        } else {
            concluir(novo ? "\(conta.nome) pode entrar de novo." : "Conta de \(conta.nome) desativada. A pessoa saiu do AUREA.")
        }
    }
}
