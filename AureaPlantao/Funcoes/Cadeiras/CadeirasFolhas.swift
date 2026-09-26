import SwiftUI

// MARK: - Nova cadeira

/// Cadastrar poltrona. A API faz upsert pelo número: mandar um número que já existe
/// reativa a cadeira e SUBSTITUI a observação dela. A folha avisa antes, em vez de deixar
/// a enfermeira apagar sem saber a nota de outra pessoa.
struct FolhaNovaCadeira: View {
    let store: CadeirasStore
    let concluir: (String) -> Void

    @State private var numero = 1
    @State private var observacao = ""
    @State private var enviando = false
    @State private var erro: String?
    @State private var preparado = false

    private var existente: CadeiraDoGiro? {
        store.carga.valor?.giro.porCadeira.first { $0.cadeira.numero == numero }?.cadeira
    }

    var body: some View {
        FolhaDeFormulario(rotulo: "Capacidade", titulo: "Nova cadeira", acao: existente == nil ? "Cadastrar cadeira" : "Atualizar cadeira \(numero)",
                          icone: "chair.lounge", enviando: enviando, erro: erro) {
            Task { await enviar() }
        } campos: {
            Text("A poltrona entra no giro na hora e passa a contar na taxa de ocupação e nas janelas livres.")
                .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)

            CampoNumerico(rotulo: "Número da cadeira", valor: $numero, faixa: 1...999)

            if let existente {
                Label {
                    Text(existente.observacao.map { "A cadeira \(numero) já existe, com a observação “\($0)”. Salvar substitui essa observação pela de baixo." }
                         ?? "A cadeira \(numero) já existe. Salvar só grava a observação de baixo.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(Tipo.apoio)
                .foregroundStyle(Cor.texto)
                .padding(Espaco.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficie(.afundado, raio: Raio.controle)
                .transition(.opacity)
            }

            CampoDeTextoLongo(rotulo: "Observação (opcional)", texto: $observacao,
                              dica: "Ex.: reclinável, perto da janela, sem tomada", linhas: 2)
            Text("\(observacao.count) de 180")
                .font(Tipo.apoio).monospacedDigit()
                .foregroundStyle(observacao.count > 180 ? Cor.texto : Cor.textoFraco)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(Movimento.interface, value: existente?.id)
        .onAppear {
            guard !preparado else { return }
            preparado = true
            // Sugere o próximo número livre: é quase sempre o que se quer cadastrar.
            numero = min(999, (store.carga.valor?.giro.porCadeira.map(\.cadeira.numero).max() ?? 0) + 1)
        }
    }

    private func enviar() async {
        guard observacao.count <= 180 else {
            Tato.erro()
            erro = "A observação passa de 180 caracteres. Encurte para caber."
            return
        }
        enviando = true
        erro = nil
        let resultado = await store.cadastrarCadeira(numero: numero, observacao: observacao)
        enviando = false
        switch resultado {
        case .feito(let m): concluir(m)
        case .falhou(let m): Tato.erro(); erro = m
        }
    }
}

// MARK: - Agendar sessão

/// Agenda a sessão com a previsão de fim CALCULADA, nunca digitada: se desse para mandar
/// o fim, a agenda voltaria a ser a convencional com outro nome. Por isso a folha mostra,
/// ao escolher o paciente, a composição da ocupação que a API vai usar.
struct FolhaAgendarSessao: View {
    let store: CadeirasStore
    let cadeiraInicial: String?
    let inicioSugerido: Date?
    let concluir: (String) -> Void

    @State private var pacienteId: String?
    @State private var cadeiraId: String?
    @State private var inicio = Date.now
    @State private var previsao: PrevisaoDeOcupacao?
    @State private var erroDaPrevisao: String?
    @State private var carregandoPrevisao = false
    @State private var enviando = false
    @State private var erro: String?
    @State private var preparado = false

    /// Sem cadeira é escolha válida (a API aceita): a sessão entra na agenda e a poltrona
    /// é decidida na chegada. O Menu nativo precisa de um valor, então "sem" é o texto vazio.
    private static let semCadeira = ""

    private var painel: PainelDeCadeiras? { store.carga.valor }

    private var opcoesDePaciente: [(valor: String, nome: String)] {
        (store.pacientes ?? []).map { p in
            (p.id, p.protocolo.map { "\(p.nome) · \($0)" } ?? p.nome)
        }
    }

    private var opcoesDeCadeira: [(valor: String, nome: String)] {
        [(Self.semCadeira, "Sem cadeira por enquanto")] + (painel?.giro.porCadeira ?? []).map { o in
            let estado = o.estado.ocupa ? " · \(o.estado.nome.lowercased())\(o.livreEm.map { " até \(Formato.hora($0))" } ?? "")" : " · livre"
            return (o.cadeira.id, "Cadeira \(o.cadeira.numero)\(estado)")
        }
    }

    private var expediente: ClosedRange<Date>? {
        guard let e = painel?.expediente, e.abertura < e.fechamento else { return nil }
        return e.abertura...e.fechamento
    }

    private var fimPrevisto: Date? {
        previsao.map { inicio.addingTimeInterval(Double($0.ocupacao.total) * 60) }
    }

    private var conflitos: [SessaoDeCadeira] {
        guard let cadeiraId, !cadeiraId.isEmpty, let fimPrevisto else { return [] }
        return store.conflitos(cadeiraId: cadeiraId, de: inicio, ate: fimPrevisto)
    }

    var body: some View {
        FolhaDeFormulario(rotulo: "Agenda de hoje", titulo: "Agendar sessão", acao: "Agendar",
                          icone: "calendar.badge.plus", enviando: enviando, erro: erro) {
            Task { await enviar() }
        } campos: {
            if store.pacientes == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Esqueleto(largura: 80, altura: 10)
                    Esqueleto(altura: 52)
                }
            } else if opcoesDePaciente.isEmpty {
                Text("Nenhum paciente com tratamento ativo. Sem protocolo, não há ocupação a prever.")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
            } else {
                CampoDeEscolha(rotulo: "Paciente", opcoes: opcoesDePaciente, selecionado: $pacienteId, dica: "Escolher paciente")
            }

            CampoDeEscolha(rotulo: "Cadeira", opcoes: opcoesDeCadeira, selecionado: $cadeiraId)

            if let expediente {
                CampoDeData(rotulo: "Início previsto", data: $inicio, comHora: true, intervalo: expediente)
                Text("O painel lê só o expediente de hoje (\(Formato.hora(expediente.lowerBound)) às \(Formato.hora(expediente.upperBound))).")
                    .font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if carregandoPrevisao {
                VStack(alignment: .leading, spacing: 10) {
                    Esqueleto(largura: 140, altura: 10)
                    Esqueleto(altura: 14)
                    Esqueleto(largura: 200, altura: 10)
                }
                .padding(Espaco.l)
                .superficie(raio: Raio.linha)
            } else if let previsao, let fimPrevisto {
                CartaoDePrevisao(previsao: previsao, inicio: inicio, fim: fimPrevisto)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                avisos(fim: fimPrevisto)
            } else if let erroDaPrevisao {
                Label(erroDaPrevisao, systemImage: "exclamationmark.circle")
                    .font(Tipo.apoio).foregroundStyle(Cor.texto)
            }
        }
        .animation(Movimento.interface, value: previsao)
        .animation(Movimento.interface, value: conflitos.map(\.id))
        .task { await store.carregarPacientes() }
        .onAppear(perform: preparar)
        .onChange(of: pacienteId) { _, novo in
            Task { await buscarPrevisao(novo) }
        }
    }

    @ViewBuilder
    private func avisos(fim: Date) -> some View {
        if let e = painel?.expediente, fim > e.fechamento {
            AvisoDaFolha(icone: "clock.badge.exclamationmark",
                         texto: "A cadeira fica presa até \(Formato.hora(fim)), depois do fim do expediente (\(Formato.hora(e.fechamento))).")
        }
        ForEach(conflitos) { c in
            AvisoDaFolha(icone: "exclamationmark.triangle",
                         texto: "Conflita com \(c.paciente) nesta cadeira (\(Formato.hora(c.previsaoDeInicio)) às \(Formato.hora(c.previsaoDeFim))). A API aceita as duas; quem decide é a coordenação.")
        }
    }

    private func preparar() {
        guard !preparado else { return }
        preparado = true
        cadeiraId = cadeiraInicial ?? Self.semCadeira
        // Próximos cinco minutos redondos, dentro do expediente.
        let base = inicioSugerido ?? .now
        let arredondado = Date(timeIntervalSince1970: (base.timeIntervalSince1970 / 300).rounded(.up) * 300)
        if let expediente {
            inicio = min(max(arredondado, expediente.lowerBound), expediente.upperBound)
        } else {
            inicio = arredondado
        }
    }

    private func buscarPrevisao(_ id: String?) async {
        guard let id else { return }
        carregandoPrevisao = true
        erroDaPrevisao = nil
        do {
            let p = try await store.previsao(de: id)
            guard pacienteId == id else { return }
            previsao = p
        } catch {
            guard pacienteId == id else { return }
            previsao = nil
            erroDaPrevisao = MensagemDoGiro.de(ErroDaAPI(error), contexto: "Não há previsão para este paciente: ele pode estar sem tratamento ativo.")
        }
        carregandoPrevisao = false
    }

    private func enviar() async {
        guard let pacienteId else {
            Tato.erro()
            erro = "Escolha o paciente. A duração sai do protocolo dele."
            return
        }
        enviando = true
        erro = nil
        let cadeira = (cadeiraId?.isEmpty ?? true) ? nil : cadeiraId
        let resultado = await store.agendar(pacienteId: pacienteId, cadeiraId: cadeira, inicio: inicio)
        enviando = false
        switch resultado {
        case .feito(let m): concluir(m)
        case .falhou(let m): Tato.erro(); erro = m
        }
    }
}

private struct AvisoDaFolha: View {
    let icone: String
    let texto: String

    var body: some View {
        Label {
            Text(texto).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icone)
        }
        .font(Tipo.apoio)
        .foregroundStyle(Cor.texto)
        .padding(Espaco.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(.afundado, raio: Raio.controle)
        .transition(.opacity)
    }
}

// MARK: - Previsão (composição da ocupação)

/// A composição da ocupação: o argumento inteiro do giro num cartão. A barra mostra que a
/// infusão é só uma parte do tempo em que a poltrona fica presa.
struct CartaoDePrevisao: View {
    let previsao: PrevisaoDeOcupacao
    let inicio: Date
    let fim: Date

    private var etapas: [(nome: String, minutos: Int, tons: TonsDoGiro)] {
        let o = previsao.ocupacao
        return [
            ("Preparo", o.preparo, .vinhoRosa),
            ("Pré-medicação", o.preMedicacao, .ameixa),
            ("Infusão", o.infusao, .acoAzul),
            ("Observação", o.observacao, .indigo),
            ("Virada da poltrona", o.virada, .neutro),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cadeira presa").estiloDeRotulo()
                Spacer()
                Text(previsao.protocolo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(FormatoDoGiro.duracao(previsao.ocupacao.total))
                    .font(.custom("Plus Jakarta Sans", size: 30, relativeTo: .title).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Cor.texto)
                Text("\(Formato.hora(inicio)) às \(Formato.hora(fim))")
                    .font(Tipo.coluna)
                    .foregroundStyle(Cor.textoSuave)
            }

            GeometryReader { geo in
                let total = max(1, CGFloat(previsao.ocupacao.total))
                let visiveis = etapas.filter { $0.minutos > 0 }
                let folga = CGFloat(max(0, visiveis.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(visiveis, id: \.nome) { etapa in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(etapa.tons.tinta)
                            .frame(width: max(3, (geo.size.width - folga) * CGFloat(etapa.minutos) / total))
                    }
                }
            }
            .frame(height: 12)

            VStack(spacing: 6) {
                ForEach(etapas, id: \.nome) { etapa in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(etapa.tons.tinta).frame(width: 10, height: 10)
                        Text(etapa.nome).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        Spacer()
                        Text(FormatoDoGiro.duracao(etapa.minutos))
                            .font(Tipo.apoioForte).monospacedDigit().foregroundStyle(Cor.texto)
                    }
                    .opacity(etapa.minutos == 0 ? 0.5 : 1)
                }
            }

            Divider().overlay(Cor.filete)

            Text(previsao.complexidade.regra)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.texto)
                .fixedSize(horizontal: false, vertical: true)
            Text("A complexidade sai da mesma estratificação de risco do painel de pacientes.")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoFraco)
                .fixedSize(horizontal: false, vertical: true)
            AvisoNaoValidado()
        }
        .padding(Espaco.l)
        .superficie(raio: Raio.linha)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rotuloFalado)
    }

    private var rotuloFalado: String {
        let partes = etapas.map { "\($0.nome) \(FormatoDoGiro.duracaoFalada($0.minutos))" }.joined(separator: ", ")
        return "Cadeira presa por \(FormatoDoGiro.duracaoFalada(previsao.ocupacao.total)), das \(Formato.hora(inicio)) às \(Formato.hora(fim)). \(partes). \(previsao.complexidade.regra) Regras não validadas clinicamente."
    }
}

