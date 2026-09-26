import Charts
import SwiftUI

@MainActor
@Observable
final class NavegacaoStore {
    private(set) var carga: Carga<PainelDeNavegacao> = .carregando
    private let api: ClienteAPI

    // `nonisolated` para a View poder criar o store no valor inicial do `@State` sem
    // arrastar o próprio init para o MainActor (`telaSecundaria` não é isolada).
    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/painel/navegacao"))
        } catch is CancellationError {
        } catch {
            carga = .falhou(AcessoAnalitico.traduzir(error), anterior: anterior)
        }
    }
}

/// Navegação — porta de `painel/navegacao/page.tsx` (blocos 6, 9, 10 e 11 dos prints).
///
/// Quatro leituras que respondem à mesma pergunta: onde o serviço está travando. O mural
/// (estado do dia), o que ameaça o tratamento de amanhã, os indicadores do mês e o mapa de
/// barreiras. Nada aqui classifica paciente, então nada aqui usa cor de faixa (ADR-005).
struct NavegacaoView: View {
    @State private var store = NavegacaoStore()

    /// Explícito e `nonisolated`: `telaSecundaria` (MaisView) cria a tela fora do MainActor.
    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Painel",
                titulo: "Navegação",
                contexto: "Onde o serviço está travando. Contagem de operação, não classificação de paciente."
            )

            ConteudoDaCarga(carga: store.carga, linhasDeEsqueleto: 4, tentarDeNovo: {
                Task { await store.carregar() }
            }) { dados in
                PainelDeNavegacaoConteudo(dados: dados)
            }
        }
        .task { await store.carregar() }
    }
}

private struct PainelDeNavegacaoConteudo: View {
    let dados: PainelDeNavegacao

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            mural

            // Antes do resto: é o único bloco com prazo.
            BlocoAnalitico(
                titulo: "Tratamento amanhã",
                descricao: "O que pode suspender a sessão. Descobrir isto na recepção custa uma viagem ao paciente.",
                indice: 1
            ) {
                if dados.alertasPreTratamento.isEmpty {
                    VazioAnalitico(
                        titulo: "Nenhuma pendência registrada para amanhã.",
                        texto: "Ausência de registro não é ausência de pendência."
                    )
                } else {
                    AlertasPreTratamento(alertas: dados.alertasPreTratamento)
                }
            }

            BlocoAnalitico(
                titulo: "Últimos 30 dias",
                descricao: "Volume, tempo de resposta e desfechos do acompanhamento.",
                indice: 2
            ) {
                IndicadoresDoMes(indicadores: dados.indicadores)
            }

            BlocoAnalitico(
                titulo: "Mapa de barreiras",
                descricao: "Quantos pacientes esbarram na mesma coisa. Só as que continuam abertas.",
                indice: 3
            ) {
                if dados.barreiras.isEmpty {
                    VazioAnalitico(
                        titulo: "Nenhuma barreira registrada",
                        texto: "Ninguém registrou barreira de acesso ainda. Isso costuma querer dizer que o registro não começou, e não que não existam."
                    )
                } else {
                    MapaDeBarreiras(barreiras: dados.barreiras)
                }
            }
        }
    }

    /// O estado do dia em quatro números, antes de qualquer análise. Todos com apoio, para
    /// os quatro cartões terem a mesma altura na grade.
    private var mural: some View {
        let m = dados.mural
        return Grid(horizontalSpacing: Espaco.s, verticalSpacing: Espaco.s) {
            GridRow(alignment: .top) {
                CartaoDeIndicador(rotulo: "Pacientes internados", valor: "\(m.pacientesInternados)",
                                  apoio: "agora", destaque: true)
                CartaoDeIndicador(rotulo: "Tratamentos suspensos", valor: "\(m.tratamentosSuspensos)",
                                  apoio: "sem encerramento")
            }
            GridRow(alignment: .top) {
                CartaoDeIndicador(rotulo: "Pendências para amanhã", valor: "\(m.pendenciasParaAmanha)",
                                  apoio: "em aberto")
                CartaoDeIndicador(rotulo: "Barreiras abertas", valor: "\(m.barreirasAbertas)",
                                  apoio: "sem resolução")
            }
        }
        .animation(Movimento.interface, value: dados.mural)
    }
}

// MARK: - Alertas pré-tratamento

private struct AlertasPreTratamento: View {
    let alertas: [PainelDeNavegacao.AlertaPreTratamento]

    var body: some View {
        VStack(spacing: Espaco.s) {
            ForEach(Array(alertas.enumerated()), id: \.element.id) { i, alerta in
                // O nome leva ao prontuário, como o link do web — a pendência se resolve lá.
                NavigationLink {
                    ProntuarioView(pacienteId: alerta.pacienteId, nome: alerta.paciente, situacao: nil)
                } label: {
                    LinhaDeAlerta(alerta: alerta)
                }
                .buttonStyle(.pressionavel)
                .entradaEscalonada(i)
            }
        }
    }
}

private struct LinhaDeAlerta: View {
    let alerta: PainelDeNavegacao.AlertaPreTratamento

