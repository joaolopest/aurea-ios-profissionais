import SwiftUI

/// Estado do conjunto. É estado ADMINISTRATIVO, então não chega perto das cores clínicas:
/// publicado é a pílula azul profunda (o que está valendo), rascunho é contorno, arquivado recua.
struct SeloDeEstadoDoConjunto: View {
    let estado: EstadoDoConjunto

    var body: some View {
        Text(estado.nome)
            .font(Tipo.rotulo)
            .tracking(Tipo.trackingDeRotulo)
            .textCase(.uppercase)
            .foregroundStyle(estado == .publicado ? Cor.textoInvertido : (estado == .rascunho ? Cor.textoSuave : Cor.textoFraco))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if estado == .publicado {
                    Capsule().fill(Cor.azulProfundo)
                } else {
                    Capsule().strokeBorder(estado == .rascunho ? Cor.fileteForte : Cor.filete, lineWidth: 1)
                }
            }
            .fixedSize()
            .accessibilityLabel("Estado: \(estado.nome)")
    }
}

/// Aviso em bloco, na casca afundada. `grave` só muda o ícone e o peso — a cor de alerta
/// é faixa clínica e não serve para aviso de sistema.
struct AvisoDoAdmin: View {
    var titulo: String?
    let texto: String
    var grave = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: grave ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(grave ? Cor.texto : Cor.azulProfundo)
            VStack(alignment: .leading, spacing: 4) {
                if let titulo {
                    Text(titulo).font(Tipo.apoioForte).foregroundStyle(Cor.texto)
                }
                Text(texto)
                    .font(Tipo.apoio)
                    .foregroundStyle(grave ? Cor.texto : Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(.afundado, raio: Raio.linha)
        .accessibilityElement(children: .combine)
    }
}

/// Grade de indicadores em duas colunas — a fileira de quatro do web, dobrada para o polegar.
struct GradeDeIndicadoresDoAdmin<Conteudo: View>: View {
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Espaco.s), GridItem(.flexible(), spacing: Espaco.s)],
                  alignment: .leading, spacing: Espaco.s) {
            conteudo
        }
    }
}

/// Uma regra de corte, inteira: a cor que ela produz (pelo selo clínico — é classificação de
/// paciente, o único lugar legítimo dessa cor aqui), a regra por extenso e a justificativa
/// sem corte. Justificativa truncada é corte indefensável em auditoria.
struct CartaoDeRegra: View {
    let regra: RegraDoConjunto

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Selo em cima, frase embaixo: lado a lado, a frase ficava com meia largura.
            VStack(alignment: .leading, spacing: 8) {
                if let situacao = regra.classificacao.situacao {
                    SeloClinico(situacao: situacao)
                } else {
                    Text(regra.classificacao.nome).font(Tipo.rotulo).foregroundStyle(Cor.textoSuave)
                }
                Text(NomesDoAlgoritmo.frase(regra))
                    .font(Tipo.corpoForte)
                    .foregroundStyle(Cor.texto)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(regra.justificativa)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
            Text("Campo \(regra.campo) · ordem \(regra.ordem)")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoFraco)
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(regra.classificacao.nome) quando \(NomesDoAlgoritmo.frase(regra)). Justificativa: \(regra.justificativa)")
    }
}

extension View {
    /// Tela empurrada numa pilha de aba: barra de navegação só com o "voltar", transparente
    /// sobre o fundo vivo — o mesmo acabamento do prontuário.
    func telaEmpurradaDoAdmin() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .containerBackground(.clear, for: .navigation)
    }
}