// MARK: - Sessão

/// A sessão aberta: o que foi previsto, o que já aconteceu (carimbado pelo servidor) e o
/// próximo passo, grande, embaixo. É o que faz o painel andar em tempo real.
struct FolhaDaSessao: View {
    let store: CadeirasStore
    let sessaoId: String
    let concluir: (String) -> Void

    @State private var cadeiraEscolhida: String?
    @State private var enviando = false
    @State private var erro: String?
    @State private var confirmarCancelamento = false
    @State private var confirmarEncerramento = false
    @State private var previsao: PrevisaoDeOcupacao?
    @Environment(\.dismiss) private var fechar

    private var sessao: SessaoDeCadeira? {
        store.carga.valor?.sessoesDoDia.first { $0.id == sessaoId }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Fechar") { fechar() }
                    .font(Tipo.apoioForte)
                    .foregroundStyle(Cor.textoSuave)
                    .frame(minHeight: 44)
                Spacer()
            }
            .padding(.horizontal, Espaco.xl)
            .padding(.top, Espaco.s)

            if let sessao {
                ScrollView {
                    conteudo(sessao)
                        .padding(Espaco.xl)
                }
                .scrollIndicators(.hidden)
                acoes(sessao)
            } else {
                EstadoVazio(titulo: "Esta sessão saiu do painel.",
                            texto: "Ela pode ter sido remarcada para outro dia. Feche e puxe a tela para atualizar.",
                            icone: "calendar.badge.exclamationmark")
                Spacer()
            }
        }
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
        .task(id: sessao?.pacienteId) {
            guard let id = sessao?.pacienteId else { return }
            previsao = try? await store.previsao(de: id)
        }
        .onAppear { cadeiraEscolhida = sessao?.cadeiraId }
        .confirmationDialog("Cancelar esta sessão?", isPresented: $confirmarCancelamento, titleVisibility: .visible) {
            Button("Cancelar sessão", role: .destructive) { mudar(para: .cancelada) }
            Button("Manter", role: .cancel) {}
        } message: {
            Text("Ela sai da linha do tempo e a janela volta a contar como livre.")
        }
        .confirmationDialog("Encerrar a sessão agora?", isPresented: $confirmarEncerramento, titleVisibility: .visible) {
            Button("Encerrar e liberar a cadeira") { mudar(para: .concluida) }
            Button("Voltar", role: .cancel) {}
        } message: {
            Text("O fim real fica registrado agora, pelo servidor, e entra no tempo médio de ocupação.")
        }
    }

    @ViewBuilder
    private func conteudo(_ s: SessaoDeCadeira) -> some View {
        let ocupacao = store.ocupacao(da: s.cadeiraId)
        VStack(alignment: .leading, spacing: Espaco.xl) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ocupacao.map { "Cadeira \($0.cadeira.numero)" } ?? "Sem cadeira").estiloDeRotulo()
                Text(s.paciente).font(Tipo.titulo).foregroundStyle(Cor.texto)
                HStack(spacing: 8) {
                    SeloDaSessao(estado: s.estado)
                    if let p = s.protocolo {
                        Text(p).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).lineLimit(1)
                    }
                }
            }

            TimelineView(.everyMinute) { ctx in
                MarcosDaSessao(sessao: s, agora: ctx.date)
            }

            if s.estado == .agendada || s.cadeiraId == nil, !s.estado.encerrada {
                escolhaDeCadeira(s)
            }

            if let previsao {
                CartaoDePrevisao(previsao: previsao, inicio: s.previsaoDeInicio, fim: s.previsaoDeFim)
            }

            if let erro {
                Label(erro, systemImage: "exclamationmark.circle")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.texto)
                    .padding(Espaco.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficie(.afundado, raio: Raio.controle)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Movimento.interface, value: erro)
        .animation(Movimento.interface, value: s.estado)
    }

    private func escolhaDeCadeira(_ s: SessaoDeCadeira) -> some View {
        let opcoes: [(valor: String, nome: String)] = (store.carga.valor?.giro.porCadeira ?? []).map { o in
            let comOutro = o.sessaoAtual.map { $0.id != s.id } ?? false
            return (o.cadeira.id, "Cadeira \(o.cadeira.numero)\(comOutro ? " · com \(o.sessaoAtual?.paciente ?? "outro paciente")" : " · livre")")
        }
        return CampoDeEscolha(rotulo: s.cadeiraId == nil ? "Onde vai sentar" : "Cadeira", opcoes: opcoes,
                              selecionado: $cadeiraEscolhida, dica: "Escolher cadeira")
    }

    @ViewBuilder
    private func acoes(_ s: SessaoDeCadeira) -> some View {
        if let proximo = s.estado.proximo {
            VStack(spacing: Espaco.s) {
                BotaoPrimario(titulo: proximo.acao, icone: proximo.icone, carregando: enviando) {
                    if proximo.estado == .concluida { confirmarEncerramento = true } else { mudar(para: proximo.estado) }
                }

                HStack(spacing: Espaco.s) {
                    if s.estado.ocupaCadeira && s.estado != .emObservacao {
                        acaoSecundaria("Encerrar agora", icone: "stop.circle") { confirmarEncerramento = true }
                    }
                    if s.estado == .agendada || s.estado == .aguardandoMedicacao {
                        acaoSecundaria("Cancelar sessão", icone: "xmark.circle") { confirmarCancelamento = true }
                    }
                }
            }
            .padding(.horizontal, Espaco.xl)
            .padding(.bottom, Espaco.l)
            .disabled(enviando)
        }
    }

    private func acaoSecundaria(_ titulo: String, icone: String, _ acao: @escaping () -> Void) -> some View {
        Button {
            Tato.selecao()
            acao()
        } label: {
            Label(titulo, systemImage: icone)
                .font(Tipo.apoioForte)
                .foregroundStyle(Cor.texto)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Cor.superficie))
                .overlay(Capsule().strokeBorder(Cor.fileteForte, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressionavel)
    }

    private func mudar(para estado: EstadoDaSessao) {
        guard let s = sessao else { return }
        let cadeira = (cadeiraEscolhida?.isEmpty ?? true) ? nil : cadeiraEscolhida

        // Sessão que passa a ocupar poltrona precisa de uma — e de uma que não esteja com
        // outra pessoa. A API não impede nenhuma das duas coisas; quem impede é a tela.
        if estado.ocupaCadeira {
            guard let cadeira else {
                Tato.erro()
                erro = "Escolha a cadeira antes: sem ela, o paciente não aparece no giro."
                return
            }
            if let outra = store.ocupacao(da: cadeira)?.sessaoAtual, outra.id != s.id {
                Tato.aviso()
                erro = "A cadeira \(store.ocupacao(da: cadeira)?.cadeira.numero ?? 0) está com \(outra.paciente). Encerre aquela sessão ou escolha outra poltrona."
                return
            }
        }

        Task {
            enviando = true
            erro = nil
            let mudouCadeira = cadeira != s.cadeiraId ? cadeira : nil
            let resultado = await store.mudar(s, para: estado, cadeiraId: mudouCadeira)
            enviando = false
            switch resultado {
            case .feito(let m): concluir(m)
            case .falhou(let m): Tato.erro(); erro = m
            }
        }
    }
}

