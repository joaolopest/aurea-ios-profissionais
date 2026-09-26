import SwiftUI

/// A conta, no mínimo que o plantão pede: quem está logado, o que pode fazer, e sair.
struct ContaView: View {
    @Environment(Sessao.self) private var sessao
    @Environment(\.dismiss) private var fechar
    @State private var saindo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.xl) {
            HStack(spacing: 14) {
                Iniciais(nome: sessao.eu?.perfilDetalhado?.nome ?? "AUREA", tamanho: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessao.eu?.perfilDetalhado?.nome ?? "—").font(Tipo.tituloDeBloco).foregroundStyle(Cor.texto)
                    Text(sessao.eu?.funcaoPorExtenso ?? "").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
            }

            if let permissoes = sessao.eu?.permissoes, !permissoes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CabecalhoDeSecao(titulo: "Este acesso pode")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(permissoes, id: \.self) { p in
                            Label(nome(da: p), systemImage: "checkmark")
                                .font(Tipo.apoio)
                                .foregroundStyle(Cor.texto)
                        }
                    }
                    .padding(Espaco.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficie()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Cada prontuário aberto fica registrado, como no computador do posto.", systemImage: "lock.doc")
                if Sessao.trancaBiometricaLigada {
                    Label("O app pede Face ID ao abrir e ao voltar do fundo.", systemImage: "faceid")
                }
            }
            .font(Tipo.apoio)
            .foregroundStyle(Cor.textoSuave)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                saindo = true
                Task {
                    await sessao.sair()
                    fechar()
                }
            } label: {
                Text(saindo ? "Saindo…" : "Sair deste iPhone")
                    .font(Tipo.corpoForte)
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .superficie(raio: Raio.controle)
            }
            .buttonStyle(.pressionavel)
            .disabled(saindo)
        }
        .padding(Espaco.xl)
        .padding(.top, Espaco.s)
    }

    private func nome(da permissao: String) -> String {
        switch permissao {
        case "ATENDER_PLANTAO": "Atender o plantão e os pedidos de contato"
        case "VER_HISTORICO_DE_PACIENTE": "Abrir o prontuário dos pacientes"
        case "REGISTRAR_INTERVENCAO": "Registrar condutas"
        default: permissao.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
