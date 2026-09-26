import SwiftUI

@MainActor
@Observable
final class ProntuarioStore {
    private(set) var carga: Carga<FichaDoProntuario> = .carregando
    let pacienteId: String
    let gravacao: GravacaoDoRegistro
    private let api: ClienteAPI

    init(pacienteId: String, api: ClienteAPI = .compartilhado) {
        self.pacienteId = pacienteId
        self.api = api
        gravacao = GravacaoDoRegistro(api: api)
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/painel/pacientes/\(pacienteId)/historico"))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }
}

/// O prontuário, na ordem em que a enfermeira ao telefone precisa:
/// quem é → por que está aqui (a regra, por extenso) e o que já foi feito → como falar com
/// ele → o que ele toma e ao que é alérgico → o contexto de casa e o que trava o tratamento
/// → o histórico.
///
/// Todo o conteúdo fica protegido de captura de tela: sai em branco num screenshot.
///
/// O registro do plantão (barreira, pendência, internação, contexto social, conduta) mora
/// AQUI e não num cadastro à parte: quem descobre que o paciente depende de carona é a
/// enfermagem no telefone, com o prontuário aberto. As folhas saem desta view de fora — a de
/// dentro vive num `UIHostingController` onde nem `Environment` nem `.sheet` funcionam direito.
struct ProntuarioView: View {
    let nome: String
    let situacao: SituacaoClinica?
    @State private var store: ProntuarioStore
    @State private var folha: FolhaDoRegistro?
    @State private var resolucao: Resolucao?
    @State private var resolvendo = false
    @State private var falha: String?
    @State private var aviso: String?
    @Environment(Sessao.self) private var sessao

    init(pacienteId: String, nome: String, situacao: SituacaoClinica?) {
        self.nome = nome
        self.situacao = situacao
        _store = State(initialValue: ProntuarioStore(pacienteId: pacienteId))
    }

    var body: some View {
        Group {
            if Self.protecaoLigada {
                ProtegidoDeCaptura { conteudo }
            } else {
                conteudo
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .containerBackground(.clear, for: .navigation)
        .task { await store.carregar() }
        .encerraSessaoNo401(store.carga.erro)
        .avisoTemporario($aviso)
        .sheet(item: $folha) { folha in
            folhaAberta(folha).presentationDetents([.large])
        }
        .confirmationDialog(resolucao?.pergunta ?? "", isPresented: resolucaoAberta,
                            titleVisibility: .visible, presenting: resolucao) { r in
            Button(r.botao) { resolver(r) }
            Button("Cancelar", role: .cancel) {}
        } message: { r in
            Text(r.explicacao)
        }
        .alert("A gravação falhou", isPresented: falhaAberta) {
            Button("Entendi", role: .cancel) {}
        } message: {
            Text(falha ?? "")
        }
    }

    private var conteudo: some View {
        ConteudoDoProntuario(nome: nome, situacao: situacao, carga: store.carga, acoes: acoes) {
            Task { await store.carregar() }
        }
    }

    // MARK: Registro

    private var permissoes: PermissoesDoRegistro {
        sessao.eu.map { PermissoesDoRegistro($0.permissoes) } ?? .nenhuma
    }

    private var acoes: AcoesDoProntuario {
        AcoesDoProntuario(
            permissoes: permissoes,
            ocupado: resolvendo,
            abrir: { folha = $0 },
            resolver: { resolucao = $0 }
        )
    }

    @ViewBuilder
    private func folhaAberta(_ folha: FolhaDoRegistro) -> some View {
        let id = store.pacienteId
        let g = store.gravacao
        switch folha {
        case .barreira:
            FolhaDeBarreira(pacienteId: id, gravacao: g) { concluir("Barreira registrada.") }
        case .pendencia:
            FolhaDePendencia(pacienteId: id, gravacao: g) { concluir("Pendência registrada.") }
        case .internacao:
            FolhaDeInternacao(pacienteId: id, gravacao: g) { concluir("Internação registrada.") }
        case .contextoSocial(let atual, let avaliado):
            FolhaDeContextoSocial(pacienteId: id, gravacao: g, atual: atual, avaliado: avaliado) {
                concluir("Contexto social gravado.")
            }
        case .intervencao(let sessaoId, let iniciadaEm):
            FolhaDeIntervencao(sessaoId: sessaoId, iniciadaEm: iniciadaEm, gravacao: g) {
                concluir("Intervenção registrada.")
            }
        }
    }

    /// Depois de gravar, relê do servidor: a tela mostra o que ficou guardado, não o que o
    /// app torceu para ter ficado.
    private func concluir(_ mensagem: String) {
        aviso = mensagem
        Task { await store.carregar() }
    }

    private func resolver(_ r: Resolucao) {
        resolvendo = true
        let g = store.gravacao
        Task {
            do {
                switch r {
                case .barreira(let id, _): try await g.resolverBarreira(id)
                case .pendencia(let id, _): try await g.resolverPendencia(id)
                }
                Tato.sucesso()
                aviso = r.sucesso
                await store.carregar()
            } catch {
                Tato.erro()
                falha = FalhaDeGravacao.mensagem(error, acao: "registrar no prontuário")
            }
            resolvendo = false
        }
    }

    private var resolucaoAberta: Binding<Bool> {
        Binding(get: { resolucao != nil }, set: { if !$0 { resolucao = nil } })
    }

    private var falhaAberta: Binding<Bool> {
        Binding(get: { falha != nil }, set: { if !$0 { falha = nil } })
    }

    /// Só em DEBUG dá para desligar, com o argumento `-revisaoDeDesign` — senão nenhuma
    /// captura de revisão de layout (Maestro, screenshot) consegue ver o prontuário.
    private static var protecaoLigada: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-revisaoDeDesign")
        #else
        true
        #endif
    }
}

/// Resolver, não apagar: o histórico mostra o que o serviço destravou. Por isso não há
/// "desfazer" — e por isso pede confirmação.
enum Resolucao: Identifiable {
    case barreira(id: String, nome: String)
    case pendencia(id: String, nome: String)