/// Previsto × real, lado a lado. Início e fim reais são do servidor; o atraso aparece
/// medido, nunca estimado.
private struct MarcosDaSessao: View {
    let sessao: SessaoDeCadeira
    let agora: Date

    var body: some View {
        VStack(spacing: 0) {
            marco("Previsto", valor: "\(Formato.hora(sessao.previsaoDeInicio)) às \(Formato.hora(sessao.previsaoDeFim))",
                  apoio: FormatoDoGiro.duracao(FormatoDoGiro.minutos(de: sessao.previsaoDeInicio, ate: sessao.previsaoDeFim)))
            Divider().overlay(Cor.filete)
            marco("Início real", valor: sessao.inicioReal.map(Formato.hora) ?? "—", apoio: atraso)
            if let liberada = sessao.medicacaoLiberadaEm {
                Divider().overlay(Cor.filete)
                marco("Medicação liberada", valor: Formato.hora(liberada), apoio: nil)
            }
            Divider().overlay(Cor.filete)
            marco(sessao.fimReal == nil ? "Na cadeira" : "Fim real",
                  valor: sessao.fimReal.map(Formato.hora) ?? decorrido,
                  apoio: sessao.fimReal.flatMap { fim in sessao.inicioReal.map { "ocupou \(FormatoDoGiro.duracao(FormatoDoGiro.minutos(de: $0, ate: fim)))" } })
        }
        .padding(.horizontal, Espaco.l)
        .superficie(raio: Raio.linha)
    }

    private var atraso: String? {
        guard let real = sessao.inicioReal else {
            return sessao.estado == .agendada && agora > sessao.previsaoDeInicio
                ? "previsto há \(FormatoDoGiro.duracao(FormatoDoGiro.minutos(de: sessao.previsaoDeInicio, ate: agora)))" : nil
        }
        let m = FormatoDoGiro.minutos(de: sessao.previsaoDeInicio, ate: real)
        return m > 0 ? "\(FormatoDoGiro.duracao(m)) de atraso" : "no horário"
    }

    private var decorrido: String {
        guard let real = sessao.inicioReal, !sessao.estado.encerrada else { return "—" }
        return FormatoDoGiro.duracao(FormatoDoGiro.minutos(de: real, ate: agora))
    }

    private func marco(_ rotulo: String, valor: String, apoio: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(rotulo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(valor).font(Tipo.corpoForte).monospacedDigit().foregroundStyle(Cor.texto)
                    .contentTransition(.numericText())
                if let apoio {
                    Text(apoio).font(Tipo.apoio).monospacedDigit().foregroundStyle(Cor.textoFraco)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
