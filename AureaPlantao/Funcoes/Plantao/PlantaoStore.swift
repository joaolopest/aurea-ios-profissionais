import Foundation
import Observation

@MainActor
@Observable
final class PlantaoStore {
    enum Filtro: Hashable, CaseIterable {
        case precisam, todos, vermelho, amarelo, semResposta, verde

        var nome: String {
            switch self {
            case .precisam: "Precisam de você"
            case .todos: "Todos"
            case .vermelho: "Vermelho"
            case .amarelo: "Amarelo"
            case .semResposta: "Sem resposta"
            case .verde: "Verde"
            }
        }

        var situacao: SituacaoClinica? {
            switch self {
            case .vermelho: .vermelho
            case .amarelo: .amarelo
            case .semResposta: .silencio
            case .verde: .verde
            case .precisam, .todos: nil
            }
        }
    }

    private(set) var carga: Carga<PacientesDoDia> = .carregando
    private(set) var atualizadoEm: Date?
    var filtro: Filtro = .todos

    private let api: ClienteAPI

    init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            let dados: PacientesDoDia = try await api.obter("/painel/pacientes-do-dia")
            carga = .pronto(dados)
            atualizadoEm = .now
            // Primeira carga com gente precisando: abre direto nesse filtro.
            if anterior == nil, dados.cards.contains(where: \.precisaDeAtencao) {
                filtro = .precisam
            }
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    // MARK: Leituras derivadas

    var dados: PacientesDoDia? { carga.valor }

    var precisamDeVoce: Int {
        guard let r = dados?.resumo else { return 0 }
        return r.vermelhos + r.amarelos
    }

    func contagem(_ filtro: Filtro) -> Int {
        guard let d = dados else { return 0 }
        switch filtro {
        case .precisam: return d.resumo.vermelhos + d.resumo.amarelos
        case .todos: return d.resumo.total
        case .vermelho: return d.resumo.vermelhos
        case .amarelo: return d.resumo.amarelos
        case .semResposta: return d.resumo.semResposta
        case .verde: return d.resumo.verdes
        }
    }

    /// A fila na ordem da API — ela já ordena por gravidade (`ordenarFilaDePrioridades`).
    /// O app não reordena: duas ordens diferentes para a mesma fila é o pior defeito possível aqui.
    var fila: [CartaoDoPlantao] {
        guard let cards = dados?.cards else { return [] }
        switch filtro {
        case .todos: return cards
        case .precisam: return cards.filter(\.precisaDeAtencao)
        default: return cards.filter { $0.situacaoClinica == filtro.situacao }
        }
    }
}
