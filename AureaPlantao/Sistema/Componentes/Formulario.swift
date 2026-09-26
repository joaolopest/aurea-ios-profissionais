import SwiftUI

// Formulário no design do app. Todo cadastro, registro e edição usa estes blocos — nada de
// `Form`/`List` nativo (anti-referência do briefing: "cara de Settings.app").

/// A folha de formulário: título, campos, erro e a ação primária presa embaixo.
/// Apresente com `.sheet` + `.presentationDetents([.large])`.
struct FolhaDeFormulario<Campos: View>: View {
    let rotulo: String?
    let titulo: String
    let acao: String
    var icone: String = "checkmark"
    var enviando = false
    var erro: String?
    let enviar: () -> Void
    @ViewBuilder let campos: Campos
    @Environment(\.dismiss) private var fechar

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancelar") { fechar() }
                    .font(Tipo.apoioForte)
                    .foregroundStyle(Cor.textoSuave)
                    .frame(minHeight: 44)
                Spacer()
            }
            .padding(.horizontal, Espaco.xl)
            .padding(.top, Espaco.s)

            ScrollView {
                VStack(alignment: .leading, spacing: Espaco.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let rotulo { Text(rotulo).estiloDeRotulo() }
                        Text(titulo).font(Tipo.titulo).foregroundStyle(Cor.texto)
                    }
                    campos
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
                .padding(Espaco.xl)
                .animation(Movimento.interface, value: erro)
            }
            .scrollDismissesKeyboard(.interactively)

            BotaoPrimario(titulo: acao, icone: icone, carregando: enviando, acao: enviar)
                .padding(.horizontal, Espaco.xl)
                .padding(.bottom, Espaco.l)
        }
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
    }
}

/// Texto longo (descrição, conduta, orientação).
struct CampoDeTextoLongo: View {
    let rotulo: String
    @Binding var texto: String
    var dica = ""
    var linhas = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rotulo).estiloDeRotulo().accessibilityHidden(true)
            TextField(dica, text: $texto, axis: .vertical)
                .lineLimit(linhas...(linhas + 6))
                .font(Tipo.corpo)
                .foregroundStyle(Cor.texto)
                .accessibilityLabel(rotulo)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficie(.afundado, raio: Raio.controle)
        }
    }
}

/// Escolha entre opções fechadas (enum da API). Menu nativo, casca do app.
struct CampoDeEscolha<Valor: Hashable>: View {
    let rotulo: String
    let opcoes: [(valor: Valor, nome: String)]
    @Binding var selecionado: Valor?
    var dica = "Escolher"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rotulo).estiloDeRotulo().accessibilityHidden(true)
            Menu {
                ForEach(opcoes, id: \.valor) { opcao in
                    Button {
                        Tato.selecao()
                        selecionado = opcao.valor
                    } label: {
                        if selecionado == opcao.valor {
                            Label(opcao.nome, systemImage: "checkmark")
                        } else {
                            Text(opcao.nome)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(opcoes.first { $0.valor == selecionado }?.nome ?? dica)
                        .font(Tipo.corpo)
                        .foregroundStyle(selecionado == nil ? Cor.textoFraco : Cor.texto)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Cor.textoFraco)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .superficie(.afundado, raio: Raio.controle)
                .contentShape(.rect)
            }
            .accessibilityLabel("\(rotulo): \(opcoes.first { $0.valor == selecionado }?.nome ?? "não escolhido")")
        }
    }
}

/// Data (e hora, se pedir). Sempre em pt_BR.
struct CampoDeData: View {
    let rotulo: String
    @Binding var data: Date
    var comHora = false
    var intervalo: ClosedRange<Date>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rotulo).estiloDeRotulo().accessibilityHidden(true)
            HStack {
                Group {
                    if let intervalo {
                        DatePicker(rotulo, selection: $data, in: intervalo,
                                   displayedComponents: comHora ? [.date, .hourAndMinute] : [.date])
                    } else {
                        DatePicker(rotulo, selection: $data,
                                   displayedComponents: comHora ? [.date, .hourAndMinute] : [.date])
                    }
                }
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .tint(Cor.azulProfundo)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .superficie(.afundado, raio: Raio.controle)
        }
    }
}

/// Liga/desliga com explicação.
struct CampoInterruptor: View {
    let titulo: String
    var explicacao: String?
    @Binding var ligado: Bool

    var body: some View {
        Toggle(isOn: $ligado) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(Tipo.apoioForte).foregroundStyle(Cor.texto)
                if let explicacao {
                    Text(explicacao).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
            }
        }
        .tint(Cor.azulProfundo)
        .padding(14)
        .superficie(raio: Raio.controle)
        .onChange(of: ligado) { _, _ in Tato.selecao() }
    }
}

/// Número (dose, ciclo, dias).
struct CampoNumerico: View {
    let rotulo: String
    @Binding var valor: Int
    var faixa: ClosedRange<Int> = 0...999
    var unidade: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rotulo).estiloDeRotulo().accessibilityHidden(true)
            HStack {
                Text("\(valor)\(unidade.map { " \($0)" } ?? "")")
                    .font(Tipo.corpoForte)
                    .monospacedDigit()
                    .foregroundStyle(Cor.texto)
                    .contentTransition(.numericText(value: Double(valor)))
                Spacer()
                Stepper(rotulo, value: $valor, in: faixa)
                    .labelsHidden()
                    .onChange(of: valor) { _, _ in Tato.selecao() }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .superficie(.afundado, raio: Raio.controle)
        }
        .animation(Movimento.toque, value: valor)
    }
}

/// Botão de ação em linha, discreto (ex.: "+ Registrar barreira"), no topo de uma seção.
struct BotaoDeAcaoEmLinha: View {
    let titulo: String
    var icone = "plus"
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
    }
}

/// Aviso de sucesso que aparece e some sozinho (toast), no topo da tela.
struct AvisoTemporario: ViewModifier {
    @Binding var mensagem: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let mensagem {
                Label(mensagem, systemImage: "checkmark.circle.fill")
                    .font(Tipo.apoioForte)
                    .foregroundStyle(Cor.textoInvertido)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Cor.azulProfundo).shadow(color: Cor.sombraAzul, radius: 12, y: 6))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: mensagem) {
                        try? await Task.sleep(for: .seconds(2.4))
                        withAnimation(Movimento.partida) { self.mensagem = nil }
                    }
            }
        }
        .animation(Movimento.chegada, value: mensagem)
    }
}

extension View {
    func avisoTemporario(_ mensagem: Binding<String?>) -> some View {
        modifier(AvisoTemporario(mensagem: mensagem))
    }
}
