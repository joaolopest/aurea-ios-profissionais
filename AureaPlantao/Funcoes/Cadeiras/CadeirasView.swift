import SwiftUI

/// Giro de cadeiras — capacidade assistencial real.
///
/// Responde o que a agenda convencional não responde: quantas poltronas estão de fato
/// livres agora, quando a próxima se libera e quanto o dia já atrasou. É aberta em pé, no
/// corredor, por quem está de plantão — por isso é um painel VIVO: os tempos correm na
/// tela a cada minuto e o retrato se refaz sozinho.
///
/// A cor aqui não é a escala clínica. Estado de poltrona não é gravidade de paciente:
/// os estados usam a paleta de dado do ADR-005 (`TonsDoGiro`), e cadeira livre é cinza de
/// estrutura, não verde.
struct CadeirasView: View {
    @State private var store: CadeirasStore
    @State private var folha: FolhaDoGiro?
    @State private var aviso: String?

    /// `nonisolated` porque o `telaSecundaria(_:)` do "Mais" monta a tela fora do MainActor;
    /// valor padrão em propriedade herdaria o isolamento da View (SE-0411) e viraria aviso.
    nonisolated init() {
        _store = State(initialValue: CadeirasStore())
    }

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Plantão",
                titulo: "Giro de cadeiras",
                contexto: "Capacidade real, não horário livre. A poltrona fica presa do preparo à liberação, e é isso que a agenda convencional não enxerga."
            )

            if let erro = store.carga.erro {
                // O `CartaoDeErro` do sistema mostra `erro.mensagem` cru; aqui a recusa (403)
                // precisa virar "seu acesso não inclui…", então a mensagem passa pelo giro.
                CartaoDeErro(erro: .recusado(MensagemDoGiro.de(erro, contexto: "Não foi possível carregar o giro de cadeiras. Puxe para tentar de novo."))) {
                    Task { await store.carregar() }
                }
                .encerraSessaoNo401(erro)
            }

            if let painel = store.carga.valor {
                conteudo(painel)
            } else if store.carga.erro == nil {
                EsqueletoDoGiro()
            }
        }
        .task { await store.carregar() }
        .task { await store.manterAoVivo() }
        .avisoTemporario($aviso)
        .sheet(item: $folha) { destino in
            Group {
                switch destino {
                case .novaCadeira:
                    FolhaNovaCadeira(store: store) { concluir($0) }
                case .agendar(let cadeiraId, let inicio):
                    FolhaAgendarSessao(store: store, cadeiraInicial: cadeiraId, inicioSugerido: inicio) { concluir($0) }
                case .sessao(let id):
                    FolhaDaSessao(store: store, sessaoId: id) { concluir($0) }
                }
            }
            .presentationDetents([.large])
        }
    }

    private func concluir(_ mensagem: String) {
        folha = nil
        Tato.sucesso()
        aviso = mensagem
    }

    @ViewBuilder
    private func conteudo(_ painel: PainelDeCadeiras) -> some View {
        let giro = painel.giro

        PainelDeOcupacao(giro: giro, atualizadoEm: store.atualizadoEm)
            .entradaEscalonada(0)

        IndicadoresDoGiro(giro: giro)
            .entradaEscalonada(1)

        // As cadeiras agora
        HStack(alignment: .center) {
            CabecalhoDeSecao(titulo: "As cadeiras agora", contagem: giro.total)
            BotaoDeAcaoEmLinha(titulo: "Cadeira") { folha = .novaCadeira }
                .accessibilityLabel("Cadastrar cadeira")
        }
        .padding(.top, Espaco.s)

        if giro.porCadeira.isEmpty {
            EstadoVazio(titulo: "Nenhuma cadeira cadastrada.",
                        texto: "Sem cadeiras, não há capacidade a calcular. Cadastre a primeira poltrona do ambulatório.",
                        icone: "chair.lounge")
                .superficie()
        } else {
            GradeDeCadeiras(ocupacoes: giro.porCadeira) { ocupacao in
                Tato.selecao()
                if let sessao = ocupacao.sessaoAtual {
                    folha = .sessao(sessao.id)
                } else {
                    folha = .agendar(cadeiraId: ocupacao.cadeira.id, inicio: nil)
                }
            }
        }

        // Linha do tempo
        if !giro.porCadeira.isEmpty {
            CabecalhoDeSecao(titulo: "Ocupação prevista do dia")
                .padding(.top, Espaco.s)
            LinhaDoTempoDoGiro(painel: painel) { sessao in
                Tato.selecao()
                folha = .sessao(sessao.id)
            }
        }

        // Agenda de hoje
        HStack(alignment: .center) {
            CabecalhoDeSecao(titulo: "Sessões de hoje", contagem: painel.sessoesDoDia.filter { $0.estado != .cancelada }.count)
            BotaoDeAcaoEmLinha(titulo: "Agendar") { folha = .agendar(cadeiraId: nil, inicio: nil) }
                .accessibilityLabel("Agendar sessão")
        }
        .padding(.top, Espaco.s)
        AgendaDoDia(painel: painel) { sessao in
            Tato.selecao()
            folha = .sessao(sessao.id)
        }

        // Ainda cabe alguém
        CabecalhoDeSecao(titulo: "Ainda cabe alguém")
            .padding(.top, Espaco.s)
        JanelasLivres(painel: painel) { janela in
            Tato.selecao()
            folha = .agendar(cadeiraId: janela.cadeiraId, inicio: max(janela.de, .now))
        }
    }
}

