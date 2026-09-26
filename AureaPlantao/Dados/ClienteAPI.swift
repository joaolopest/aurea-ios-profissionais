import Foundation

/// Erro da API, já traduzido para o que a tela precisa decidir.
enum ErroDaAPI: Error, Equatable {
    /// 401 — a sessão acabou (expirou, foi revogada, a senha foi trocada em outro lugar).
    case sessaoEncerrada
    /// 409 — a ação já foi feita por outra pessoa. É o caso NORMAL de dois plantonistas no
    /// mesmo pedido, não uma falha.
    case conflito(String)
    /// 429 — muitas tentativas de entrada.
    case bloqueado(String)
    /// Outro 4xx com mensagem da API, que é escrita para gente ler.
    case recusado(String)
    /// Sem rede, servidor fora, tempo esgotado.
    case semConexao
    /// A resposta não tem o formato esperado. Nunca silencioso: aparece e fica no console.
    case formatoInesperado(String)
    case servidor(Int)

    /// Texto para a tela. Direto, sem "Algo deu errado".
    var mensagem: String {
        switch self {
        case .sessaoEncerrada: "Sua sessão terminou. Entre de novo."
        case .conflito(let m), .bloqueado(let m), .recusado(let m): m
        case .semConexao: "Sem conexão com o AUREA. Confira a rede do hospital e puxe para tentar de novo."
        case .formatoInesperado: "O AUREA respondeu num formato que este app não conhece. Avise a equipe de sistemas."
        case .servidor(let codigo): "O servidor do AUREA falhou (\(codigo)). Tente de novo em instantes."
        }
    }
}

/// Cliente REST da API Fastify do AUREA. Token opaco no `Authorization: Bearer`.
///
/// Sem cache em disco: `URLCache` desligado e `ephemeral`. Prontuário oncológico não fica
/// guardado no aparelho — o que está na tela vive só na memória.
final class ClienteAPI: Sendable {
    static let compartilhado = ClienteAPI()

    let base: URL
    private let sessao: URLSession
    private let token: GuardaDeToken

    init(token: GuardaDeToken = .compartilhado) {
        let endereco = Bundle.main.object(forInfoDictionaryKey: "EnderecoDaAPI") as? String ?? "http://localhost:3333"
        base = URL(string: endereco)!
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        sessao = URLSession(configuration: config)
        self.token = token
    }

    // MARK: Chamadas

    func obter<T: Decodable & Sendable>(_ caminho: String, consulta: [URLQueryItem] = []) async throws -> T {
        try await chamar(caminho, metodo: "GET", consulta: consulta, corpo: Optional<Vazio>.none)
    }

    func enviar<T: Decodable & Sendable, C: Encodable & Sendable>(_ caminho: String, corpo: C) async throws -> T {
        try await chamar(caminho, metodo: "POST", consulta: [], corpo: corpo)
    }

    func enviarSemResposta<C: Encodable & Sendable>(_ caminho: String, corpo: C) async throws {
        let _: Vazio = try await chamar(caminho, metodo: "POST", consulta: [], corpo: corpo)
    }

    private func chamar<T: Decodable & Sendable, C: Encodable & Sendable>(
        _ caminho: String, metodo: String, consulta: [URLQueryItem], corpo: C?
    ) async throws -> T {
        var componentes = URLComponents(url: base.appending(path: caminho), resolvingAgainstBaseURL: false)!
        if !consulta.isEmpty { componentes.queryItems = consulta }

        var pedido = URLRequest(url: componentes.url!)
        pedido.httpMethod = metodo
        pedido.setValue("application/json", forHTTPHeaderField: "Accept")
        if let valor = token.ler() {
            pedido.setValue("Bearer \(valor)", forHTTPHeaderField: "Authorization")
        }
        if let corpo {
            pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
            pedido.httpBody = try JSONEncoder().encode(corpo)
        }

        let dados: Data
        let resposta: URLResponse
        do {
            (dados, resposta) = try await sessao.data(for: pedido)
        } catch {
            throw ErroDaAPI.semConexao
        }

        let codigo = (resposta as? HTTPURLResponse)?.statusCode ?? 0

        switch codigo {
        case 200..<300:
            if T.self == Vazio.self || dados.isEmpty, let vazio = Vazio() as? T { return vazio }
            do {
                return try Self.decodificador.decode(T.self, from: dados)
            } catch {
                // Nunca engolir: é aqui que um campo renomeado na API aparece.
                print("🔴 [ClienteAPI] \(metodo) \(caminho) — formato inesperado: \(error)")
                throw ErroDaAPI.formatoInesperado(String(describing: error))
            }
        case 401:
            throw ErroDaAPI.sessaoEncerrada
        case 409:
            throw ErroDaAPI.conflito(Self.mensagem(em: dados) ?? "Isto já foi feito por outra pessoa.")
        case 429:
            throw ErroDaAPI.bloqueado(Self.mensagem(em: dados) ?? "Muitas tentativas. Espere alguns minutos.")
        case 400..<500:
            throw ErroDaAPI.recusado(Self.mensagem(em: dados) ?? "O AUREA recusou o pedido (\(codigo)).")
        default:
            throw ErroDaAPI.servidor(codigo)
        }
    }

    private static func mensagem(em dados: Data) -> String? {
        struct Corpo: Decodable { let message: String?; let mensagem: String? }
        guard let c = try? JSONDecoder().decode(Corpo.self, from: dados) else { return nil }
        return c.mensagem ?? c.message
    }

    /// Datas da API: ISO 8601 com milissegundos (`2026-09-25T20:46:03.324Z`).
    static let decodificador: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let texto = try decoder.singleValueContainer().decode(String.self)
            if let data = try? Date(texto, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) {
                return data
            }
            if let data = try? Date(texto, strategy: .iso8601) { return data }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Data fora do ISO 8601: \(texto)"))
        }
        return d
    }()
}

/// Resposta sem corpo (204) ou corpo ignorado.
struct Vazio: Codable, Sendable {}