    var id: String {
        switch self {
        case .barreira(let id, _), .pendencia(let id, _): id
        }
    }

    var pergunta: String {
        switch self {
        case .barreira(_, let nome): "Resolver a barreira “\(nome)”?"
        case .pendencia(_, let nome): "Resolver a pendência “\(nome)”?"
        }
    }

    var explicacao: String {
        switch self {
        case .barreira: "Ela sai do prontuário e do mapa de barreiras. O registro continua no histórico do serviço; não há como reabrir por aqui."
        case .pendencia: "Ela sai do prontuário e da tela de navegação. Não há como reabrir por aqui."
        }
    }

    var botao: String {
        switch self {
        case .barreira: "Resolver barreira"
        case .pendencia: "Resolver pendência"
        }
    }

    var sucesso: String {
        switch self {
        case .barreira: "Barreira resolvida."
        case .pendencia: "Pendência resolvida."
        }
    }
}

/// O que o conteúdo protegido pode pedir à view de fora. Só closures e valores: lá dentro
/// não há `Environment`.
struct AcoesDoProntuario {
    let permissoes: PermissoesDoRegistro
    /// Uma resolução em andamento: os botões de resolver esperam.
    let ocupado: Bool
    let abrir: (FolhaDoRegistro) -> Void
    let resolver: (Resolucao) -> Void
}

/// Separado da view de cima porque vive dentro de um `UIHostingController` (a proteção de
/// captura): ali o `Environment` não chega, então tudo entra por parâmetro.
private struct ConteudoDoProntuario: View {
    let nome: String
    let situacao: SituacaoClinica?
    let carga: Carga<FichaDoProntuario>
    let acoes: AcoesDoProntuario
    let recarregar: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                cabecalho

                if let erro = carga.erro, carga.valor == nil {
                    CartaoDeErro(erro: erro, tentarDeNovo: recarregar)
                }