/// O que a folha mostra. Guarda só o id da sessão: a folha lê o painel vivo do store,
/// e o estado que ela mostra é sempre o que a API acabou de devolver.
enum FolhaDoGiro: Identifiable, Hashable {
    case novaCadeira
    case agendar(cadeiraId: String?, inicio: Date?)
    case sessao(String)

    var id: String {
        switch self {
        case .novaCadeira: "nova"
        case .agendar(let c, let i): "agendar-\(c ?? "")-\(i?.timeIntervalSince1970 ?? 0)"
        case .sessao(let id): "sessao-\(id)"
        }
    }
}

// MARK: - Painel de ocupação (o herói)

/// O número que a coordenação fala em voz alta, com a composição da sala embaixo: uma
/// pastilha por poltrona, na cor do estado. Dez cadeiras viram dez pastilhas — o olho
/// conta sem ler.
private struct PainelDeOcupacao: View {
    let giro: GiroDasCadeiras
    let atualizadoEm: Date?
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    private var presas: Int { giro.total - giro.disponiveis }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Taxa de ocupação").estiloDeRotulo()
                Spacer()
                SinalAoVivo(atualizadoEm: atualizadoEm)
            }

            HStack(alignment: .firstTextBaseline, spacing: Espaco.m) {
                Text("\(giro.taxaDeOcupacao)%")
                    .font(Tipo.heroi)
                    .monospacedDigit()
                    .foregroundStyle(Cor.azulProfundo)
                    .contentTransition(.numericText(value: Double(giro.taxaDeOcupacao)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(presas) de \(giro.total)")
                        .font(Tipo.destaque).monospacedDigit().foregroundStyle(Cor.texto)
                    Text(giro.total == 1 ? "cadeira presa" : "cadeiras presas")
                        .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
            }

            PastilhasDaSala(ocupacoes: giro.porCadeira)

            LegendaDosEstados(giro: giro)
        }
        .padding(Espaco.xl)
        .cartaoDestaque(tom: Cor.auroraAco)
        .animation(reduzirMovimento ? nil : Movimento.interface, value: giro.taxaDeOcupacao)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloFalado)
    }

    private var rotuloFalado: String {
        let partes = EstadoDaCadeira.ordem.map { "\(giro.quantas($0)) \($0.nome.lowercased())" }
        return "Taxa de ocupação \(giro.taxaDeOcupacao) por cento. \(presas) de \(giro.total) cadeiras presas. " + partes.joined(separator: ", ") + "."
    }
}

