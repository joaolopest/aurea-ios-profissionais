import SwiftUI

@MainActor
@Observable
final class ContatosStore {
    private(set) var carga: Carga<PaginaDeSolicitacoes> = .carregando
    private let api: ClienteAPI

    init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    var aguardando: Int { carga.valor?.aguardando ?? 0 }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/painel/solicitacoes-de-contato"))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    enum Resultado { case atendida, jaAtendida(String), falhou(ErroDaAPI) }

    /// Fecha o pedido. A API faz `updateMany` com `atendidaEm: null` na condição: se duas
    /// pessoas tocam ao mesmo tempo, a segunda recebe 409. Isso é o caso normal de plantão,
    /// e a resposta certa é tirar o pedido da fila dos dois — ninguém precisa fazer nada.
    func atender(_ solicitacao: SolicitacaoDeContato) async -> Resultado {
        struct Corpo: Encodable, Sendable {}
        do {
            let _: SolicitacaoAtendida = try await api.enviar(
                "/painel/solicitacoes-de-contato/\(solicitacao.id)/atendimento", corpo: Corpo()
            )
            remover(solicitacao)
            return .atendida
        } catch ErroDaAPI.conflito(let mensagem) {
            remover(solicitacao)
            return .jaAtendida(mensagem)
        } catch {
            return .falhou(ErroDaAPI(error))
        }
    }

    /// Otimista: o pedido sai da fila na hora, sem esperar a recarga.
    private func remover(_ s: SolicitacaoDeContato) {
        guard let pagina = carga.valor else { return }
        carga = .pronto(PaginaDeSolicitacoes(
            itens: pagina.itens.filter { $0.id != s.id },
            proximoCursor: pagina.proximoCursor,
            aguardando: max(0, pagina.aguardando - 1)
        ))
    }
}

/// A fila de pedidos de contato: o paciente apertou "Falar com a enfermagem" em casa.
/// Quem esperou mais vem primeiro.
struct ContatosView: View {
    let store: ContatosStore
    @State private var emAtendimento: SolicitacaoDeContato?
    @State private var aviso: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espaco.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fila de ligações").estiloDeRotulo()
                        Text("Pedidos de contato").font(Tipo.titulo).foregroundStyle(Cor.texto)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.top, Espaco.s)

                    if let pagina = store.carga.valor {
                        ResumoDaFila(pagina: pagina)
                    }

                    if let aviso {
                        Label(aviso, systemImage: "person.2.fill")
                            .font(Tipo.apoioForte)
                            .foregroundStyle(Cor.azulProfundo)
                            .padding(Espaco.l)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .superficie(.afundado, raio: Raio.linha)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let erro = store.carga.erro {
                        CartaoDeErro(erro: erro) { Task { await store.carregar() } }
                    }

                    lista
                }
                .padding(.horizontal, Espaco.margem)
                .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            .containerBackground(.clear, for: .navigation)
            .refreshable {
                Tato.leve()
                await store.carregar()
            }
            .task { await store.carregar() }
            .encerraSessaoNo401(store.carga.erro)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $emAtendimento) { s in
                AtenderSheet(solicitacao: s, store: store) { resultado in
                    emAtendimento = nil
                    if case .jaAtendida(let m) = resultado {
                        withAnimation(Movimento.chegada) { aviso = m }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
                .presentationBackground(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    private var lista: some View {
        if let pagina = store.carga.valor {
            if pagina.itens.isEmpty {
                EstadoVazio(titulo: "Ninguém esperando.", texto: "Quando um paciente pedir para falar com a enfermagem, o pedido aparece aqui.", icone: "phone")
                    .superficie()
            } else {
                VStack(spacing: Espaco.s) {
                    ForEach(Array(pagina.itens.enumerated()), id: \.element.id) { i, s in
                        Button {
                            Tato.selecao()
                            aviso = nil
                            emAtendimento = s
                        } label: {
                            LinhaDeSolicitacao(solicitacao: s)
                        }
                        .buttonStyle(.pressionavel)
                        .entradaEscalonada(i)
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96))))
                    }
                }
                .animation(Movimento.interface, value: pagina.itens.map(\.id))
            }
        } else if store.carga.erro == nil {
            VStack(spacing: Espaco.s) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack { Esqueleto(largura: 160, altura: 13); Spacer(); Esqueleto(largura: 48, altura: 11) }
                        .padding(Espaco.l).frame(minHeight: 72).superficie(raio: Raio.linha)
                }
            }
        }
    }
}

