import SwiftUI

@main
struct AureaPlantaoApp: App {
    @State private var sessao = Sessao()

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(sessao)
                .preferredColorScheme(.light)
                .tint(Cor.azulProfundo)
        }
    }
}

/// A porta do app. Decide o que aparece a partir da fase da sessão, e tranca ao sair do
/// primeiro plano.
struct RaizView: View {
    @Environment(Sessao.self) private var sessao
    @Environment(\.scenePhase) private var fase

    var body: some View {
        ZStack {
            switch sessao.fase {
            case .verificando:
                Cor.azulProfundo.ignoresSafeArea()
            case .fora:
                EntradaView().transition(.opacity)
            case .trocandoSenha(let atual):
                TrocaDeSenhaView(senhaAtual: atual).transition(.opacity)
            case .trancado:
                TrancaView().transition(.opacity)
            case .dentro:
                AbasView().transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            // Cobre a tela quando o app sai de ativo: a miniatura do seletor de apps é
            // tirada nesse instante, e ela não pode mostrar nome de paciente.
            if fase != .active, sessao.fase == .dentro {
                CapaDePrivacidade().transition(.opacity)
            }
        }
        .animation(Movimento.interface, value: sessao.fase)
        .animation(Movimento.toque, value: fase)
        .onAppear { sessao.iniciar() }
        .onChange(of: fase) { _, nova in
            if nova == .background { sessao.trancar() }
        }
    }
}

private struct CapaDePrivacidade: View {
    var body: some View {
        ZStack {
            Cor.azulProfundo.ignoresSafeArea()
            MarcaAurea(tamanho: 56)
        }
    }
}

// MARK: - Abas

/// A casca do app autenticado. As abas saem das PERMISSÕES de quem entrou (`Acesso`):
/// a enfermeira de plantão vê Plantão · Contatos · Pacientes · Mais; o médico, que só lê
/// histórico, não vê Contatos nem Cadeiras; o administrador vê a área dele.
struct AbasView: View {
    @Environment(Sessao.self) private var sessao
    @State private var aba: Destino = .plantao
    @State private var plantao = PlantaoStore()
    @State private var contatos = ContatosStore()
    @State private var mostrandoConta = false
    @Environment(\.scenePhase) private var fase

    private var acesso: Acesso {
        Acesso(perfil: sessao.eu?.perfil ?? "PROFISSIONAL", permissoes: sessao.eu?.permissoes ?? [])
    }

    private var ehPainel: Bool { !acesso.ehAdministrador }
    private var atendePlantao: Bool { acesso.tem("ATENDER_PLANTAO") }

    var body: some View {
        let abas = acesso.abas

        ZStack(alignment: .bottom) {
            FundoVivo(tom: aba.tom)
                .animation(.easeInOut(duration: 0.8), value: aba)

            // As telas ficam vivas: trocar de aba não recarrega nem perde a rolagem.
            ZStack {
                ForEach(abas) { destino in
                    tela(destino).visivel(aba == destino)
                }
            }

            VStack(spacing: 8) {
                if ehPainel, abas.contains(.plantao) {
                    FaixaAoVivo(atualizadoEm: plantao.atualizadoEm, aguardando: atendePlantao ? contatos.aguardando : 0) {
                        guard abas.contains(.contatos) else { return }
                        Tato.selecao()
                        withAnimation(Movimento.interface) { aba = .contatos }
                    }
                }
                BarraDeAbas(abas: abas, aba: $aba, aguardando: atendePlantao ? contatos.aguardando : 0)
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.bottom, 4)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            if !abas.contains(aba), let primeira = abas.first { aba = primeira }
        }
        .onChange(of: acesso) { _, novo in
            if !novo.abas.contains(aba), let primeira = novo.abas.first { aba = primeira }
        }
        .sheet(isPresented: $mostrandoConta) {
            ContaView()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
                .presentationBackground(.regularMaterial)
        }
        // "Ao vivo" tem que ser verdade: com o app na frente, a fila e os pedidos se
        // atualizam a cada minuto. No fundo, nada roda.
        .task(id: fase) {
            guard fase == .active, ehPainel else { return }
            while !Task.isCancelled {
                if atendePlantao {
                    async let a: Void = plantao.carregar()
                    async let b: Void = contatos.carregar()
                    _ = await (a, b)
                } else {
                    await plantao.carregar()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .environment(\.abrirConta, AcaoDeAbrirConta(acao: { mostrandoConta = true }))
    }

    @ViewBuilder
    private func tela(_ destino: Destino) -> some View {
        switch destino {
        case .plantao: PlantaoView(store: plantao, mostrandoConta: $mostrandoConta)
        case .contatos: ContatosView(store: contatos)
        case .pacientes: PacientesView()
        case .inicioAdmin: InicioAdminView()
        case .limiares: LimiaresView()
        case .cadastros: CadastrosView()
        case .mais: MaisView(destinos: acesso.secundarios)
        default: EmConstrucao(destino: destino)
        }
    }
}

/// Abre a folha da conta de qualquer tela (avatar no cabeçalho).
/// Embrulhada num tipo comparável: closure crua no Environment invalida quem depende dela
/// a cada atualização da casca.
struct AcaoDeAbrirConta: Equatable {
    fileprivate let acao: () -> Void
    func callAsFunction() { acao() }
    static func == (_: Self, _: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var abrirConta = AcaoDeAbrirConta(acao: {})
}

private extension View {
    /// Aba escondida some de verdade: sem toque e fora da árvore de acessibilidade — senão o
    /// VoiceOver leria a fila de uma aba que a pessoa nem está vendo.
    func visivel(_ ativo: Bool) -> some View {
        opacity(ativo ? 1 : 0)
            .allowsHitTesting(ativo)
            .accessibilityHidden(!ativo)
    }
}

/// A faixa acima das abas — o lugar do clima no BT Professor. Aqui ela diz se a fila
/// está fresca e quantos pedidos esperam, e leva para Contatos com um toque.
private struct FaixaAoVivo: View {
    let atualizadoEm: Date?
    let aguardando: Int
    let abrirContatos: () -> Void
    @State private var pulso = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    var body: some View {
        Button(action: abrirContatos) {
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Cor.azulProfundo.opacity(0.18))
                            .frame(width: 14, height: 14)
                            .scaleEffect(pulso ? 1 : 0.4)
                            .opacity(pulso ? 0 : 1)
                        Circle().fill(Cor.azulProfundo).frame(width: 6, height: 6)
                    }
                    Text(atualizadoEm.map { "Ao vivo · \(Formato.desde($0, agora: ctx.date))" } ?? "Conectando…")
                        .font(Tipo.apoioForte)
                        .monospacedDigit()
                        .foregroundStyle(Cor.texto)
                    Spacer(minLength: 8)
                    if aguardando > 0 {
                        Text(aguardando == 1 ? "1 pedido de contato" : "\(aguardando) pedidos de contato")
                            .font(Tipo.apoio)
                            .monospacedDigit()
                            .foregroundStyle(Cor.textoSuave)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Cor.textoFraco)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.35)))
                        .overlay(Capsule().strokeBorder(
                            LinearGradient(colors: [.white, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1))
                        .shadow(color: Cor.tinta.opacity(0.08), radius: 12, y: 6)
                }
            }
        }
        .buttonStyle(.pressionavel)
        .disabled(aguardando == 0)
        .accessibilityLabel(aguardando > 0 ? "Fila ao vivo. \(aguardando) pedidos de contato. Abre Contatos." : "Fila ao vivo")
        .onAppear {
            guard !reduzirMovimento else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulso = true }
        }
    }
}