/// "Ao vivo · há 20 s". O ponto pulsa em azul — pulsar em verde diria "tudo bem", e
/// quem diz isso aqui é a faixa clínica.
private struct SinalAoVivo: View {
    let atualizadoEm: Date?
    @State private var pulso = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { ctx in
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(Cor.auroraAco.opacity(0.35))
                        .frame(width: 14, height: 14)
                        .scaleEffect(pulso ? 1 : 0.4)
                        .opacity(pulso ? 0 : 1)
                    Circle().fill(Cor.azulProfundo).frame(width: 6, height: 6)
                }
                Text(texto(agora: ctx.date))
                    .font(Tipo.rotulo).tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(Cor.textoSuave)
            }
        }
        .onAppear {
            guard !reduzirMovimento else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulso = true }
        }
    }

    private func texto(agora: Date) -> String {
        guard let atualizadoEm else { return "AO VIVO" }
        let s = Int(max(0, agora.timeIntervalSince(atualizadoEm)))
        return s < 15 ? "AO VIVO · AGORA" : s < 60 ? "AO VIVO · HÁ \(s / 10 * 10) S" : "AO VIVO · HÁ \(s / 60) MIN"
    }
}

private struct PastilhasDaSala: View {
    let ocupacoes: [OcupacaoDeCadeira]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ordenadas) { o in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(o.estado.ocupa ? o.estado.tons.tinta : Cor.fundoBaixo)
                    .overlay {
                        if !o.estado.ocupa {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Cor.fileteForte, lineWidth: 1)
                        }
                    }
                    .frame(height: 22)
                    .frame(maxWidth: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Movimento.interface, value: ocupacoes.map(\.estado))
        .accessibilityHidden(true)
    }

    /// Presas primeiro, na ordem do fluxo, livres no fim: a barra lê como proporção.
    private var ordenadas: [OcupacaoDeCadeira] {
        let ordem = EstadoDaCadeira.ordem
        return ocupacoes.sorted {
            (ordem.firstIndex(of: $0.estado) ?? 99, $0.cadeira.numero) < (ordem.firstIndex(of: $1.estado) ?? 99, $1.cadeira.numero)
        }
    }
}

private struct LegendaDosEstados: View {
    let giro: GiroDasCadeiras

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 10) {
            ForEach(EstadoDaCadeira.ordem, id: \.self) { estado in
                let n = giro.quantas(estado)
                HStack(spacing: 8) {
                    PontoDoEstado(estado: estado)
                    Text("\(n)")
                        .font(Tipo.corpoForte).monospacedDigit()
                        .foregroundStyle(Cor.texto)
                        .contentTransition(.numericText(value: Double(n)))
                    Text(estado.nome)
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(n == 0 ? 0.55 : 1)
            }
        }
    }
}

/// Ponto de estado. Livre é anel, não disco: a diferença sobrevive a daltonismo e a
/// tela suja de corredor.
struct PontoDoEstado: View {
    let estado: EstadoDaCadeira
    var tamanho: CGFloat = 10

    var body: some View {
        Group {
            if estado.ocupa {
                Circle().fill(estado.tons.tinta)
            } else {
                Circle().strokeBorder(Cor.textoFraco, lineWidth: 1.5)
            }
        }
        .frame(width: tamanho, height: tamanho)
        .accessibilityHidden(true)
    }
}

// MARK: - Indicadores

private struct IndicadoresDoGiro: View {
    let giro: GiroDasCadeiras

    var body: some View {
        VStack(spacing: Espaco.m) {
            HStack(spacing: Espaco.m) {
                CartaoDeIndicador(
                    rotulo: "Tempo médio",
                    valor: FormatoDoGiro.duracao(giro.tempoMedioDeOcupacaoEmMinutos),
                    apoio: "sessões encerradas hoje"
                )
                .accessibilityLabel("Tempo médio de ocupação: \(FormatoDoGiro.duracaoFalada(giro.tempoMedioDeOcupacaoEmMinutos)), sessões encerradas hoje")
                CartaoDeIndicador(
                    rotulo: "Próxima livre",
                    valor: giro.disponiveis > 0 ? "agora" : giro.proximaCadeiraLivreEm.map(Formato.hora) ?? "—",
                    apoio: giro.disponiveis > 0
                        ? "\(giro.disponiveis) \(giro.disponiveis > 1 ? "disponíveis" : "disponível")"
                        : "todas ocupadas"
                )
            }
            CartaoDeIndicador(
                rotulo: "Atraso acumulado",
                valor: FormatoDoGiro.duracao(giro.atrasoAcumuladoEmMinutos),
                apoio: "do previsto ao início real, só o que já aconteceu hoje"
            )
            .accessibilityLabel("Atraso acumulado: \(FormatoDoGiro.duracaoFalada(giro.atrasoAcumuladoEmMinutos)), do previsto ao início real")
        }
    }
}

