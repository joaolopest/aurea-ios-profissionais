import Foundation

/// `GET /painel/solicitacoes-de-contato` — conferido com curl em 25/09/2026.
///
/// O envelope traz `aguardando` além de `itens` e `proximoCursor`: o tamanho da fila sem
/// paginar até o fim. A ordem é a mais antiga primeiro — quem esperou mais vem antes.
struct PaginaDeSolicitacoes: Decodable, Sendable {
    let itens: [SolicitacaoDeContato]
    let proximoCursor: String?
    let aguardando: Int
}

struct SolicitacaoDeContato: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    /// 🔴 `solicitadaEm`, não `criadaEm` — foi esse nome que derrubou o `sort` do web.
    let solicitadaEm: Date
    let sessaoId: String?
    let paciente: Paciente

    struct Paciente: Decodable, Sendable, Hashable {
        let id: String
        let nome: String
    }
    // PENDÊNCIA DO BACKEND: `motivo` não é persistido e o telefone não vem aqui.
    // Com o telefone, a linha ganha "Ligar" direto. Pedido ao Prumo.
}

/// Resposta de `POST /painel/solicitacoes-de-contato/:id/atendimento`.
struct SolicitacaoAtendida: Decodable, Sendable {
    let id: String
    let atendidaEm: Date
}
