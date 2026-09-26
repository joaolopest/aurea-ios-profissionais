import SwiftUI

/// O coração do app. Abre e responde, em um segundo, a única pergunta do plantão:
/// quem precisa de mim agora?
///
/// Composição de cima para baixo, na ordem em que o olho precisa:
/// 1. o número — quantos precisam de você (ou "Ninguém agora.")
/// 2. a proporção da escala, numa barra só
/// 3. os filtros, com a contagem de cada faixa
/// 4. a fila, na ordem de gravidade da API
struct PlantaoView: View {
    @Environment(Sessao.self) private var sessao
    let store: PlantaoStore
    @Binding var mostrandoConta: Bool
    @Namespace private var transicao

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    cabecalho
                        .padding(.bottom, Espaco.l)

                    PainelDoNumero(store: store)
                        .padding(.bottom, Espaco.l)

                    if store.dados != nil {
                        FiltrosDaFila(store: store)
                            .padding(.horizontal, -Espaco.margem)
                            .padding(.bottom, Espaco.l)
                            .transition(.opacity)
                    }

                    if let erro = store.carga.erro {
                        CartaoDeErro(erro: erro) { Task { await store.carregar() } }
                            .padding(.bottom, Espaco.l)
                    }

                    fila
                }
                .padding(.horizontal, Espaco.margem)
                .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                Tato.leve()
                await store.carregar()
            }
            .encerraSessaoNo401(store.carga.erro)
            // O fundo vivo mora atrás de tudo, na casca — a pilha de navegação é transparente.
            .containerBackground(.clear, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CartaoDoPlantao.self) { cartao in
                ProntuarioView(pacienteId: cartao.pacienteId, nome: cartao.nome, situacao: cartao.situacaoClinica)
                    .navigationTransition(.zoom(sourceID: cartao.id, in: transicao))
            }
        }
    }

    // MARK: Cabeçalho

    private var cabecalho: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dataDoPlantao).estiloDeRotulo()
                Text(saudacao)
                    .font(Tipo.titulo)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(Cor.texto)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                Tato.selecao()
                mostrandoConta = true
            } label: {
                Iniciais(nome: sessao.eu?.perfilDetalhado?.nome ?? "AUREA", tamanho: 42)
            }
            .buttonStyle(.pressionavel)
            .accessibilityLabel("Sua conta")
        }
        .padding(.top, Espaco.s)
    }

    /// Calor nas bordas (P6): a saudação é o único lugar da tela que fala como gente.
    /// O resto é dado.
    private var saudacao: String {
        let hora = Calendar.current.component(.hour, from: .now)
        let turno = switch hora {
        case 5..<12: "Bom dia"
        case 12..<18: "Boa tarde"
        default: "Boa noite"
        }
        let primeiroNome = sessao.eu?.perfilDetalhado?.nome.split(separator: " ").first.map(String.init)
        return primeiroNome.map { "\(turno), \($0)" } ?? turno
    }

    private var dataDoPlantao: String {
        "Plantão · " + Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))
    }

    // MARK: Fila

    @ViewBuilder
    private var fila: some View {
        if store.dados == nil, store.carga.erro == nil {
            VStack(spacing: Espaco.s) {
                ForEach(0..<6, id: \.self) { _ in LinhaEsqueleto() }
            }
        } else if store.fila.isEmpty, store.dados != nil {
            EstadoVazio(
                titulo: store.filtro == .precisam ? "Ninguém agora." : "Ninguém nesta faixa.",
                texto: store.filtro == .precisam
                    ? "Nenhum vermelho ou amarelo hoje. Quem não respondeu continua na fila completa."
                    : "Escolha outra faixa ou volte para todos."
            )
            .superficie()
        } else {
            VStack(spacing: Espaco.s) {
                ForEach(Array(store.fila.enumerated()), id: \.element.id) { i, cartao in
                    NavigationLink(value: cartao) {
                        LinhaDaFila(cartao: cartao)
                            .matchedTransitionSource(id: cartao.id, in: transicao)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity
                    ))
                }
            }
            .animation(Movimento.interface, value: store.fila.map(\.id))
        }
    }
}

// MARK: - O número

/// O cartão escuro: o único número da tela que não está em lugar nenhum — quantas pessoas
/// precisam de alguém agora. Com zero ele deixa de ser algarismo (ADR-006, Onda 4): um `0`
/// gigante pesa tanto quanto um `7` e custa um segundo tempo de leitura.
private struct PainelDoNumero: View {
    let store: PlantaoStore

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            Text("Precisam de você agora").estiloDeRotulo(cor: Cor.textoInvertido.opacity(0.62))