// MARK: - Grade de cadeiras

private struct GradeDeCadeiras: View {
    let ocupacoes: [OcupacaoDeCadeira]
    let tocar: (OcupacaoDeCadeira) -> Void

    var body: some View {
        // Um relógio para a grade inteira: cada cartão recebe o mesmo "agora" e os tempos
        // correm juntos, em vez de dez relógios dessincronizados.
        TimelineView(.everyMinute) { ctx in
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Espaco.m), GridItem(.flexible(), spacing: Espaco.m)],
                      spacing: Espaco.m) {
                ForEach(Array(ocupacoes.enumerated()), id: \.element.id) { i, o in
                    Button { tocar(o) } label: {
                        CartaoDeCadeira(ocupacao: o, agora: ctx.date)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i + 2)
                }
            }
            .animation(Movimento.interface, value: ocupacoes.map(\.estado))
        }
    }
}

/// A poltrona como objeto: número, quem está nela, o estado e o tempo correndo.
/// A barra embaixo é o quanto da ocupação prevista já passou.
private struct CartaoDeCadeira: View {
    let ocupacao: OcupacaoDeCadeira
    let agora: Date

    private var estado: EstadoDaCadeira { ocupacao.estado }
    private var sessao: SessaoDeCadeira? { ocupacao.sessaoAtual }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("#\(ocupacao.cadeira.numero)")
                    .font(Tipo.colunaForte)
                    .foregroundStyle(Cor.textoFraco)
                Spacer()
                Image(systemName: estado.icone)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(estado.ocupa ? estado.tons.tinta : Cor.textoFraco)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(estado.ocupa ? estado.tons.fundo : Cor.fundo))
            }

            Spacer(minLength: Espaco.s)

            Text(sessao?.paciente ?? "Livre")
                .font(Tipo.corpoForte)
                .foregroundStyle(sessao == nil ? Cor.textoSuave : Cor.texto)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(linhaDeEstado)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .lineLimit(2)
                .padding(.top, 2)

            Spacer(minLength: Espaco.m)

            if let sessao {
                ProgressoDaSessao(sessao: sessao, estado: estado, agora: agora)
            } else {
                Text(ocupacao.cadeira.observacao ?? "Toque para agendar")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoFraco)
                    .lineLimit(1)
            }
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .superficie(estado.ocupa ? .erguido : .apoiado, raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloFalado)
        .accessibilityHint(sessao == nil ? "Abre o agendamento nesta cadeira" : "Abre a sessão")
        .accessibilityAddTraits(.isButton)
    }

    private var linhaDeEstado: String {
        if let livre = ocupacao.livreEm { return "\(estado.nome) até \(Formato.hora(livre))" }
        return estado.nome
    }

    private var rotuloFalado: String {
        var texto = "Cadeira \(ocupacao.cadeira.numero). "
        if let sessao {
            texto += "\(sessao.paciente). \(linhaDeEstado)."
            if let inicio = sessao.inicioReal {
                texto += " Na cadeira há \(FormatoDoGiro.duracaoFalada(FormatoDoGiro.minutos(de: inicio, ate: agora)))."
            }
            if let livre = ocupacao.livreEm, livre < agora {
                texto += " Passou \(FormatoDoGiro.duracaoFalada(FormatoDoGiro.minutos(de: livre, ate: agora))) da liberação prevista."
            }
        } else {
            texto += "Livre."
            if let obs = ocupacao.cadeira.observacao { texto += " \(obs)." }
        }
        return texto
    }
}

/// Barra fina + tempo correndo. Se a previsão já passou, a tela diz isso por extenso em
/// vez de travar a barra cheia em silêncio: a API não recalcula a liberação pelo início real.
private struct ProgressoDaSessao: View {
    let sessao: SessaoDeCadeira
    let estado: EstadoDaCadeira
    let agora: Date

