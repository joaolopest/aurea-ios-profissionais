import SwiftUI

// MARK: - Selo clínico

/// O selo de situação: ponto + nome, com fundo tintado. Nunca só a cor — o nome vai junto
/// (daltonismo, VoiceOver, luz ruim de enfermaria).
struct SeloClinico: View {
    let situacao: SituacaoClinica

    var body: some View {
        let tons = Faixa.tons(situacao)
        HStack(spacing: 6) {
            Circle().fill(tons.tinta).frame(width: 7, height: 7)
            Text(situacao.nome)
                .font(Tipo.rotulo)
                .tracking(0.4)
                .foregroundStyle(tons.tinta)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tons.fundo, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Situação: \(situacao.nome)")
    }
}

// MARK: - Aviso de validação clínica

/// Decisão travada do produto: sem validação clínica assinada, a interface é OBRIGADA a
/// dizer "não validado clinicamente". Não é rodapé jurídico; é informação de leitura.
struct AvisoNaoValidado: View {
    var versao: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
            Text(texto)
                .font(Tipo.apoio)
        }
        .foregroundStyle(Cor.textoSuave)
        .accessibilityElement(children: .combine)
    }

    private var texto: String {
        if let versao { return "Regras \(versao) · não validadas clinicamente" }
        return "Regras não validadas clinicamente"
    }
}

// MARK: - Botão primário

/// CTA principal: pílula azul profundo com texto claro (a pílula lima do BT, trocada por
/// azul — lima é lido como verde, e verde é faixa clínica). Um só desenho no app inteiro.
/// Luz interna no topo, na família clara do próprio azul, e sombra tingida.
struct BotaoPrimario: View {
    let titulo: String
    var icone: String?
    var carregando = false
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 8) {
                if carregando {
                    ProgressView().tint(Cor.textoInvertido)
                } else {
                    if let icone { Image(systemName: icone).font(.system(size: 15, weight: .bold)) }
                    Text(titulo).font(Tipo.corpoForte)
                }
            }
            .foregroundStyle(Cor.textoInvertido)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x173A55), Cor.azulProfundo],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Capsule().strokeBorder(
                            LinearGradient(colors: [Color(hex: 0xB4D6F0, opacidade: 0.35), .clear],
                                           startPoint: .top, endPoint: .center),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: Cor.sombraAzul, radius: 14, y: 8)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressionavel)
        .disabled(carregando)
    }
}

/// Ação secundária: contorno, sem preenchimento. Nunca compete com o primário.
struct BotaoSecundario: View {
    let titulo: String
    var icone: String?
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 8) {
                if let icone { Image(systemName: icone).font(.system(size: 14, weight: .semibold)) }
                Text(titulo).font(Tipo.corpoForte)
            }
            .foregroundStyle(Cor.texto)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(Cor.superficie))
            .overlay(Capsule().strokeBorder(Cor.fileteForte, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressionavel)
    }
}

// MARK: - Seletor em pílulas

/// Opção de um seletor: rótulo, contador e — só quando a opção É uma faixa clínica —
/// o ponto da faixa. A cor clínica nunca vira fundo de pílula; ela fica no ponto.
struct OpcaoDeSeletor<ID: Hashable>: Identifiable {
    let id: ID
    let titulo: String
    var contador: Int?
    var faixa: SituacaoClinica?
}

