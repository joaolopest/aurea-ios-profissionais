import SwiftUI

/// A marca do AUREA desenhada em código: o anel de acompanhamento com o ponto de sinal.
/// Vetor puro — nítido em qualquer tamanho, sem asset.
struct MarcaAurea: View {
    var tamanho: CGFloat = 44
    var cor: Color = Cor.textoInvertido

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(cor, style: StrokeStyle(lineWidth: tamanho * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90 + 0))
            Circle()
                .fill(Cor.azulGelo)
                .frame(width: tamanho * 0.2, height: tamanho * 0.2)
                .offset(y: -tamanho * 0.5 + tamanho * 0.05)
        }
        .frame(width: tamanho, height: tamanho)
        .accessibilityHidden(true)
    }
}

/// Entrada da equipe. E-mail e senha — não há OAuth, magic link nem Sign in with Apple na API.
struct EntradaView: View {
    @Environment(Sessao.self) private var sessao
    @State private var email = ""
    @State private var senha = ""
    @State private var manterConectado = true
    @State private var entrando = false
    @State private var erro: String?
    @State private var apareceu = false

    var body: some View {
        ZStack(alignment: .top) {
            FundoVivo()

            // O azul profundo sobe do topo: a mesma matéria da landing e do cartão do plantão.
            Cor.azulProfundo
                .overlay {
                    RadialGradient(colors: [Color(hex: 0x2C5170, opacidade: 0.6), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 420)
                }
                .frame(height: 330)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36, style: .continuous))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Espaco.l) {
                        MarcaAurea(tamanho: 40)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AUREA Plantão")
                                .font(Tipo.titulo)
                                .foregroundStyle(Cor.textoInvertido)
                            Text("Quem precisa de você agora, em um toque.")
                                .font(Tipo.corpo)
                                .foregroundStyle(Cor.textoInvertido.opacity(0.7))
                        }
                    }
                    .padding(.top, 36)
                    .padding(.bottom, 44)
                    .opacity(apareceu ? 1 : 0)
                    .offset(y: apareceu ? 0 : 10)

                    VStack(alignment: .leading, spacing: Espaco.l) {
                        if let aviso = sessao.avisoDeEntrada {
                            Text(aviso).font(Tipo.apoioForte).foregroundStyle(Cor.azulProfundo)
                        }
                        CampoDeEntrada(rotulo: "E-mail", texto: $email, teclado: .emailAddress, conteudo: .username)
                        CampoDeEntrada(rotulo: "Senha", texto: $senha, seguro: true, conteudo: .password,
                                       botaoDoTeclado: .go) { Task { await entrar() } }

                        Toggle(isOn: $manterConectado) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manter conectado por 30 dias").font(Tipo.apoioForte).foregroundStyle(Cor.texto)
                                Text("Neste iPhone. Saia pela sua conta ao terminar o plantão.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                            }
                        }
                        .tint(Cor.azulProfundo)

                        if let erro {
                            Text(erro)
                                .font(Tipo.apoio)
                                .foregroundStyle(Cor.texto)
                                .padding(Espaco.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .superficie(.afundado, raio: Raio.controle)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        BotaoPrimario(titulo: "Entrar", carregando: entrando) {
                            Task { await entrar() }
                        }
                        .padding(.top, Espaco.s)
                    }
                    .padding(Espaco.xl)
                    .superficie(.flutuante, raio: 28)
                    .opacity(apareceu ? 1 : 0)
                    .offset(y: apareceu ? 0 : 24)

                    Text("Dado de saúde. Cada acesso fica registrado.")
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoFraco)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Espaco.xl)
                }
                .padding(.horizontal, Espaco.margem)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Barra de status escura sobre o azul some; em tela de porta ela não informa nada.
        .statusBarHidden()
        .onAppear {
            withAnimation(Movimento.chegada.delay(0.05)) { apareceu = true }
        }
    }

    private func entrar() async {
        guard !email.isEmpty, !senha.isEmpty else {
            withAnimation(Movimento.interface) { erro = "Preencha e-mail e senha." }
            Tato.erro()
            return
        }
        entrando = true
        defer { entrando = false }
        do {
            try await sessao.entrar(email: email, senha: senha, manterConectado: manterConectado)
            Tato.sucesso()
        } catch {
            Tato.erro()
            let e = ErroDaAPI(error)
            withAnimation(Movimento.interface) {
                erro = e == .sessaoEncerrada ? "E-mail ou senha não conferem." : e.mensagem
            }
        }
    }
}