                if let ficha = carga.valor {
                    let p = ficha.prontuario
                    let r = ficha.registro
                    UltimoCheckin(prontuario: p, registro: r, acoes: acoes)
                    Contatos(contatos: p.contatos)
                    SaudeDoPaciente(prontuario: p)
                    ContextoDeCasa(prontuario: p, registro: r, acoes: acoes)
                    Barreiras(barreiras: p.barreiras, acoes: acoes)
                    Pendencias(pendencias: r.pendencias, acoes: acoes)
                    Internacoes(internacoes: p.internacoes, acoes: acoes)
                    HistoricoDeCheckins(prontuario: p, registro: r, acoes: acoes)
                    Agenda(eventos: p.eventosDeAgenda)
                } else if carga.erro == nil {
                    VStack(alignment: .leading, spacing: Espaco.m) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                Esqueleto(largura: 120, altura: 10)
                                Esqueleto(altura: 12)
                                Esqueleto(largura: 220, altura: 12)
                            }
                            .padding(Espaco.l)
                            .superficie()
                        }
                    }
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.top, Espaco.s)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    /// A ficha do BT: avatar grande, nome, e as etiquetas logo abaixo.
    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Iniciais(nome: nome, tamanho: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(nome)
                        .font(Tipo.titulo)
                        .foregroundStyle(Cor.texto)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let situacao { SeloClinico(situacao: situacao) }
                }
            }
            if let p = carga.valor?.prontuario {
                Text(p.diagnostico)
                    .font(Tipo.corpo)
                    .foregroundStyle(Cor.textoSuave)
                HStack(spacing: 10) {
                    Metrica(valor: "\(Formato.idade(nascimento: p.dataNascimento))", rotulo: "anos")
                    if let c = p.numeroDoCiclo { Metrica(valor: "C\(c)", rotulo: "ciclo") }
                    if let d = p.diaDoCiclo { Metrica(valor: "D\(d)", rotulo: "hoje") }
                    if p.ecog != "NAO_AVALIADO" { Metrica(valor: p.ecog.replacingOccurrences(of: "ECOG_", with: ""), rotulo: "ECOG") }
                }
                .padding(.top, 4)
                if let protocolo = p.protocolo {
                    Text(protocolo)
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                }
            }
        }
    }
}

private struct Metrica: View {
    let valor: String
    let rotulo: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor).font(Tipo.colunaForte).foregroundStyle(Cor.texto)
            Text(rotulo).font(Tipo.rotulo).tracking(0.4).foregroundStyle(Cor.textoFraco)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .superficie(.plano, raio: 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bloco

/// Ação no topo de um bloco ("+ Registrar"). Só aparece para quem pode gravar.
private struct AcaoDeBloco {
    let titulo: String
    var icone = "plus"
    let rotuloAcessivel: String
    let executar: () -> Void
}

private struct Bloco<Conteudo: View>: View {
    let titulo: String
    var contagem: Int?
    var acao: AcaoDeBloco?
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                CabecalhoDeSecao(titulo: titulo, contagem: contagem)
                if let acao {
                    BotaoDoRegistro(titulo: acao.titulo, icone: acao.icone,
                                    rotuloAcessivel: acao.rotuloAcessivel, acao: acao.executar)
                }
            }
            VStack(alignment: .leading, spacing: 0) { conteudo }
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficie()
        }
    }
}

private struct LinhaDeBloco<Conteudo: View>: View {
    var ultima = false
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            conteudo
                .padding(.horizontal, Espaco.l)
                .padding(.vertical, 14)
            if !ultima {
                Rectangle().fill(Cor.filete).frame(height: 0.75).padding(.leading, Espaco.l)
            }
        }
    }
}

// MARK: - Último check-in (a regra, por extenso)

/// Lei 2 do produto: toda classificação vem com a regra que a produziu, por extenso.
/// Sem isso o painel vira caixa-preta. Aqui ela não se esconde atrás de toque.
private struct UltimoCheckin: View {
    let prontuario: Prontuario
    let registro: RegistroDoProntuario
    let acoes: AcoesDoProntuario

