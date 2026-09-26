import SwiftUI

@MainActor
@Observable
final class DetalheDoConjuntoStore {
    struct Tudo: Sendable {
        let resumo: ConjuntoResumido
        let detalhe: ConjuntoDetalhado
        /// O que está valendo hoje, para dizer o que a publicação substitui.
        let publicadoAgora: ConjuntoResumido?
    }

    private(set) var carga: Carga<Tudo> = .carregando
    let conjuntoId: String
    private let api: ClienteAPI

    init(conjuntoId: String, api: ClienteAPI = .compartilhado) {
        self.conjuntoId = conjuntoId
        self.api = api
    }

    /// O detalhe da API não traz `ativo`, `publicadoEm` nem `criadoEm` — só a lista traz.
    /// As duas vão juntas, e a tela nunca mostra estado montado no cliente.
    func carregar() async {
        let anterior = carga.valor
        do {
            async let lista: [ConjuntoResumido] = api.obter("/admin/limiares")
            async let detalhe: ConjuntoDetalhado = api.obter("/admin/limiares/\(conjuntoId)")
            let (conjuntos, d) = try await (lista, detalhe)
            guard let resumo = conjuntos.first(where: { $0.id == conjuntoId }) else {
                carga = .falhou(.recusado("Este conjunto não existe mais."), anterior: anterior)
                return
            }
            carga = .pronto(Tudo(resumo: resumo, detalhe: d, publicadoAgora: conjuntos.first(where: \.ativo)))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    func publicar() async throws -> ConjuntoPublicado {
        try await ChamadaDoAdmin.compartilhada.acionar("/admin/limiares/\(conjuntoId)/publicar")
    }

    func validar() async throws -> ConjuntoValidado {
        try await ChamadaDoAdmin.compartilhada.acionar("/admin/limiares/\(conjuntoId)/validar")
    }
}

/// A2 + A5 — Um conjunto: as regras com a justificativa por extenso, a política, e as duas
/// ações que mudam o que o paciente recebe. Publicar é irreversível na prática — conjunto
/// publicado nunca é editado, publica-se outro — por isso passa por confirmação explícita.
struct DetalheDoConjuntoView: View {
    let lista: LimiaresStore
    @State private var store: DetalheDoConjuntoStore
    @State private var filtro = "TODOS"
    @State private var confirmandoPublicacao = false
    @State private var confirmandoValidacao = false
    @State private var resultado: String?
    @State private var aviso: String?
    @Environment(Sessao.self) private var sessao

    init(conjuntoId: String, lista: LimiaresStore) {
        self.lista = lista
        _store = State(initialValue: DetalheDoConjuntoStore(conjuntoId: conjuntoId))
    }

    private var podePublicar: Bool { sessao.eu?.permissoes.contains("PUBLICAR_ALGORITMO") == true }
    private var podeEditar: Bool { sessao.eu?.permissoes.contains("EDITAR_ALGORITMO") == true }

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            if let tudo = store.carga.valor {
                conteudo(tudo)
            } else {
                CabecalhoDeTela(rotulo: "Conjunto de limiares", titulo: "Conjunto")
                ConteudoDaCarga(carga: store.carga, linhasDeEsqueleto: 4, tentarDeNovo: { Task { await store.carregar() } }) { _ in EmptyView() }
            }
        }
        .telaEmpurradaDoAdmin()
        .task { await store.carregar() }
        .encerraSessaoNo401(store.carga.erro)
        .avisoTemporario($aviso)
        .sheet(isPresented: $confirmandoPublicacao) {
            if let tudo = store.carga.valor {
                ConfirmacaoDePublicacao(tudo: tudo, publicar: { try await store.publicar() }) { r in
                    confirmandoPublicacao = false
                    Task { await concluir(r.aviso ?? "Este conjunto passou a classificar pacientes reais a partir de agora. Ele não será editado; qualquer ajuste nasce em um conjunto novo.", toast: "\(r.publicado) publicado") }
                }
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $confirmandoValidacao) {
            if let tudo = store.carga.valor {
                ConfirmacaoDeValidacao(versao: tudo.resumo.versao, validar: { try await store.validar() }) { _ in
                    confirmandoValidacao = false
                    Task { await concluir("O conjunto está marcado como validado clinicamente, com a sua assinatura e a data de hoje.", toast: "Validação registrada") }
                }
                .presentationDetents([.large])
            }
        }
    }

    /// O estado depois da gravação vem do servidor, nunca de um objeto montado aqui: uma
    /// tela que desenha o resultado que ESPERA obter mente quando o servidor recusa.
    private func concluir(_ texto: String, toast: String) async {
        Tato.sucesso()
        resultado = texto
        aviso = toast
        async let a: Void = store.carregar()
        async let b: Void = lista.carregar()
        _ = await (a, b)
    }

    @ViewBuilder
    private func conteudo(_ tudo: DetalheDoConjuntoStore.Tudo) -> some View {
        let resumo = tudo.resumo
        let detalhe = tudo.detalhe

        CabecalhoDeTela(rotulo: "Conjunto de limiares", titulo: resumo.versao, contexto: detalhe.descricao)

        HStack(spacing: Espaco.s) {
            SeloDeEstadoDoConjunto(estado: resumo.estado)
            if resumo.ativo {
                Text("Classificando pacientes agora").font(Tipo.apoioForte).foregroundStyle(Cor.azulProfundo)
            }
        }

        // Sem exceção: conjunto sem assinatura clínica mostra a marca, publicado ou não.
        if resumo.validadoClinicamente {
            Label(validadoTexto(resumo), systemImage: "checkmark.seal")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
        } else {
            AvisoNaoValidado(versao: resumo.versao)
        }

        if let resultado {
            AvisoDoAdmin(titulo: "Feito", texto: resultado)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Origem").estiloDeRotulo()
            Text(detalhe.origem)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.texto)
                .fixedSize(horizontal: false, vertical: true)
        }

        GradeDeIndicadoresDoAdmin {
            CartaoDeIndicador(rotulo: "Regras", valor: "\(detalhe.regras.count)",
                              apoio: "\(Set(detalhe.regras.map(\.sintoma)).count) sintomas")
            CartaoDeIndicador(rotulo: "Classificações", valor: "\(resumo.classificacoesProduzidas)", apoio: "já produzidas por ele")
            CartaoDeIndicador(rotulo: "Criado em", valor: DataDoAdmin.diaCurto(resumo.criadoEm), apoio: DataDoAdmin.anoEHora(resumo.criadoEm))
            CartaoDeIndicador(rotulo: "Publicado em", valor: resumo.publicadoEm.map(DataDoAdmin.diaCurto) ?? "nunca",
                              apoio: resumo.publicadoEm.map(DataDoAdmin.anoEHora) ?? "rascunho")
        }

        if !detalhe.problemasDeIntegridade.isEmpty {
            AvisoDoAdmin(titulo: "Regras que nunca disparam",
                         texto: detalhe.problemasDeIntegridade.map { "• \($0)" }.joined(separator: "\n"),
                         grave: true)
        }

        CabecalhoDeSecao(titulo: "Política de classificação")
        VStack(spacing: Espaco.s) {
            linhaDePolitica("Combinação de sintomas", NomesDoAlgoritmo.combinacao(detalhe.politica.combinacao))
            linhaDePolitica("Efeito do antitérmico", NomesDoAlgoritmo.antitermico(detalhe.politica.efeitoDoAntitermico))
            linhaDePolitica("Questionário abandonado", NomesDoAlgoritmo.abandono(detalhe.politica.tratamentoDeAbandono))
        }

        regras(detalhe.regras)

        acoes(tudo)
    }