/// O resumo da fila, como o rodapé da chamada do BT: o número que importa grande, e o
/// contexto que decide a urgência — há quanto tempo espera o mais antigo.
private struct ResumoDaFila: View {
    let pagina: PaginaDeSolicitacoes

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            HStack(alignment: .firstTextBaseline, spacing: Espaco.xl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pagina.aguardando)")
                        .font(.custom("Plus Jakarta Sans", size: 44, relativeTo: .largeTitle).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Cor.azulProfundo)
                        .contentTransition(.numericText(value: Double(pagina.aguardando)))
                    Text(pagina.aguardando == 1 ? "aguardando" : "aguardando").estiloDeRotulo()
                }
                if let antigo = pagina.itens.map(\.solicitadaEm).min() {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formato.desde(antigo, agora: ctx.date))
                            .font(.custom("Plus Jakarta Sans", size: 24, relativeTo: .title2).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Cor.texto)
                        Text("o mais antigo").estiloDeRotulo()
                    }
                }
                Spacer()
            }
            .padding(Espaco.xl)
            .cartaoDestaque(tom: Color(hex: 0x7FA7CF))
            .animation(Movimento.interface, value: pagina.aguardando)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct LinhaDeSolicitacao: View {
    let solicitacao: SolicitacaoDeContato

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { contexto in
            HStack(spacing: 12) {
                Iniciais(nome: solicitacao.paciente.nome, tamanho: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(solicitacao.paciente.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto).lineLimit(1)
                    Text(solicitacao.sessaoId == nil ? "Pediu contato" : "Pediu contato depois do check-in")
                        .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formato.desde(solicitacao.solicitadaEm, agora: contexto.date))
                        .font(Tipo.apoioForte).monospacedDigit().foregroundStyle(Cor.texto)
                    Text(Formato.hora(solicitacao.solicitadaEm))
                        .font(Tipo.coluna).foregroundStyle(Cor.textoFraco)
                }
            }
            .padding(.horizontal, Espaco.l)
            .frame(minHeight: 72)
            .superficie(raio: Raio.linha)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Abre o atendimento")
        }
    }
}

/// Atender em dois toques (Steady): tocar no pedido → "Marcar como atendido".
/// No meio, o telefone — puxado do prontuário, porque a fila ainda não traz o número.
private struct AtenderSheet: View {
    let solicitacao: SolicitacaoDeContato
    let store: ContatosStore
    let concluir: (ContatosStore.Resultado) -> Void

    @State private var contatos: [Prontuario.Contato]?
    @State private var enviando = false
    @State private var erro: String?
    @State private var feito = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.xl) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pediu contato \(Formato.desde(solicitacao.solicitadaEm)) · \(Formato.hora(solicitacao.solicitadaEm))")
                    .estiloDeRotulo()
                Text(solicitacao.paciente.nome).font(Tipo.titulo).foregroundStyle(Cor.texto)
            }

            VStack(spacing: Espaco.s) {
                if let contatos {
                    if contatos.isEmpty {
                        Text("Nenhum telefone no cadastro.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    }
                    ForEach(Array(contatos.enumerated()), id: \.offset) { _, c in
                        if let url = URL(string: "tel:\(c.telefone.filter(\.isNumber))") {
                            Link(destination: url) {
                                HStack(spacing: 12) {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Cor.textoInvertido)
                                        .frame(width: 40, height: 40)
                                        .background(Cor.azulProfundo, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.tipo == "CONTATO_DE_EMERGENCIA" ? "Ligar para \(c.relacao ?? "contato de emergência")" : "Ligar para o paciente")
                                            .font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                                        Text(Formato.telefone(c.telefone)).font(Tipo.apoio).monospacedDigit().foregroundStyle(Cor.textoSuave)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .superficie(raio: Raio.linha)
                            }
                        }
                    }
                } else {
                    HStack { Esqueleto(largura: 40, altura: 40); Esqueleto(largura: 180, altura: 12); Spacer() }
                        .padding(12).superficie(raio: Raio.linha)
                }
            }

            Spacer(minLength: 0)

            if let erro {
                Text(erro).font(Tipo.apoio).foregroundStyle(Cor.texto)
            }

            BotaoPrimario(titulo: feito ? "Atendido" : "Marcar como atendido",
                          icone: feito ? "checkmark" : "checkmark.circle",
                          carregando: enviando) {
                Task { await atender() }
            }
            .sensoryFeedback(.success, trigger: feito)
        }
        .padding(Espaco.xl)
        .padding(.top, Espaco.s)
        .task { await carregarTelefones() }
    }

    private func carregarTelefones() async {
        let p: Prontuario? = try? await ClienteAPI.compartilhado.obter("/painel/pacientes/\(solicitacao.paciente.id)/historico")
        withAnimation(Movimento.chegada) { contatos = p?.contatos ?? [] }
    }

    private func atender() async {
        enviando = true
        erro = nil
        let resultado = await store.atender(solicitacao)
        enviando = false
        switch resultado {
        case .atendida:
            feito = true
            try? await Task.sleep(for: .milliseconds(450))
            concluir(resultado)
        case .jaAtendida:
            Tato.aviso()
            concluir(resultado)
        case .falhou(let e):
            Tato.erro()
            erro = e.mensagem
        }
    }
}