    private var inicio: Date { sessao.inicioReal ?? sessao.previsaoDeInicio }
    private var fim: Date { sessao.previsaoDeFim }
    private var fracao: Double {
        let total = fim.timeIntervalSince(inicio)
        guard total > 0 else { return 1 }
        return min(1, max(0, agora.timeIntervalSince(inicio) / total))
    }
    private var passou: Bool { agora > fim }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(estado.tons.fundo)
                    Capsule().fill(estado.tons.tinta)
                        .frame(width: max(4, geo.size.width * fracao))
                }
            }
            .frame(height: 4)
            .animation(Movimento.interface, value: fracao)

            Text(rodape)
                .font(Tipo.apoio)
                .monospacedDigit()
                .foregroundStyle(passou ? Cor.texto : Cor.textoFraco)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
        }
    }

    private var rodape: String {
        if passou { return "+\(FormatoDoGiro.duracao(FormatoDoGiro.minutos(de: fim, ate: agora))) da previsão" }
        if let real = sessao.inicioReal { return "há \(FormatoDoGiro.duracao(FormatoDoGiro.minutos(de: real, ate: agora)))" }
        return "previsto \(Formato.hora(sessao.previsaoDeInicio))"
    }
}

// MARK: - Agenda do dia

private struct AgendaDoDia: View {
    let painel: PainelDeCadeiras
    let tocar: (SessaoDeCadeira) -> Void

    private var sessoes: [SessaoDeCadeira] {
        painel.sessoesDoDia.filter { $0.estado != .cancelada }.sorted { $0.previsaoDeInicio < $1.previsaoDeInicio }
    }

    private func numero(_ cadeiraId: String?) -> Int? {
        painel.giro.porCadeira.first { $0.cadeira.id == cadeiraId }?.cadeira.numero
    }

    var body: some View {
        if sessoes.isEmpty {
            EstadoVazio(titulo: "Nenhuma sessão hoje.",
                        texto: "Agende a primeira: a previsão de fim sai dos tempos do protocolo, não de quem digita.",
                        icone: "calendar")
                .superficie()
        } else {
            VStack(spacing: Espaco.s) {
                ForEach(Array(sessoes.enumerated()), id: \.element.id) { i, s in
                    Button { tocar(s) } label: {
                        LinhaDeSessao(sessao: s, numeroDaCadeira: numero(s.cadeiraId))
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
            .animation(Movimento.interface, value: sessoes.map(\.estado))
        }
    }
}

private struct LinhaDeSessao: View {
    let sessao: SessaoDeCadeira
    let numeroDaCadeira: Int?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formato.hora(sessao.previsaoDeInicio)).font(Tipo.colunaForte).foregroundStyle(Cor.texto)
                Text(Formato.hora(sessao.previsaoDeFim)).font(Tipo.coluna).foregroundStyle(Cor.textoFraco)
            }
            .frame(width: 48, alignment: .trailing)

            Rectangle().fill(Cor.filete).frame(width: 1, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(sessao.paciente)
                    .font(Tipo.corpoForte)
                    .foregroundStyle(sessao.estado == .concluida ? Cor.textoSuave : Cor.texto)
                    .lineLimit(1)
                Text(apoio).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).lineLimit(1)
            }
            Spacer(minLength: 8)
            SeloDaSessao(estado: sessao.estado)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sessao.paciente). Das \(Formato.hora(sessao.previsaoDeInicio)) às \(Formato.hora(sessao.previsaoDeFim)). \(apoio). \(sessao.estado.nome).")
        .accessibilityHint("Abre a sessão")
        .accessibilityAddTraits(.isButton)
    }

    private var apoio: String {
        let cadeira = numeroDaCadeira.map { "Cadeira \($0)" } ?? "Sem cadeira"
        guard let protocolo = sessao.protocolo else { return cadeira }
        return "\(cadeira) · \(protocolo)"
    }
}

/// Selo de estado da sessão: ponto + nome, fundo da paleta de dado. Nome sempre junto.
struct SeloDaSessao: View {
    let estado: EstadoDaSessao

    var body: some View {
        let cadeira = estado.estadoDaCadeira
        let tons: TonsDoGiro = cadeira.ocupa ? cadeira.tons : .neutro
        HStack(spacing: 5) {
            if cadeira.ocupa {
                Circle().fill(tons.tinta).frame(width: 6, height: 6)
            } else if estado == .concluida {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            }
            Text(estado.nome).font(Tipo.rotulo).tracking(0.3).lineLimit(1)
        }
        .foregroundStyle(tons.tinta)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tons.fundo, in: Capsule())
        .fixedSize()
    }
}