    private func validadoTexto(_ r: ConjuntoResumido) -> String {
        var partes = ["Validado clinicamente"]
        if let quem = r.validadoPor {
            partes.append("por \(quem.nome)" + (quem.registroDoConselho.map { " (\($0))" } ?? ""))
        }
        if let quando = r.validadoEm { partes.append("em \(DataDoAdmin.dia(quando))") }
        return partes.joined(separator: " ")
    }

    private func linhaDePolitica(_ titulo: String, _ valor: (nome: String, explicacao: String)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).estiloDeRotulo()
            Text(valor.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
            Text(valor.explicacao).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .accessibilityElement(children: .combine)
    }

    // MARK: Regras por sintoma

    @ViewBuilder
    private func regras(_ todas: [RegraDoConjunto]) -> some View {
        let ordem = ArvoreDoAlgoritmo.sintomas + Array(Set(todas.map(\.sintoma)).subtracting(ArvoreDoAlgoritmo.sintomas)).sorted()
        let presentes = ordem.filter { s in todas.contains { $0.sintoma == s } }
        let opcoes = [OpcaoDeSeletor(id: "TODOS", titulo: "Todos", contador: todas.count)]
            + presentes.map { s in OpcaoDeSeletor(id: s, titulo: NomesDoAlgoritmo.sintoma(s), contador: todas.filter { $0.sintoma == s }.count) }

        CabecalhoDeSecao(titulo: "Regras", contagem: todas.count)
        if todas.isEmpty {
            EstadoVazio(titulo: "Nenhuma regra.", texto: "Este conjunto não classifica nada: todo check-in sairia sem cor.", icone: "list.bullet")
                .superficie()
        } else {
            SeletorDePilulas(opcoes: opcoes, selecionado: $filtro)
                .padding(.horizontal, -Espaco.margem)

            ForEach(presentes.filter { filtro == "TODOS" || $0 == filtro }, id: \.self) { sintoma in
                let doSintoma = todas.filter { $0.sintoma == sintoma }.sorted { $0.ordem < $1.ordem }
                VStack(alignment: .leading, spacing: Espaco.s) {
                    Text(NomesDoAlgoritmo.sintoma(sintoma))
                        .font(Tipo.tituloDeBloco)
                        .foregroundStyle(Cor.texto)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, Espaco.s)
                    ForEach(Array(doSintoma.enumerated()), id: \.element.id) { i, regra in
                        CartaoDeRegra(regra: regra).entradaEscalonada(i)
                    }
                }
            }
        }
    }

    // MARK: Ações

    @ViewBuilder
    private func acoes(_ tudo: DetalheDoConjuntoStore.Tudo) -> some View {
        let resumo = tudo.resumo
        let podeComparar = tudo.publicadoAgora != nil && tudo.publicadoAgora?.id != resumo.id

        if podePublicar || podeEditar || podeComparar {
            CabecalhoDeSecao(titulo: "Ações")
                .padding(.top, Espaco.s)
            VStack(alignment: .leading, spacing: Espaco.m) {
                if podeComparar, let atual = tudo.publicadoAgora {
                    NavigationLink(value: RotaDoAlgoritmo.diferenca(de: atual.id, para: resumo.id)) {
                        LinhaPadrao(icone: "arrow.left.arrow.right", titulo: "Comparar com o publicado",
                                    apoio: "O que muda de \(atual.versao) para \(resumo.versao)")
                    }
                    .buttonStyle(.pressionavel)
                }
                if podeEditar {
                    NavigationLink(value: RotaDoAlgoritmo.novo(baseId: resumo.id)) {
                        LinhaPadrao(icone: "doc.on.doc", titulo: "Novo conjunto a partir deste",
                                    apoio: "Conjunto não se edita: o ajuste nasce numa cópia, como rascunho")
                    }
                    .buttonStyle(.pressionavel)
                }
                if podePublicar {
                    if resumo.estado == .rascunho {
                        BotaoPrimario(titulo: "Publicar este conjunto", icone: "arrow.up.circle") {
                            Tato.aviso()
                            confirmandoPublicacao = true
                        }
                    }
                    if !resumo.validadoClinicamente {
                        BotaoSecundario(titulo: "Marcar como validado clinicamente", icone: "checkmark.seal") {
                            confirmandoValidacao = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Confirmação de publicação

/// A decisão mais perigosa do sistema, dita no ponto da decisão: o que acontece, o que é
/// substituído, e — se for o caso — que ninguém assinou estes cortes. Quem decide aqui pode
/// nunca ter rolado até o selo da página, então o aviso se repete DENTRO da folha.
private struct ConfirmacaoDePublicacao: View {
    let tudo: DetalheDoConjuntoStore.Tudo
    let publicar: () async throws -> ConjuntoPublicado
    let concluido: (ConjuntoPublicado) -> Void

    @State private var ciente = false
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(rotulo: "Efeito clínico imediato",
                          titulo: "Publicar \(tudo.resumo.versao)?",
                          acao: "Publicar conjunto",
                          icone: "arrow.up.circle",
                          enviando: enviando,
                          erro: erro,
                          enviar: { Task { await confirmar() } }) {
            if !tudo.resumo.validadoClinicamente {
                AvisoDoAdmin(titulo: "Conjunto ainda não validado clinicamente",
                             texto: "Nenhuma pessoa com responsabilidade clínica assinou estes cortes. Publicar agora coloca esta política em produção sem essa revisão.",
                             grave: true)
            }
            Text("A partir da publicação, este conjunto passa a classificar pacientes reais no check-in diário. Ele substitui \(tudo.publicadoAgora.map { "o \($0.versao), que classifica os pacientes hoje" } ?? "nenhum conjunto: hoje nada está publicado").")
                .font(Tipo.corpo)
                .foregroundStyle(Cor.texto)
                .fixedSize(horizontal: false, vertical: true)
            Text("Conjunto publicado nunca é editado depois. Se um corte precisar mudar, a correção nasce em um conjunto novo, não numa edição deste.")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
            CampoInterruptor(titulo: "Entendo que isto muda o risco de todos os pacientes",
                             explicacao: "\(tudo.detalhe.regras.count) regras passam a decidir a cor de cada check-in.",
                             ligado: $ciente)
        }
        .interactiveDismissDisabled(enviando)
    }

    private func confirmar() async {
        guard ciente else {
            Tato.aviso()
            erro = "Confirme que entendeu o efeito antes de publicar."
            return
        }
        enviando = true
        erro = nil
        do {
            let r = try await publicar()
            enviando = false
            concluido(r)
        } catch {
            enviando = false
            Tato.erro()
            // A recusa aparece no lugar da decisão: fechar a folha escondendo o erro faria a
            // pessoa voltar achando que publicou.
            erro = "Nada foi alterado. \(ErroDaAPI(error).mensagem)"
        }
    }
}

// MARK: - Confirmação de validação

/// Validar é assinar responsabilidade técnica pelos cortes — ato diferente de publicar, e a
/// API só aceita de quem tem ficha de profissional de saúde. A recusa dela vem por extenso.
private struct ConfirmacaoDeValidacao: View {
    let versao: String
    let validar: () async throws -> ConjuntoValidado
    let concluido: (ConjuntoValidado) -> Void

    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(rotulo: "Responsabilidade técnica",
                          titulo: "Marcar \(versao) como validado clinicamente?",
                          acao: "Confirmar validação",
                          icone: "checkmark.seal",
                          enviando: enviando,
                          erro: erro,
                          enviar: { Task { await confirmar() } }) {
            Text("Esta marca declara que uma pessoa com responsabilidade clínica revisou e assinou os cortes deste conjunto. A assinatura leva o seu nome e a data de hoje.")
                .font(Tipo.corpo)
                .foregroundStyle(Cor.texto)
                .fixedSize(horizontal: false, vertical: true)
            Text("Enquanto ausente, todo resultado gerado por ele carrega o selo de não validado, inclusive se já estiver publicado.")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .interactiveDismissDisabled(enviando)
    }

    private func confirmar() async {
        enviando = true
        erro = nil
        do {
            let r = try await validar()
            enviando = false
            concluido(r)
        } catch {
            enviando = false
            Tato.erro()
            erro = "Nada foi alterado. \(ErroDaAPI(error).mensagem)"
        }
    }
}