    private var data: String {
        FormatoAnalitico.diaCivil(alerta.referenteA).map(FormatoAnalitico.dataCurta) ?? alerta.referenteA
    }

    var body: some View {
        HStack(spacing: Espaco.m) {
            Image(systemName: alerta.tipo.icone)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Cor.azulProfundo)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Cor.azulGelo.opacity(0.35)))
            VStack(alignment: .leading, spacing: 3) {
                Text(alerta.paciente)
                    .font(Tipo.corpoForte)
                    .foregroundStyle(Cor.texto)
                    .lineLimit(2)
                Text(alerta.tipo.nome)
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                if let descricao = alerta.descricao, !descricao.isEmpty {
                    Text(descricao)
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoFraco)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(data)
                .font(Tipo.coluna)
                .foregroundStyle(Cor.textoFraco)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Cor.textoFraco.opacity(0.7))
        }
        .padding(.horizontal, Espaco.m)
        .padding(.vertical, Espaco.m)
        .frame(minHeight: 60)
        .superficie(.plano, raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alerta.paciente): \(alerta.tipo.nome)\(alerta.descricao.map { ", \($0)" } ?? ""), para \(data)")
        .accessibilityHint("Abre o prontuário")
    }
}

// MARK: - Indicadores do mês

private struct IndicadoresDoMes: View {
    let indicadores: PainelDeNavegacao.Indicadores

    var body: some View {
        let i = indicadores
        let linhas: [(String, String)] = [
            ("Pacientes acompanhados", "\(i.pacientesAcompanhados)"),
            ("Intervenções realizadas", "\(i.intervencoesRealizadas)"),
            ("Tempo médio de resposta", FormatoAnalitico.duracao(i.tempoMedioDeRespostaEmMinutos)),
            ("Encaminhamentos", "\(i.encaminhamentos)"),
            ("Internações notificadas", "\(i.internacoesNotificadas)"),
            ("Tratamentos suspensos", "\(i.tratamentosSuspensos)"),
            ("Sem rede de apoio", "\(i.pacientesSemRedeDeApoio)"),
            ("Com dificuldade de acesso", "\(i.pacientesComDificuldadeDeAcesso)"),
        ]
        VStack(spacing: 0) {
            ForEach(Array(linhas.enumerated()), id: \.offset) { indice, linha in
                if indice > 0 { Rectangle().fill(Cor.filete).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: Espaco.l) {
                    Text(linha.0).font(Tipo.corpo).foregroundStyle(Cor.textoSuave)
                    Spacer(minLength: 8)
                    Text(linha.1)
                        .font(Tipo.corpoForte)
                        .monospacedDigit()
                        .foregroundStyle(Cor.texto)
                        .contentTransition(.numericText())
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Mapa de barreiras

/// Barras horizontais, uma cor por índice. Quatro tipos com cor própria; do quinto em
/// diante o excedente vira "Outras" em neutro — e os tipos agrupados são ditos por extenso
/// logo abaixo, para nenhum número do web sumir.
private struct MapaDeBarreiras: View {
    let barreiras: [PainelDeNavegacao.Barreira]
    @State private var revelado = false

    private var categorias: [CategoriaAnalitica] {
        CategoriaAnalitica.agrupar(barreiras.enumerated().map { i, b in
            (id: "\(i)-\(b.tipo.nome)", rotulo: b.tipo.nome, valor: b.quantidade)
        })
    }

    var body: some View {
        let categorias = self.categorias
        let maior = max(categorias.map(\.valor).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: Espaco.m) {
            Chart(categorias) { c in
                BarMark(
                    x: .value("Pacientes", revelado ? c.valor : 0),
                    y: .value("Barreira", c.rotulo)
                )
                .foregroundStyle(c.cor)
                .cornerRadius(5)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text("\(c.valor)")
                        .font(Tipo.apoioForte)
                        .monospacedDigit()
                        .foregroundStyle(Cor.texto)
                        .opacity(revelado ? 1 : 0)
                }
            }
            // Folga à direita para o número da maior barra não ser cortado.
            .chartXScale(domain: 0...(Double(maior) * 1.18))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { valor in
                    AxisValueLabel {
                        if let rotulo = valor.as(String.self) {
                            Text(rotulo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: CGFloat(categorias.count) * 38)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rotuloAcessivel)

            ForEach(categorias.filter(\.ehOutras)) { outras in
                Text("Outras: " + outras.agrupadas.map { "\($0.rotulo) \($0.valor)" }.joined(separator: " · "))
                    .font(Tipo.apoio)
                    .monospacedDigit()
                    .foregroundStyle(Cor.textoFraco)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .revelaGrafico($revelado)
        .animation(Movimento.chegada, value: categorias.map(\.valor))
    }

    private var rotuloAcessivel: String {
        let itens = barreiras.map { b in
            "\(b.tipo.nome), \(b.quantidade) \(b.quantidade == 1 ? "paciente" : "pacientes")"
        }
        return "Barreiras abertas por tipo: " + itens.joined(separator: "; ") + "."
    }
}