// MARK: - Janelas livres

private struct JanelasLivres: View {
    let painel: PainelDeCadeiras
    let tocar: (JanelaLivreDeCadeira) -> Void

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            // Janela que já acabou não é capacidade. A API devolve o dia inteiro, inclusive o
            // que ficou para trás; a tela mostra só o que ainda dá para usar.
            let abertas = painel.janelasLivres.filter { $0.ate > ctx.date }
            VStack(alignment: .leading, spacing: 0) {
                Text("Vãos de uma hora ou mais dentro do expediente (\(Formato.hora(painel.expediente.abertura)) às \(Formato.hora(painel.expediente.fechamento))). É a capacidade que sobra depois de contar a ocupação real.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Espaco.m)

                if abertas.isEmpty {
                    Text(painel.janelasLivres.isEmpty
                         ? "Nenhuma janela de uma hora hoje. O dia está cheio."
                         : "O expediente de hoje já não tem janela de uma hora pela frente.")
                        .font(Tipo.corpo)
                        .foregroundStyle(Cor.texto)
                } else {
                    ForEach(Array(abertas.prefix(8).enumerated()), id: \.element.id) { i, janela in
                        if i > 0 { Divider().overlay(Cor.filete) }
                        Button { tocar(janela) } label: {
                            LinhaDeJanela(janela: janela, agora: ctx.date)
                        }
                        .buttonStyle(.pressionavel)
                    }
                    if abertas.count > 8 {
                        Text("e mais \(abertas.count - 8) \(abertas.count - 8 == 1 ? "janela" : "janelas") na linha do tempo")
                            .font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                            .padding(.top, Espaco.s)
                    }
                }
            }
            .padding(Espaco.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie()
        }
    }
}

private struct LinhaDeJanela: View {
    let janela: JanelaLivreDeCadeira
    let agora: Date

    var body: some View {
        let de = max(janela.de, agora)
        let minutos = janela.de < agora ? FormatoDoGiro.minutos(de: agora, ate: janela.ate) : janela.minutos
        HStack(spacing: Espaco.m) {
            Text("Cadeira \(janela.numero)")
                .font(Tipo.corpoForte)
                .foregroundStyle(Cor.texto)
            Spacer(minLength: 8)
            Text("\(janela.de < agora ? "agora" : Formato.hora(de)) às \(Formato.hora(janela.ate))")
                .font(Tipo.coluna)
                .foregroundStyle(Cor.textoSuave)
            Text(FormatoDoGiro.duracao(minutos))
                .font(Tipo.apoioForte)
                .monospacedDigit()
                .foregroundStyle(Cor.azulProfundo)
                .frame(minWidth: 52, alignment: .trailing)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Cor.azulProfundo.opacity(0.85))
        }
        .frame(minHeight: 48)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cadeira \(janela.numero), livre de \(janela.de < agora ? "agora" : Formato.hora(de)) às \(Formato.hora(janela.ate)), \(FormatoDoGiro.duracaoFalada(minutos)).")
        .accessibilityHint("Agenda uma sessão nesta janela")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Esqueleto

/// Carregamento com a forma do painel: herói, indicadores e a grade de poltronas.
private struct EsqueletoDoGiro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            VStack(alignment: .leading, spacing: Espaco.l) {
                Esqueleto(largura: 120, altura: 10)
                Esqueleto(largura: 140, altura: 52)
                HStack(spacing: 4) { ForEach(0..<10, id: \.self) { _ in Esqueleto(altura: 22) } }
            }
            .padding(Espaco.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie()

            HStack(spacing: Espaco.m) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) { Esqueleto(largura: 80, altura: 10); Esqueleto(largura: 70, altura: 26) }
                        .padding(Espaco.l).frame(maxWidth: .infinity, alignment: .leading).superficie()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Espaco.m) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        Esqueleto(largura: 28, altura: 12)
                        Spacer()
                        Esqueleto(largura: 110, altura: 13)
                        Esqueleto(largura: 80, altura: 10)
                    }
                    .padding(Espaco.l)
                    .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
                    .superficie(raio: Raio.linha)
                }
            }
        }
    }
}