/// Pílulas em trilho, com a ativa em azul deslizando entre elas (matched geometry).
/// O `Picker(.segmented)` nativo não aceita contador, não anima e usa o cinza do sistema.
struct SeletorDePilulas<ID: Hashable>: View {
    let opcoes: [OpcaoDeSeletor<ID>]
    @Binding var selecionado: ID
    @Namespace private var pilula
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(opcoes) { opcao in item(opcao) }
            }
            .padding(4)
            .background(Capsule().fill(Cor.superficie.opacity(0.75)))
            .overlay(Capsule().strokeBorder(Cor.filete, lineWidth: 0.75))
            .padding(.horizontal, Espaco.margem)
        }
        .scrollIndicators(.hidden)
        .fadeArestaDireita()
    }

    private func item(_ opcao: OpcaoDeSeletor<ID>) -> some View {
        let ativo = selecionado == opcao.id
        return Button {
            guard !ativo else { return }
            Tato.selecao()
            withAnimation(reduzirMovimento ? .easeOut(duration: 0.15) : Movimento.interface) {
                selecionado = opcao.id
            }
        } label: {
            HStack(spacing: 7) {
                if let faixa = opcao.faixa {
                    Circle().fill(Faixa.tons(faixa).tinta).frame(width: 7, height: 7)
                }
                Text(opcao.titulo)
                    .font(ativo ? Tipo.apoioForte : Tipo.apoio)
                    .fixedSize()
                if let n = opcao.contador {
                    Text("\(n)")
                        .font(.custom("Plus Jakarta Sans", size: 11, relativeTo: .caption).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(ativo ? Cor.azulProfundo : Cor.textoSuave)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(ativo ? Cor.azulGelo : Cor.fundoBaixo))
                        // Zero é informação de fundo: fica, mas recua.
                        .opacity(n == 0 && !ativo ? 0.55 : 1)
                }
            }
            .foregroundStyle(ativo ? Cor.textoInvertido : Cor.textoSuave)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background {
                if ativo {
                    Capsule()
                        .fill(Cor.azulProfundo)
                        .shadow(color: Cor.sombraAzul, radius: 6, y: 3)
                        .matchedGeometryEffect(id: "pilulaAtiva", in: pilula)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(opcao.contador.map { "\(opcao.titulo), \($0)" } ?? opcao.titulo)
        .accessibilityAddTraits(ativo ? [.isSelected, .isButton] : .isButton)
    }
}

extension View {
    /// Esmaece a borda direita de um trilho horizontal: o corte seco no meio da palavra
    /// lê como layout quebrado; o esmaecido diz "tem mais pro lado".
    func fadeArestaDireita(_ largura: CGFloat = 56) -> some View {
        mask {
            GeometryReader { geo in
                let fracao = min(0.4, largura / max(geo.size.width, 1))
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 1 - fracao),
                                       .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
    }
}

// MARK: - Campo

struct CampoDeEntrada: View {
    let rotulo: String
    @Binding var texto: String
    var seguro = false
    var teclado: UIKeyboardType = .default
    var conteudo: UITextContentType?
    /// Maiúscula automática: `.never` para e-mail e senha; `.words` para nome; `.sentences` para texto.
    var maiusculas: TextInputAutocapitalization = .never
    /// Corretor ortográfico: desligado por padrão (e-mail, CPF, código); ligar em texto livre.
    var corrigir = false
    var botaoDoTeclado: SubmitLabel = .next
    var aoEnviar: (() -> Void)?

    @FocusState private var focado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rotulo).estiloDeRotulo().accessibilityHidden(true)
            Group {
                if seguro {
                    SecureField("", text: $texto)
                } else {
                    TextField("", text: $texto)
                        .keyboardType(teclado)
                        .textInputAutocapitalization(maiusculas)
                        .autocorrectionDisabled(!corrigir)
                }
            }
            .textContentType(conteudo)
            .submitLabel(botaoDoTeclado)
            .onSubmit { aoEnviar?() }
            .font(Tipo.corpo)
            .foregroundStyle(Cor.texto)
            .focused($focado)
            // O rótulo visível fica fora do campo; sem isto o VoiceOver acha um campo sem nome.
            .accessibilityLabel(rotulo)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .superficie(.afundado, raio: Raio.controle)
            // A caixa inteira foca, não só a linha do texto (22 de 52 pt respondiam ao toque).
            .contentShape(RoundedRectangle(cornerRadius: Raio.controle, style: .continuous))
            .onTapGesture { focado = true }
            .overlay {
                RoundedRectangle(cornerRadius: Raio.controle, style: .continuous)
                    .strokeBorder(Cor.azulProfundo.opacity(focado ? 0.55 : 0), lineWidth: 1.5)
                    .animation(Movimento.toque, value: focado)
            }
        }
    }
}

// MARK: - Esqueleto

/// Carregamento com a forma do conteúdo real. Spinner sozinho diz "espera"; esqueleto
/// diz "vem aí uma fila" — e a tela não pula quando os dados chegam.
struct Esqueleto: View {
    var largura: CGFloat? = nil
    var altura: CGFloat = 12
    @State private var fase = false
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    var body: some View {
        RoundedRectangle(cornerRadius: altura / 2, style: .continuous)
            .fill(Cor.fundoBaixo)
            .frame(width: largura, height: altura)
            .opacity(reduzirMovimento ? 1 : (fase ? 0.55 : 1))
            .animation(reduzirMovimento ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: fase)
            .onAppear { fase = true }
            .accessibilityHidden(true)
    }
}

// MARK: - Estado vazio e erro

/// Vazio com cara. No plantão, fila vazia é boa notícia — não é erro, não leva tracejado.
struct EstadoVazio: View {
    let titulo: String
    let texto: String
    var icone = "checkmark"

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icone)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Cor.azulProfundo)
                .frame(width: 52, height: 52)
                .superficie(.afundado, raio: 26)
            VStack(spacing: 6) {
                Text(titulo).font(Tipo.tituloDeBloco).foregroundStyle(Cor.texto)
                Text(texto)
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

struct CartaoDeErro: View {
    let erro: ErroDaAPI
    let tentarDeNovo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(erro.mensagem).font(Tipo.apoio).foregroundStyle(Cor.texto)
            } icon: {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(Cor.textoSuave)
            }
            Button("Tentar de novo", action: tentarDeNovo)
                .font(Tipo.apoioForte)
                .foregroundStyle(Cor.azulProfundo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Espaco.l)
        .superficie()
    }
}

// MARK: - Cabeçalho de seção

struct CabecalhoDeSecao: View {
    let titulo: String
    var contagem: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titulo).estiloDeRotulo()
            if let contagem {
                Text("\(contagem)")
                    .font(Tipo.rotulo)
                    .monospacedDigit()
                    .foregroundStyle(Cor.textoFraco)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Avatar de iniciais

struct Iniciais: View {
    let nome: String
    var tamanho: CGFloat = 40

    var body: some View {
        Text(iniciais)
            .font(.custom("Plus Jakarta Sans", size: tamanho * 0.36).weight(.bold))
            .foregroundStyle(Cor.azulProfundo)
            .frame(width: tamanho, height: tamanho)
            .background {
                // Sem cor por pessoa: avatar colorido é decoração, e aqui cor é faixa clínica.
                // A vida vem da luz — gradiente do azul da marca, claro no topo.
                Circle().fill(LinearGradient(colors: [Color(hex: 0xE9EFF3), Color(hex: 0xD5DFE7)],
                                             startPoint: .top, endPoint: .bottom))
            }
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.1)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var iniciais: String {
        let partes = nome
            .replacingOccurrences(of: "(fictício)", with: "")
            .replacingOccurrences(of: "(fictícia)", with: "")
            .split(separator: " ")
            .filter { $0.first?.isUppercase == true }
        let letras = [partes.first, partes.dropFirst().last].compactMap { $0?.first }
        return String(letras).uppercased()
    }
}
