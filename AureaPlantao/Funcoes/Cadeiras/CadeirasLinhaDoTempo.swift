import SwiftUI

/// A linha do tempo do dia, cadeira por cadeira.
///
/// É a peça que torna o argumento visível: a barra de cada paciente é a ocupação REAL, já
/// com preparo, pré-medicação, observação e virada. Duas horas de infusão viram uma barra
/// de duas horas e vinte, e o vão que sobra no fim do dia é capacidade de verdade.
///
/// Rola na horizontal dentro do próprio trilho, e abre já posicionada no "agora": doze
/// horas de expediente não cabem num celular em pé, e espremer produziria barras de três
/// pontos. O número da cadeira fica preso à esquerda enquanto o dia rola.
struct LinhaDoTempoDoGiro: View {
    let painel: PainelDeCadeiras
    let tocar: (SessaoDeCadeira) -> Void

    private let pontosPorHora: CGFloat = 72
    private let alturaDaLinha: CGFloat = 36
    private let larguraDoRotulo: CGFloat = 40

    private var abertura: Date { painel.expediente.abertura }
    private var fechamento: Date { painel.expediente.fechamento }
    private var horas: Double { fechamento.timeIntervalSince(abertura) / 3600 }
    private var larguraTotal: CGFloat { CGFloat(horas) * pontosPorHora }