            Group {
                if store.dados == nil {
                    Esqueleto(largura: 96, altura: 56).opacity(0.25)
                } else if store.precisamDeVoce == 0 {
                    Text("Ninguém agora.")
                        .font(Tipo.titulo)
                        .foregroundStyle(Cor.textoInvertido.opacity(0.78))
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(store.precisamDeVoce)")
                            .font(Tipo.heroi)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(store.precisamDeVoce)))
                            // Azul-gelo sobre o azul profundo: o número é a única coisa da
                            // tela que acende. Nunca lima — sobre o azul ele vira verde.
                            .foregroundStyle(Cor.azulGelo)
                            .shadow(color: Cor.azulGelo.opacity(0.45), radius: 18)
                        Text(store.precisamDeVoce == 1 ? "paciente" : "pacientes")
                            .font(Tipo.destaque)
                            .foregroundStyle(Cor.textoInvertido.opacity(0.7))
                    }
                }
            }
            .animation(Movimento.chegada, value: store.precisamDeVoce)

            if let d = store.dados {
                BarraDaEscala(resumo: d.resumo)
                Text(legenda(d))
                    .font(Tipo.apoio)
                    .monospacedDigit()
                    .foregroundStyle(Cor.textoInvertido.opacity(0.66))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Espaco.xl)
        .background {
            let forma = RoundedRectangle(cornerRadius: Raio.cartao + 4, style: .continuous)
            forma
                .fill(Cor.azulProfundo)
                .overlay {
                    // Luz fria no canto superior + azul-gelo acendendo embaixo, à direita —
                    // o cartão de destaque do BT, sobre o azul da marca.
                    forma.fill(RadialGradient(
                        colors: [Color(hex: 0x2C5170, opacidade: 0.6), .clear],
                        center: .topLeading, startRadius: 0, endRadius: 320
                    ))
                }
                .overlay {
                    forma.fill(RadialGradient(
                        colors: [Cor.azulGelo.opacity(temAlguem ? 0.22 : 0.08), .clear],
                        center: .bottomTrailing, startRadius: 0, endRadius: 260
                    ))
                    .animation(Movimento.chegada, value: temAlguem)
                }
                .overlay {
                    forma.strokeBorder(
                        LinearGradient(colors: [Color(hex: 0xB4D6F0, opacidade: 0.18), .white.opacity(0.03)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .shadow(color: Cor.azulProfundoAlto.opacity(0.28), radius: 18, y: 12)
        }
        .accessibilityElement(children: .combine)
    }

    private var temAlguem: Bool { store.precisamDeVoce > 0 }

    private func legenda(_ d: PacientesDoDia) -> String {
        var partes: [String] = []
        if d.resumo.vermelhos > 0 { partes.append("\(d.resumo.vermelhos) vermelho" + (d.resumo.vermelhos > 1 ? "s" : "")) }
        if d.resumo.amarelos > 0 { partes.append("\(d.resumo.amarelos) amarelo" + (d.resumo.amarelos > 1 ? "s" : "")) }
        partes.append("\(d.resumo.semResposta) sem resposta hoje")
        if d.silencio.umaSemana + d.silencio.nuncaRespondeu > 0 {
            partes.append("\(d.silencio.umaSemana + d.silencio.nuncaRespondeu) calados há uma semana ou mais")
        }
        return partes.joined(separator: " · ")
    }
}

/// A escala inteira numa barra. Proporção como informação primária (Quicken, ADR-004 §7).
/// Aqui a cor clínica é legítima: cada segmento É uma contagem de pacientes por faixa.
private struct BarraDaEscala: View {
    let resumo: PacientesDoDia.Resumo

    var body: some View {
        let segmentos: [(SituacaoClinica, Int)] = [
            (.vermelho, resumo.vermelhos), (.amarelo, resumo.amarelos),
            (.silencio, resumo.semResposta), (.verde, resumo.verdes),
        ].filter { $0.1 > 0 }
        let total = max(1, segmentos.map(\.1).reduce(0, +))

        GeometryReader { geo in
            let espacos = CGFloat(max(0, segmentos.count - 1)) * 3
            HStack(spacing: 3) {
                ForEach(segmentos, id: \.0.nome) { situacao, n in
                    Capsule()
                        .fill(situacao == .silencio ? Color.white.opacity(0.28) : Faixa.tons(situacao).fundo)
                        .overlay(Capsule().fill(situacao == .silencio ? .clear : Faixa.tons(situacao).tinta.opacity(0.35)))
                        .frame(width: max(6, (geo.size.width - espacos) * CGFloat(n) / CGFloat(total)))
                }
            }
        }
        .frame(height: 8)
        .animation(Movimento.interface, value: [resumo.vermelhos, resumo.amarelos, resumo.semResposta, resumo.verdes])
        .accessibilityHidden(true)
    }
}

// MARK: - Filtros

private struct FiltrosDaFila: View {
    @Bindable var store: PlantaoStore

    var body: some View {
        SeletorDePilulas(
            opcoes: PlantaoStore.Filtro.allCases.map {
                OpcaoDeSeletor(id: $0, titulo: $0.nome, contador: store.contagem($0), faixa: $0.situacao)
            },
            selecionado: $store.filtro
        )
    }
}

// MARK: - Linha da fila

/// A linha-assinatura (DC-001): faixa clínica à esquerda, nome, o que foi observado, e o
/// número que desempata dois pacientes que a fila trata como iguais — dias de silêncio.
struct LinhaDaFila: View {
    let cartao: CartaoDoPlantao

    var body: some View {
        let tons = Faixa.tons(cartao.situacaoClinica)

        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tons.tinta)
                .frame(width: 4)
                .padding(.vertical, 12)
                .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(cartao.nome)
                        .font(Tipo.corpoForte)
                        .foregroundStyle(Cor.texto)
                        .lineLimit(1)
                    if cartao.sinalizadores.internadoAte != nil {
                        Text("Internado")
                            .font(Tipo.rotulo)
                            .tracking(0.4)
                            .foregroundStyle(Cor.azulProfundo)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Cor.fundoBaixo, in: Capsule())
                    }
                }
                Text(cartao.resumoDoMotivo)
                    .font(Tipo.apoio)
                    .monospacedDigit()
                    .foregroundStyle(cartao.situacaoClinica == .silencio ? Cor.textoSuave : tons.tinta)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.vertical, 14)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(colunaPrincipal)
                    .font(Tipo.colunaForte)
                    .foregroundStyle(Cor.texto)
                Text(colunaApoio)
                    .font(Tipo.rotulo)
                    .tracking(0.3)
                    .foregroundStyle(Cor.textoFraco)
            }
            .padding(.trailing, 6)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Cor.textoFraco.opacity(0.7))
                .padding(.trailing, 14)
        }
        .frame(minHeight: 68)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloDeAcessibilidade)
        .accessibilityHint("Abre o prontuário")
    }

    /// Silêncio: quantos dias calado (o que desempata dentro da mesma faixa, ADR-006 Onda 4).
    /// Respondeu: o dia do ciclo.
    private var colunaPrincipal: String {
        if cartao.nuncaRespondeu { return "—" }
        if !cartao.respondeuHoje, let dias = cartao.diasSemResponder, dias > 0 { return "\(dias)" }
        if let dia = cartao.diaDoCiclo { return "D\(dia)" }
        return "—"
    }

    private var colunaApoio: String {
        if cartao.nuncaRespondeu { return "nunca" }
        if !cartao.respondeuHoje, let dias = cartao.diasSemResponder, dias > 0 { return dias == 1 ? "dia calado" : "dias calado" }
        return "dia do ciclo"
    }

    private var rotuloDeAcessibilidade: String {
        var partes = [cartao.nome, cartao.situacaoClinica.nome, cartao.resumoDoMotivo]
        if cartao.sinalizadores.internadoAte != nil { partes.append("internado") }
        if let dia = cartao.diaDoCiclo { partes.append("dia \(dia) do ciclo") }
        return partes.joined(separator: ", ")
    }
}

private struct LinhaEsqueleto: View {
    var body: some View {
        HStack(spacing: 12) {
            Esqueleto(largura: 4, altura: 40)
            VStack(alignment: .leading, spacing: 8) {
                Esqueleto(largura: 150, altura: 13)
                Esqueleto(largura: 210, altura: 10)
            }
            Spacer()
            Esqueleto(largura: 34, altura: 12)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 68)
        .superficie(raio: Raio.linha)
    }
}