/// Primeiro acesso: a API exige trocar a senha provisória.
struct TrocaDeSenhaView: View {
    let senhaAtual: String
    @Environment(Sessao.self) private var sessao
    @State private var nova = ""
    @State private var confirmacao = ""
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Primeiro acesso").estiloDeRotulo()
                    Text("Crie sua senha").font(Tipo.titulo).foregroundStyle(Cor.texto)
                    Text("A senha que você recebeu é provisória. Depois de trocar, entre de novo com a nova.")
                        .font(Tipo.corpo).foregroundStyle(Cor.textoSuave)
                }
                VStack(spacing: Espaco.l) {
                    CampoDeEntrada(rotulo: "Senha nova · mínimo de 10 caracteres", texto: $nova, seguro: true, conteudo: .newPassword)
                    CampoDeEntrada(rotulo: "Repita a senha nova", texto: $confirmacao, seguro: true, conteudo: .newPassword)
                    if let erro {
                        Text(erro).font(Tipo.apoio).foregroundStyle(Cor.texto).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    BotaoPrimario(titulo: "Trocar senha", carregando: enviando) { Task { await trocar() } }
                }
                .padding(Espaco.xl)
                .superficie(.flutuante, raio: 28)

                #if DEBUG
                Button("Pular — só na demonstração") { sessao.pularTrocaDeSenhaNaDemonstracao() }
                    .font(Tipo.apoioForte)
                    .foregroundStyle(Cor.textoSuave)
                    .frame(maxWidth: .infinity, minHeight: 44)
                #endif
            }
            .padding(Espaco.margem)
            .padding(.top, Espaco.xl)
        }
        .background { FundoVivo() }
    }

    private func trocar() async {
        guard nova.count >= 10 else { erro = "A senha nova precisa de pelo menos 10 caracteres."; Tato.erro(); return }
        guard nova == confirmacao else { erro = "As duas senhas não são iguais."; Tato.erro(); return }
        enviando = true
        defer { enviando = false }
        do {
            try await sessao.trocarSenha(atual: senhaAtual, nova: nova)
            Tato.sucesso()
        } catch {
            Tato.erro()
            erro = ErroDaAPI(error).mensagem
        }
    }
}

/// A tranca. Aparece ao abrir e ao voltar do fundo, e cobre tudo — inclusive a miniatura
/// do seletor de apps, que de outro jeito mostraria a fila com nomes de pacientes.
struct TrancaView: View {
    @Environment(Sessao.self) private var sessao
    @State private var erro: String?
    @State private var tentando = false

    var body: some View {
        ZStack {
            Cor.azulProfundo.ignoresSafeArea()
            RadialGradient(colors: [Color(hex: 0x2C5170, opacidade: 0.55), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: Espaco.xl) {
                Spacer()
                MarcaAurea(tamanho: 56)
                VStack(spacing: 8) {
                    Text("AUREA Plantão").font(Tipo.tituloDeBloco).foregroundStyle(Cor.textoInvertido)
                    Text("Confirme que é você para ver os pacientes.")
                        .font(Tipo.apoio).foregroundStyle(Cor.textoInvertido.opacity(0.65))
                }
                if let erro {
                    Text(erro).font(Tipo.apoio).foregroundStyle(Cor.textoInvertido)
                        .multilineTextAlignment(.center).padding(.horizontal, Espaco.xl)
                }
                Spacer()
                Button {
                    Task { await destrancar() }
                } label: {
                    Label("Destravar", systemImage: "faceid")
                        .font(Tipo.corpoForte)
                        .foregroundStyle(Cor.azulProfundo)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Cor.textoInvertido, in: RoundedRectangle(cornerRadius: Raio.controle, style: .continuous))
                }
                .buttonStyle(.pressionavel)
                .disabled(tentando)
                .padding(.horizontal, Espaco.margem)
                .padding(.bottom, Espaco.xl)
            }
        }
        .statusBarHidden()
        .task { await destrancar() }
    }

    private func destrancar() async {
        guard !tentando else { return }
        tentando = true
        erro = await sessao.destrancar()
        tentando = false
    }
}