    var body: some View {
        let ultimo = prontuario.checkins.first

        Bloco(titulo: "Último check-in") {
            if let ultimo {
                let classificacao = ultimo.classificacao
                LinhaDeBloco(ultima: regras(classificacao).isEmpty && classificacao?.motivoDeNaoClassificar == nil) {
                    HStack {
                        if let r = classificacao?.resultado {
                            SeloClinico(situacao: r.situacao)
                        } else {
                            SeloClinico(situacao: .silencio)
                        }
                        Spacer()
                        Text(Formato.quando(ultimo.sessao.iniciadaEm))
                            .font(Tipo.apoio)
                            .monospacedDigit()
                            .foregroundStyle(Cor.textoFraco)
                    }
                }

                if let motivo = classificacao?.motivoDeNaoClassificar {
                    // Lei 3: silêncio não é verde. Questionário não terminado não vira resultado.
                    LinhaDeBloco(ultima: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Não classificado").font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                            Text(motivo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        }
                    }
                }

                let lista = regras(classificacao)
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, regra in
                    LinhaDeBloco(ultima: i == lista.count - 1) {
                        LinhaDeRegra(regra: regra)
                    }
                }

                if let conjunto = classificacao?.conjunto, !conjunto.validadoClinicamente {
                    AvisoNaoValidado(versao: conjunto.versao)
                        .padding(.horizontal, Espaco.l)
                        .padding(.bottom, 14)
                }
            } else {
                LinhaDeBloco(ultima: true) {
                    Text("Nunca respondeu o questionário.")
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                }
            }
        }

        if let ultimo {
            CondutasDoCheckin(sessao: ultimo.sessao,
                              intervencoes: registro.intervencoes(daSessao: ultimo.sessao.id),
                              acoes: acoes)
        }
    }

    private func regras(_ c: Prontuario.ClassificacaoDaSessao?) -> [RegraDisparada] {
        (c?.explicacao.porSintoma ?? []).flatMap(\.regrasDisparadas)
    }
}

private struct LinhaDeRegra: View {
    let regra: RegraDisparada

    var body: some View {
        let tons = Faixa.tons(regra.classificacao.situacao)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(tons.tinta).frame(width: 8, height: 8)
                Text(regra.sintoma.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                Spacer()
                Text(Formato.observado(regra))
                    .font(Tipo.apoioForte)
                    .monospacedDigit()
                    .foregroundStyle(tons.tinta)
            }
            Text(regra.justificativa)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(regra.classificacao.situacao.nome): \(regra.sintoma.nome), \(Formato.observado(regra)). \(regra.justificativa)")
    }
}

// MARK: - Contatos

private struct Contatos: View {
    let contatos: [Prontuario.Contato]

