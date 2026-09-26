import SwiftUI

/// "Mais": as telas que não cabem na barra, em cartões com a explicação de cada uma.
/// A lista sai das permissões — ninguém vê destino que a API recusaria.
struct MaisView: View {
    let destinos: [Destino]

    var body: some View {
        TelaDeAba {
            CabecalhoDeTela(rotulo: "Tudo o que você acessa", titulo: "Mais", mostrarConta: true)
            if destinos.isEmpty {
                EstadoVazio(titulo: "Nada além das abas.", texto: "Seu acesso cobre só o que está na barra.", icone: "ellipsis")
                    .superficie()
            }
            VStack(spacing: Espaco.s) {
                ForEach(Array(destinos.enumerated()), id: \.element) { i, destino in
                    NavigationLink(value: destino) {
                        LinhaPadrao(icone: destino.icone, titulo: destino.nome, apoio: destino.descricao)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
            // Dentro da pilha da aba — fora dela o link não teria para onde empurrar.
            .navigationDestination(for: Destino.self) { telaSecundaria($0) }
        }
    }
}

/// As telas secundárias, empurradas a partir do "Mais". Não criam NavigationStack próprio.
@ViewBuilder
func telaSecundaria(_ destino: Destino) -> some View {
    switch destino {
    case .intervencoes: IntervencoesView()
    case .cadeiras: CadeirasView()
    case .toxicidade: ToxicidadeView()
    case .navegacao: NavegacaoView()
    case .orientacoes: OrientacoesView()
    case .protocolos: ProtocolosView()
    case .medicamentos: MedicamentosView()
    case .equipe: EquipeView()
    case .acessos: AcessosView()
    case .pesquisa: PesquisaView()
    default: EmConstrucao(destino: destino)
    }
}