    var body: some View {
        if horas <= 0 {
            EmptyView()
        } else {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: Espaco.m) {
                    Text("A barra é a ocupação real da poltrona, não só o tempo de infusão.")
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 0) {
                        coluna
                        ScrollView(.horizontal) {
                            trilho(agora: ctx.date)
                                .padding(.trailing, Espaco.l)
                        }
                        .scrollIndicators(.hidden)
                        .defaultScrollAnchor(ancora(agora: ctx.date))
                        .fadeArestaDireita(32)
                    }

                    LegendaDaLinhaDoTempo()
                }
                .padding(Espaco.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficie()
            }
        }
    }

    /// Abre com o "agora" a um terço da largura: dá para ver o que acabou de acontecer e
    /// o que vem pela frente. Fora do expediente, abre no começo ou no fim.
    private func ancora(agora: Date) -> UnitPoint {
        let fracao = agora.timeIntervalSince(abertura) / fechamento.timeIntervalSince(abertura)
        return UnitPoint(x: min(1, max(0, fracao - 0.12)), y: 0)
    }

    private var coluna: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Color.clear.frame(height: 18)
            ForEach(painel.giro.porCadeira) { o in
                Text("#\(o.cadeira.numero)")
                    .font(Tipo.coluna)
                    .foregroundStyle(Cor.textoFraco)
                    .frame(width: larguraDoRotulo - 8, height: alturaDaLinha, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .padding(.trailing, 8)
    }

    private func trilho(agora: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            regua
            ForEach(painel.giro.porCadeira) { o in
                linha(o)
            }
        }
        .frame(width: larguraTotal, alignment: .leading)
        .overlay(alignment: .topLeading) { marcaDoAgora(agora) }
    }

    private var regua: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: 0, through: Int(horas), by: 1)), id: \.self) { h in
                let x = CGFloat(h) * pontosPorHora
                VStack(alignment: .leading, spacing: 2) {
                    if h % 2 == 0 {
                        Text(Formato.hora(abertura.addingTimeInterval(Double(h) * 3600)))
                            .font(.custom("IBMPlexMono-Regular", size: 10, relativeTo: .caption2))
                            .foregroundStyle(Cor.textoFraco)
                            .fixedSize()
                    }
                }
                .offset(x: h == Int(horas) ? x - 30 : x)
            }
        }
        .frame(width: larguraTotal, height: 18, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func linha(_ o: OcupacaoDeCadeira) -> some View {
        let sessoes = painel.sessoesDoDia.filter { $0.cadeiraId == o.cadeira.id && $0.estado != .cancelada }
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Cor.fundo)
            // Grade das horas: guia sem competir com as barras.
            ForEach(1..<max(2, Int(horas)), id: \.self) { h in
                Rectangle().fill(Cor.filete)
                    .frame(width: 1)
                    .offset(x: CGFloat(h) * pontosPorHora)
            }
            ForEach(sessoes) { s in
                barra(s)
            }
        }
        .frame(width: larguraTotal, height: alturaDaLinha)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rotuloDaLinha(o, sessoes: sessoes))
    }

    @ViewBuilder
    private func barra(_ s: SessaoDeCadeira) -> some View {
        let total = fechamento.timeIntervalSince(abertura)
        let inicio = max(0, s.previsaoDeInicio.timeIntervalSince(abertura))
        let fim = min(total, s.previsaoDeFim.timeIntervalSince(abertura))
        if fim > inicio {
            let x = CGFloat(inicio / 3600) * pontosPorHora
            let largura = max(6, CGFloat((fim - inicio) / 3600) * pontosPorHora)
            let visual = VisualDaBarra(estado: s.estado)
            Button { tocar(s) } label: {
                Text(s.paciente)
                    .font(.custom("Plus Jakarta Sans", size: 11, relativeTo: .caption2).weight(.semibold))
                    .foregroundStyle(visual.texto)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: largura, height: alturaDaLinha - 6, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(visual.preenchimento)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(visual.contorno, style: StrokeStyle(lineWidth: 1, dash: visual.tracejado ? [3, 2] : []))
                            }
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.pressionavel)
            .offset(x: x)
            .accessibilityLabel("\(s.paciente), das \(Formato.hora(s.previsaoDeInicio)) às \(Formato.hora(s.previsaoDeFim)), \(s.estado.nome)")
            .accessibilityHint("Abre a sessão")
        }
    }

    private func marcaDoAgora(_ agora: Date) -> some View {
        let fracao = agora.timeIntervalSince(abertura) / fechamento.timeIntervalSince(abertura)
        return Group {
            if fracao >= 0 && fracao <= 1 {
                let x = CGFloat(fracao) * larguraTotal
                VStack(spacing: 0) {
                    Text("agora")
                        .font(.custom("Plus Jakarta Sans", size: 9.5, relativeTo: .caption2).weight(.bold))
                        .foregroundStyle(Cor.textoInvertido)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(Cor.azulProfundo))
                        .fixedSize()
                    Rectangle().fill(Cor.azulProfundo).frame(width: 1.5)
                }
                .offset(x: x - 18)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func rotuloDaLinha(_ o: OcupacaoDeCadeira, sessoes: [SessaoDeCadeira]) -> String {
        guard !sessoes.isEmpty else { return "Cadeira \(o.cadeira.numero): livre o dia todo." }
        let partes = sessoes.map { "\($0.paciente) das \(Formato.hora($0.previsaoDeInicio)) às \(Formato.hora($0.previsaoDeFim)), \($0.estado.nome.lowercased())" }
        return "Cadeira \(o.cadeira.numero): " + partes.joined(separator: "; ")
    }
}

/// Agendada é contorno tracejado (ainda é previsão), em curso é cheio na cor do estado,
/// concluída recua para o cinza da estrutura.
private struct VisualDaBarra {
    let preenchimento: Color
    let contorno: Color
    let texto: Color
    let tracejado: Bool

    init(estado: EstadoDaSessao) {
        let cadeira = estado.estadoDaCadeira
        switch estado {
        case .concluida:
            preenchimento = Cor.fundoFundo; contorno = .clear; texto = Cor.textoSuave; tracejado = false
        case .agendada, .desconhecido, .cancelada:
            preenchimento = TonsDoGiro.acoAzul.fundo; contorno = TonsDoGiro.acoAzul.tinta.opacity(0.6)
            texto = TonsDoGiro.acoAzul.tinta; tracejado = true
        default:
            preenchimento = cadeira.tons.tinta; contorno = .clear; texto = .white; tracejado = false
        }
    }
}

private struct LegendaDaLinhaDoTempo: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Espaco.m) { itens }
            VStack(alignment: .leading, spacing: 6) { itens }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var itens: some View {
        item(TonsDoGiro.acoAzul.fundo, contorno: TonsDoGiro.acoAzul.tinta.opacity(0.6), "Agendada", tracejado: true)
        item(TonsDoGiro.acoAzul.tinta, contorno: .clear, "Em curso (cor do estado)", tracejado: false)
        item(Cor.fundoFundo, contorno: .clear, "Concluída", tracejado: false)
    }

    private func item(_ cor: Color, contorno: Color, _ nome: String, tracejado: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cor)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(contorno, style: StrokeStyle(lineWidth: 1, dash: tracejado ? [2, 1.5] : []))
                }
                .frame(width: 16, height: 10)
            Text(nome).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).fixedSize()
        }
    }
}