    var body: some View {
        Bloco(titulo: "Ligar") {
            if contatos.isEmpty {
                LinhaDeBloco(ultima: true) {
                    Text("Nenhum telefone cadastrado.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
            }
            ForEach(Array(contatos.enumerated()), id: \.offset) { i, contato in
                LinhaDeBloco(ultima: i == contatos.count - 1) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contato.tipo == "CONTATO_DE_EMERGENCIA" ? "Emergência · \(contato.relacao ?? "contato")" : "Paciente")
                                .estiloDeRotulo()
                            Text(contato.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                            Text(Formato.telefone(contato.telefone))
                                .font(Tipo.apoio)
                                .monospacedDigit()
                                .foregroundStyle(Cor.textoSuave)
                        }
                        Spacer()
                        if let url = URL(string: "tel:\(contato.telefone.filter(\.isNumber))") {
                            Link(destination: url) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Cor.textoInvertido)
                                    .frame(width: 44, height: 44)
                                    .background(Cor.azulProfundo, in: Circle())
                            }
                            .accessibilityLabel("Ligar para \(contato.nome)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Saúde

private struct SaudeDoPaciente: View {
    let prontuario: Prontuario

    var body: some View {
        let emVigor = prontuario.prescricoes.filter { $0.encerradaEm == nil }

        Bloco(titulo: "Alergias e medicação") {
            LinhaDeBloco {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alergias").estiloDeRotulo()
                    if prontuario.alergias.isEmpty {
                        Text("Nenhuma registrada").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    } else {
                        Text(prontuario.alergias.map(\.descricao).joined(separator: ", "))
                            .font(Tipo.corpoForte)
                            .foregroundStyle(Cor.texto)
                    }
                }
            }
            if !prontuario.comorbidades.isEmpty {
                LinhaDeBloco {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comorbidades").estiloDeRotulo()
                        Text(prontuario.comorbidades.map(\.descricao).joined(separator: ", "))
                            .font(Tipo.corpo).foregroundStyle(Cor.texto)
                    }
                }
            }
            if emVigor.isEmpty {
                LinhaDeBloco(ultima: true) {
                    Text("Nenhuma prescrição em vigor.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
            }
            ForEach(Array(emVigor.enumerated()), id: \.element.id) { i, p in
                LinhaDeBloco(ultima: i == emVigor.count - 1) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.medicamento.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                        Text(p.posologia).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        if let quem = p.prescritaPor {
                            Text("Prescrito por \(quem.nome)").font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Contexto de casa

/// Contexto social. Se ninguém perguntou, a tela diz isso — não mostra "não mora sozinho"
/// e "sem cuidador" por omissão (a mesma lei do silêncio: não perguntar não é "não").
private struct ContextoDeCasa: View {
    let prontuario: Prontuario
    let registro: RegistroDoProntuario
    let acoes: AcoesDoProntuario

    var body: some View {
        let avaliadoEm = registro.contextoSocialAvaliadoEm

        Bloco(titulo: "Em casa", acao: acaoDeEditar(avaliado: avaliadoEm != nil)) {
            if let avaliadoEm {
                LinhaDeBloco(ultima: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        Fato(texto: prontuario.moraSozinho ? "Mora sozinho" : "Não mora sozinho", alerta: prontuario.moraSozinho)
                        Fato(texto: prontuario.temCuidador ? "Tem cuidador" : "Sem cuidador", alerta: !prontuario.temCuidador)
                        Fato(texto: prontuario.dificuldadeDeTransporte ? "Dificuldade de transporte" : "Transporte sem dificuldade",
                             alerta: prontuario.dificuldadeDeTransporte)
                        Text("Avaliado em \(Formato.diaCompleto(avaliadoEm))")
                            .font(Tipo.apoio)
                            .foregroundStyle(Cor.textoFraco)
                            .padding(.top, 2)
                    }
                }
            } else {
                LinhaDeBloco(ultima: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contexto social nunca avaliado").font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                        Text("Ninguém perguntou ainda se mora sozinho, se tem cuidador ou como chega ao serviço. Até lá, o risco trata os três como ausentes, não como negativos.")
                            .font(Tipo.apoio)
                            .foregroundStyle(Cor.textoSuave)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func acaoDeEditar(avaliado: Bool) -> AcaoDeBloco? {
        guard acoes.permissoes.registrar else { return nil }
        let atual = GravacaoDoRegistro.ContextoSocial(moraSozinho: prontuario.moraSozinho,
                                                     dificuldadeDeTransporte: prontuario.dificuldadeDeTransporte,
                                                     temCuidador: prontuario.temCuidador)
        return AcaoDeBloco(titulo: avaliado ? "Revisar" : "Avaliar", icone: "house",
                           rotuloAcessivel: avaliado ? "Revisar contexto social" : "Avaliar contexto social") {
            acoes.abrir(.contextoSocial(atual, avaliado: avaliado))
        }
    }
}

/// Um fato de contexto. O ponto escuro marca o que pesa contra — sem cor clínica, porque
/// contexto social não é classificação.
private struct Fato: View {
    let texto: String
    let alerta: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(alerta ? Cor.azulProfundo : Cor.fundoFundo)
                .frame(width: 7, height: 7)
            Text(texto)
                .font(alerta ? Tipo.apoioForte : Tipo.apoio)
                .foregroundStyle(alerta ? Cor.texto : Cor.textoSuave)
        }
    }
}

// MARK: - Barreiras, pendências, internações

/// Barreiras de acesso abertas. Para quem só lê, o bloco some quando não há nada; para quem
/// registra, fica — é onde mora o botão.
private struct Barreiras: View {
    let barreiras: [Prontuario.Barreira]
    let acoes: AcoesDoProntuario

    var body: some View {
        if !barreiras.isEmpty || acoes.permissoes.registrar {
            Bloco(titulo: "Barreiras de acesso", contagem: barreiras.isEmpty ? nil : barreiras.count,
                  acao: acoes.permissoes.registrar
                    ? AcaoDeBloco(titulo: "Registrar", rotuloAcessivel: "Registrar barreira") { acoes.abrir(.barreira) }
                    : nil) {
                if barreiras.isEmpty {
                    LinhaDeBloco(ultima: true) {
                        Text("Nenhuma barreira aberta.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    }
                }
                ForEach(Array(barreiras.enumerated()), id: \.element.id) { i, b in
                    let nome = TipoDeBarreira(bruto: b.tipo).nome
                    LinhaDeBloco(ultima: i == barreiras.count - 1) {
                        LinhaResolvivel(
                            rotulo: "Desde \(Formato.dia(b.criadaEm))",
                            titulo: nome,
                            detalhe: b.descricao,
                            podeResolver: acoes.permissoes.registrar,
                            ocupado: acoes.ocupado,
                            rotuloDoBotao: "Resolver barreira \(nome)"
                        ) {
                            acoes.resolver(.barreira(id: b.id, nome: nome))
                        }
                    }
                }
            }
        }
    }
}

/// Pendências pré-tratamento abertas, da data mais próxima para a mais distante.
private struct Pendencias: View {
    let pendencias: [RegistroDoProntuario.Pendencia]
    let acoes: AcoesDoProntuario

    var body: some View {
        if !pendencias.isEmpty || acoes.permissoes.registrar {
            Bloco(titulo: "Pendências pré-tratamento", contagem: pendencias.isEmpty ? nil : pendencias.count,
                  acao: acoes.permissoes.registrar
                    ? AcaoDeBloco(titulo: "Registrar", rotuloAcessivel: "Registrar pendência") { acoes.abrir(.pendencia) }
                    : nil) {
                if pendencias.isEmpty {
                    LinhaDeBloco(ultima: true) {
                        Text("Nenhuma pendência aberta.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    }
                }
                ForEach(Array(pendencias.enumerated()), id: \.element.id) { i, p in
                    LinhaDeBloco(ultima: i == pendencias.count - 1) {
                        LinhaResolvivel(
                            rotulo: rotuloDaData(p.referenteA),
                            titulo: p.tipo.nome,
                            detalhe: p.descricao,
                            podeResolver: acoes.permissoes.registrar,
                            ocupado: acoes.ocupado,
                            rotuloDoBotao: "Resolver pendência \(p.tipo.nome)"
                        ) {
                            acoes.resolver(.pendencia(id: p.id, nome: p.tipo.nome))
                        }
                    }
                }
            }
        }
    }

    /// A data do tratamento que a pendência ameaça, dita do jeito que o plantão pensa.
    private func rotuloDaData(_ data: Date) -> String {
        switch DataCivil.diasAte(data) {
        case 0: "Tratamento hoje"
        case 1: "Tratamento amanhã"
        case let d where d < 0: "Tratamento era \(DataCivil.textoCurto(data))"
        default: "Tratamento \(DataCivil.textoCurto(data))"
        }
    }
}

private struct Internacoes: View {
    let internacoes: [Prontuario.Internacao]
    let acoes: AcoesDoProntuario

    var body: some View {
        if !internacoes.isEmpty || acoes.permissoes.registrar {
            Bloco(titulo: "Internações",
                  acao: acoes.permissoes.registrar
                    ? AcaoDeBloco(titulo: "Registrar", rotuloAcessivel: "Registrar internação") { acoes.abrir(.internacao) }
                    : nil) {
                if internacoes.isEmpty {
                    LinhaDeBloco(ultima: true) {
                        Text("Nenhuma internação registrada.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    }
                }
                ForEach(Array(internacoes.enumerated()), id: \.element.id) { i, item in
                    LinhaDeBloco(ultima: i == internacoes.count - 1) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(periodo(item)).estiloDeRotulo()
                            Text(item.motivo).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                            if let local = item.local {
                                Text(local).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// Datas civis: lidas em UTC, senão "10 de jan." vira "9 de jan." em Brasília.
    private func periodo(_ i: Prontuario.Internacao) -> String {
        if let alta = i.altaEm {
            return "\(DataCivil.textoCurto(i.iniciadaEm)) até \(DataCivil.textoCompleto(alta))"
        }
        return "Internado desde \(DataCivil.textoCompleto(i.iniciadaEm))"
    }
}

/// Linha com botão "Resolver" à direita (barreira, pendência).
private struct LinhaResolvivel: View {
    let rotulo: String
    let titulo: String
    let detalhe: String?
    let podeResolver: Bool
    let ocupado: Bool
    let rotuloDoBotao: String
    let resolver: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rotulo).estiloDeRotulo()
                Text(titulo).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                if let detalhe {
                    Text(detalhe).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if podeResolver {
                Button(action: resolver) {
                    Text("Resolver")
                        .font(Tipo.apoioForte)
                        .foregroundStyle(Cor.azulProfundo)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .overlay(Capsule().strokeBorder(Cor.fileteForte, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressionavel)
                .disabled(ocupado)
                .opacity(ocupado ? 0.5 : 1)
                .accessibilityLabel(rotuloDoBotao)
            }
        }
    }
}

/// A ação de registrar no topo de um bloco. Mesmo desenho do `BotaoDeAcaoEmLinha`, mas com
/// os 44 pt de toque no rótulo (o compartilhado tem 40).
private struct BotaoDoRegistro: View {
    let titulo: String
    let icone: String
    let rotuloAcessivel: String
    let acao: () -> Void

    var body: some View {
        Button {
            Tato.selecao()
            acao()
        } label: {
            Label(titulo, systemImage: icone)
                .font(Tipo.apoioForte)
                .foregroundStyle(Cor.azulProfundo)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Cor.azulGelo.opacity(0.45)))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressionavel)
        .fixedSize()
        .accessibilityLabel(rotuloAcessivel)
    }
}

// MARK: - Condutas (intervenções)

/// As condutas registradas num check-in. A intervenção se amarra à SESSÃO que gerou o
/// alerta, não ao paciente solto — é o que mede depois "do alerta ao contato".
private struct CondutasDoCheckin: View {
    let sessao: Prontuario.SessaoDeTriagem
    let intervencoes: [RegistroDoProntuario.IntervencaoDaSessao]
    let acoes: AcoesDoProntuario

    var body: some View {
        if !intervencoes.isEmpty || acoes.permissoes.intervir {
            Bloco(titulo: "Condutas deste check-in", contagem: intervencoes.isEmpty ? nil : intervencoes.count,
                  acao: acoes.permissoes.intervir
                    ? AcaoDeBloco(titulo: "Registrar", rotuloAcessivel: "Registrar intervenção neste check-in") {
                        acoes.abrir(.intervencao(sessaoId: sessao.id, iniciadaEm: sessao.iniciadaEm))
                    }
                    : nil) {
                if intervencoes.isEmpty {
                    LinhaDeBloco(ultima: true) {
                        Text("Nenhuma intervenção registrada.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    }
                }
                ForEach(Array(intervencoes.enumerated()), id: \.element.id) { i, item in
                    LinhaDeBloco(ultima: i == intervencoes.count - 1) {
                        LinhaDeConduta(intervencao: item)
                    }
                }
            }
        }
    }
}

private struct LinhaDeConduta: View {
    let intervencao: RegistroDoProntuario.IntervencaoDaSessao

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                PontoDeDesfecho(desfecho: intervencao.situacao)
                Spacer(minLength: 8)
                Text(Formato.quando(intervencao.contatoRealizadoEm))
                    .font(Tipo.apoio)
                    .monospacedDigit()
                    .foregroundStyle(Cor.textoFraco)
            }
            Text(intervencao.conduta)
                .font(Tipo.corpo)
                .foregroundStyle(Cor.texto)
                .fixedSize(horizontal: false, vertical: true)
            Text(intervencao.profissional?.nome ?? "Profissional do plantão")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
        }
        .accessibilityElement(children: .combine)
    }
}

/// O desfecho, dito por palavra. Sem cor clínica: "encaminhado ao PA" é o único que pesa
/// (saiu do alcance da equipe), e pesa em azul e negrito, não em vermelho.
struct PontoDeDesfecho: View {
    let desfecho: DesfechoDaIntervencao

    var body: some View {
        let grave = desfecho == .encaminhadoAoPA
        let resolvido = desfecho == .resolvido
        HStack(spacing: 7) {
            Circle()
                .fill(grave ? Cor.azulProfundo : resolvido ? Cor.fundoFundo : Cor.textoFraco)
                .frame(width: 7, height: 7)
            Text(desfecho.nome)
                .font(grave ? Tipo.apoioForte : Tipo.apoio)
                .foregroundStyle(resolvido ? Cor.textoSuave : Cor.texto)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Situação: \(desfecho.nome)")
    }
}

// MARK: - Histórico

private struct HistoricoDeCheckins: View {
    let prontuario: Prontuario
    let registro: RegistroDoProntuario
    let acoes: AcoesDoProntuario

    var body: some View {
        let lista = Array(prontuario.checkins.dropFirst().prefix(12))
        if !lista.isEmpty {
            Bloco(titulo: "Check-ins anteriores", contagem: prontuario.sessoesDeTriagem.count - 1) {
                ForEach(Array(lista.enumerated()), id: \.element.sessao.id) { i, item in
                    let condutas = registro.intervencoes(daSessao: item.sessao.id)
                    LinhaDeBloco(ultima: i == lista.count - 1) {
                        HStack(alignment: .center, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(Formato.diaCurto(item.sessao.iniciadaEm))
                                    .font(Tipo.coluna)
                                    .foregroundStyle(Cor.textoSuave)
                                    .frame(width: 48, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    if let r = item.classificacao?.resultado {
                                        Text(r.situacao.nome).font(Tipo.apoioForte).foregroundStyle(Faixa.tons(r.situacao).tinta)
                                        let sintomas = (item.classificacao?.explicacao.porSintoma ?? [])
                                            .filter { $0.classificacao != .verde }.map(\.sintoma.nome)
                                        if !sintomas.isEmpty {
                                            Text(sintomas.joined(separator: ", ")).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                                        }
                                    } else {
                                        Text(item.sessao.estado == "ABANDONADA" ? "Não terminou" : "Não classificado")
                                            .font(Tipo.apoioForte).foregroundStyle(Cor.textoSuave)
                                    }
                                    if let ultima = condutas.first {
                                        Text(resumoDasCondutas(condutas.count, ultima: ultima.situacao))
                                            .font(Tipo.apoio)
                                            .foregroundStyle(Cor.textoFraco)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                            Spacer()
                            if acoes.permissoes.intervir {
                                Button {
                                    Tato.selecao()
                                    acoes.abrir(.intervencao(sessaoId: item.sessao.id, iniciadaEm: item.sessao.iniciadaEm))
                                } label: {
                                    Image(systemName: "plus.bubble")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Cor.azulProfundo)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(Cor.azulGelo.opacity(0.35)))
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.pressionavel)
                                .accessibilityLabel("Registrar intervenção no check-in de \(Formato.dia(item.sessao.iniciadaEm))")
                            }
                        }
                    }
                }
            }
        }
    }

    private func resumoDasCondutas(_ n: Int, ultima: DesfechoDaIntervencao) -> String {
        n == 1 ? "1 conduta · \(ultima.nome)" : "\(n) condutas · última: \(ultima.nome)"
    }
}

// MARK: - Agenda

private struct Agenda: View {
    let eventos: [Prontuario.Evento]

    var body: some View {
        let proximos = eventos.filter { $0.aconteceEm >= .now }.sorted { $0.aconteceEm < $1.aconteceEm }
        let ultimo = eventos.filter { $0.aconteceEm < .now }.max { $0.aconteceEm < $1.aconteceEm }
        let lista = proximos.prefix(3) + (ultimo.map { [$0] } ?? [])

        if !lista.isEmpty {
            Bloco(titulo: "Agenda") {
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, e in
                    LinhaDeBloco(ultima: i == lista.count - 1) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.aconteceEm < .now ? "Última visita" : "Próxima").estiloDeRotulo()
                                Text(e.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                                if let local = e.local { Text(local).font(Tipo.apoio).foregroundStyle(Cor.textoSuave) }
                            }
                            Spacer()
                            Text(Formato.dia(e.aconteceEm) + " · " + Formato.hora(e.aconteceEm))
                                .font(Tipo.apoio)
                                .monospacedDigit()
                                .foregroundStyle(Cor.textoSuave)
                        }
                    }
                }
            }
        }
    }
}