/// Barra de abas flutuante em vidro. A pílula azul desliza entre as abas (matched
/// geometry) e o rótulo só aparece na ativa — as outras ficam como ícone.
/// Custom e não `TabView`: a nativa é opaca e mata o fundo vivo, e não anima a seleção.
private struct BarraDeAbas: View {
    let abas: [Destino]
    @Binding var aba: Destino
    let aguardando: Int
    @Namespace private var indicador
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    var body: some View {
        HStack(spacing: 4) {
            ForEach(abas) { item in
                let ativo = aba == item
                Button {
                    guard !ativo else { return }
                    Tato.selecao()
                    withAnimation(reduzirMovimento ? .easeOut(duration: 0.15) : Movimento.interface) { aba = item }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: ativo ? item.iconeAtivo : item.icone)
                            .font(.system(size: 15, weight: .semibold))
                            .symbolEffect(.bounce, value: ativo)
                        if ativo {
                            Text(item.nome)
                                .font(Tipo.apoioForte)
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                        if item == .contatos, aguardando > 0 {
                            Text("\(aguardando)")
                                .font(.custom("Plus Jakarta Sans", size: 11, relativeTo: .caption).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(ativo ? Cor.azulProfundo : Cor.textoInvertido)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(ativo ? Cor.azulGelo : Cor.azulProfundo))
                                .contentTransition(.numericText(value: Double(aguardando)))
                        }
                    }
                    .foregroundStyle(ativo ? Cor.textoInvertido : Cor.textoSuave)
                    .padding(.horizontal, ativo ? 18 : 14)
                    .frame(maxWidth: ativo ? .infinity : nil, minHeight: 48)
                    .frame(minWidth: 56)
                    .background {
                        if ativo {
                            Capsule()
                                .fill(Cor.azulProfundo)
                                .overlay(Capsule().strokeBorder(
                                    LinearGradient(colors: [Color(hex: 0xB4D6F0, opacidade: 0.35), .clear], startPoint: .top, endPoint: .center),
                                    lineWidth: 1))
                                .shadow(color: Cor.sombraAzul, radius: 8, y: 4)
                                .matchedGeometryEffect(id: "indicador", in: indicador)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .contatos && aguardando > 0 ? "\(item.nome), \(aguardando) aguardando" : item.nome)
                .accessibilityAddTraits(ativo ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(5)
        .background {
            // Vidro: o material refrata o fundo vivo; o branco a 30% segura a leitura no claro.
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.3)))
                .overlay(Capsule().strokeBorder(
                    LinearGradient(colors: [.white, .white.opacity(0.15)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
                .shadow(color: Cor.tinta.opacity(0.05), radius: 2, y: 1)
                .shadow(color: Cor.tinta.opacity(0.14), radius: 24, y: 12)
        }
    }
}
