import Foundation

/// As chamadas de ESCRITA do admin (criar conjunto, publicar, validar) e a exportação bruta.
///
/// Por que não passam pelo `ClienteAPI`: a API do AUREA responde erro como
/// `{"erro": "...", "detalhes": [...]}`, e o `ClienteAPI` só lê `message`/`mensagem` — a
/// frase escrita para gente ler se perde e sobra "O AUREA recusou o pedido (403)". Aqui isso
/// é inaceitável: "Só profissional de saúde assina validação clínica" e "campo X não existe
/// em FEBRE" são exatamente o que quem mexe no algoritmo precisa ler. (A correção certa é no
/// `ClienteAPI`, compartilhado; está descrita no relatório. Enquanto não vem, este desvio
/// fica restrito às chamadas do admin.)
///
/// Mesmo token, mesma base, mesma sessão efêmera sem cache, mesma tradução para `ErroDaAPI`.
struct ChamadaDoAdmin: Sendable {
    static let compartilhada = ChamadaDoAdmin()

    private let sessao: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func enviar<T: Decodable & Sendable, C: Encodable & Sendable>(_ caminho: String, corpo: C) async throws -> T {
        let dados = try await chamar(caminho, metodo: "POST", consulta: [], corpo: try JSONEncoder().encode(corpo))
        return try decodificar(dados, caminho: caminho)
    }

    /// POST sem corpo (publicar, validar): a rota lê só o `:id`.
    func acionar<T: Decodable & Sendable>(_ caminho: String) async throws -> T {
        let dados = try await chamar(caminho, metodo: "POST", consulta: [], corpo: Data("{}".utf8))
        return try decodificar(dados, caminho: caminho)
    }

    /// GET que devolve os bytes crus — a exportação de pesquisa sai do jeito que o servidor
    /// montou, sem passar por um modelo que poderia descartar campo.
    func bruto(_ caminho: String, consulta: [URLQueryItem] = []) async throws -> Data {
        try await chamar(caminho, metodo: "GET", consulta: consulta, corpo: nil)
    }

    private func decodificar<T: Decodable>(_ dados: Data, caminho: String) throws -> T {
        do {
            return try ClienteAPI.decodificador.decode(T.self, from: dados)
        } catch {
            print("🔴 [ChamadaDoAdmin] \(caminho) — formato inesperado: \(error)")
            throw ErroDaAPI.formatoInesperado(String(describing: error))
        }
    }

    private func chamar(_ caminho: String, metodo: String, consulta: [URLQueryItem], corpo: Data?) async throws -> Data {
        var componentes = URLComponents(url: ClienteAPI.compartilhado.base.appending(path: caminho), resolvingAgainstBaseURL: false)!
        if !consulta.isEmpty { componentes.queryItems = consulta }

        var pedido = URLRequest(url: componentes.url!)
        pedido.httpMethod = metodo
        pedido.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = GuardaDeToken.compartilhado.ler() {
            pedido.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let corpo {
            pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
            pedido.httpBody = corpo
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
            return dados
        case 401:
            throw ErroDaAPI.sessaoEncerrada
        case 403:
            throw ErroDaAPI.recusado(Self.mensagem(em: dados) ?? "Seu acesso não inclui esta operação.")
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

    /// `erro` é a frase; `detalhes` vem em dois formatos: lista de frases (integridade do
    /// conjunto, 422) ou lista de problemas do Zod (`{path, message}`, 400). As duas viram
    /// linhas embaixo da frase — o problema de integridade É a informação.
    static func mensagem(em dados: Data) -> String? {
        guard let objeto = try? JSONSerialization.jsonObject(with: dados) as? [String: Any] else { return nil }
        let frase = (objeto["erro"] ?? objeto["mensagem"] ?? objeto["message"]) as? String
        var linhas: [String] = []
        if let detalhes = objeto["detalhes"] as? [Any] {
            for item in detalhes {
                if let texto = item as? String {
                    linhas.append(texto)
                } else if let problema = item as? [String: Any] {
                    let caminho = (problema["path"] as? [Any])?.map { "\($0)" }.joined(separator: ".") ?? ""
                    linhas.append(caminho.isEmpty ? "Um campo foi recusado." : "Campo “\(NomesDoAlgoritmo.campoDoFormulario(caminho))” recusado.")
                }
            }
        }
        guard let frase else { return linhas.isEmpty ? nil : linhas.joined(separator: "\n") }
        return linhas.isEmpty ? frase : ([frase] + linhas.map { "• \($0)" }).joined(separator: "\n")
    }
}
