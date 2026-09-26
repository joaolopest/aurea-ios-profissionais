import SwiftUI

@MainActor
@Observable
final class CadeirasStore {
    private(set) var carga: Carga<PainelDeCadeiras> = .carregando
    /// Quando o retrato chegou. É o "atualizado há 20 s" do painel ao vivo.
    private(set) var atualizadoEm: Date?
    /// Pacientes em tratamento, para agendar. Carrega só quando a folha de agendar abre.
    private(set) var pacientes: [PacienteDaLista]?
    private var previsoes: [String: PrevisaoDeOcupacao] = [:]
    private let api: ClienteAPI

    /// `nonisolated`: a tela é criada pelo `telaSecundaria(_:)` do "Mais", que não é
    /// isolado no MainActor. Só guarda referências; nada aqui toca a interface.
    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    // MARK: Leitura

    func carregar() async {
        let anterior = carga.valor
        do {
            let painel: PainelDeCadeiras = try await api.obter("/painel/cadeiras")
            carga = .pronto(painel)
            atualizadoEm = .now
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    /// Painel de sala recarrega sozinho, como no web: quem está no corredor não volta na
    /// tela para apertar atualizar. Um minuto é o intervalo em que um estado muda de verdade.
    /// Vive no `.task` da tela — sai da tela, o relógio para.
    func manterAoVivo() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { return }
            await carregar()
        }
    }

    func carregarPacientes() async {
        guard pacientes == nil else { return }
        do {
            let pagina: PaginaDePacientes = try await api.obter("/painel/pacientes")
            // Só quem está em tratamento: sem protocolo ativo a API recusa a previsão e o agendamento.
            pacientes = pagina.itens.filter(\.emTratamento)
        } catch {
            pacientes = []
        }
    }

    /// A previsão não grava nada — é simulação. Guardada em memória porque a mesma
    /// pessoa é consultada várias vezes na mesma folha.
    func previsao(de pacienteId: String) async throws -> PrevisaoDeOcupacao {
        if let pronta = previsoes[pacienteId] { return pronta }
        let nova: PrevisaoDeOcupacao = try await api.obter("/painel/cadeiras/previsao/\(pacienteId)")
        previsoes[pacienteId] = nova
        return nova
    }

    // MARK: Escrita — toda escrita é conferida lendo o painel de volta

    enum Resultado: Equatable { case feito(String), falhou(String) }

    func cadastrarCadeira(numero: Int, observacao: String) async -> Resultado {
        struct Corpo: Encodable, Sendable { let numero: Int; let observacao: String? }
        let texto = observacao.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // Observação vazia a API recusa (min 1): vai sem o campo.
            let gravada: CadeiraGravada = try await api.enviar(
                "/painel/cadeiras", corpo: Corpo(numero: numero, observacao: texto.isEmpty ? nil : String(texto.prefix(180)))
            )
            await carregar()
            guard carga.valor?.giro.porCadeira.contains(where: { $0.cadeira.id == gravada.id }) == true else {
                return .falhou("A API respondeu, mas a cadeira \(numero) não apareceu no painel. Puxe para atualizar antes de tentar de novo.")
            }
            return .feito("Cadeira \(numero) no painel")
        } catch {
            return .falhou(MensagemDoGiro.de(ErroDaAPI(error), contexto: "Não foi possível cadastrar a cadeira \(numero). Confira o número (1 a 999)."))
        }
    }

    func agendar(pacienteId: String, cadeiraId: String?, inicio: Date) async -> Resultado {
        struct Corpo: Encodable, Sendable { let pacienteId: String; let cadeiraId: String?; let previsaoDeInicio: String }
        do {
            // Data como TEXTO ISO: o JSONEncoder padrão mandaria segundos desde 2001, e a
            // API (`z.coerce.date`) aceitaria o número como outra data sem reclamar.
            let gravada: SessaoGravada = try await api.enviar(
                "/painel/cadeiras/sessoes",
                corpo: Corpo(pacienteId: pacienteId, cadeiraId: cadeiraId, previsaoDeInicio: inicio.ISO8601Format())
            )
            await carregar()
            guard let painel = carga.valor else {
                return .falhou("A sessão foi enviada, mas o painel não recarregou. Puxe para conferir.")
            }
            guard painel.sessoesDoDia.contains(where: { $0.id == gravada.id }) else {
                // A API grava qualquer horário, mas o painel só lê o expediente de hoje.
                return .falhou("A sessão foi gravada, mas fica fora do expediente de hoje e não aparece no painel.")
            }
            return .feito("Sessão agendada · cadeira livre às \(Formato.hora(gravada.previsaoDeFim))")
        } catch {
            return .falhou(MensagemDoGiro.de(ErroDaAPI(error), contexto: "Não foi possível agendar. Confira se o paciente tem tratamento ativo."))
        }
    }

    /// Muda o estado da sessão. Início e fim reais são carimbados pelo SERVIDOR — o app
    /// nunca manda horário, porque atraso que o cliente escolhe não é medição.
    func mudar(_ sessao: SessaoDeCadeira, para estado: EstadoDaSessao, cadeiraId: String? = nil) async -> Resultado {
        struct Corpo: Encodable, Sendable { let estado: String; let cadeiraId: String? }
        do {
            let _: SessaoGravada = try await api.atualizar(
                "/painel/cadeiras/sessoes/\(sessao.id)", corpo: Corpo(estado: estado.bruto, cadeiraId: cadeiraId)
            )
            await carregar()
            guard let lida = carga.valor?.sessoesDoDia.first(where: { $0.id == sessao.id }), lida.estado == estado else {
                return .falhou("A mudança foi enviada, mas o painel ainda mostra o estado antigo. Puxe para atualizar.")
            }
            return .feito(mensagem(para: estado, sessao: lida))
        } catch {
            return .falhou(MensagemDoGiro.de(ErroDaAPI(error), contexto: "Não foi possível mudar o estado da sessão."))
        }
    }

    private func mensagem(para estado: EstadoDaSessao, sessao: SessaoDeCadeira) -> String {
        let primeiroNome = sessao.paciente.split(separator: " ").first.map(String.init) ?? sessao.paciente
        switch estado {
        case .concluida: return "Sessão encerrada · cadeira liberada"
        case .cancelada: return "Sessão cancelada"
        case .aguardandoMedicacao: return "\(primeiroNome) chegou"
        default: return "\(primeiroNome) · \(estado.nome.lowercased())"
        }
    }

    // MARK: Leituras derivadas

    /// Sessões de uma cadeira que se sobrepõem ao intervalo — a API não impede duas
    /// sessões na mesma poltrona, então quem avisa é a tela.
    func conflitos(cadeiraId: String, de inicio: Date, ate fim: Date, exceto: String? = nil) -> [SessaoDeCadeira] {
        (carga.valor?.sessoesDoDia ?? []).filter {
            $0.cadeiraId == cadeiraId && $0.id != exceto && $0.estado != .cancelada && $0.estado != .concluida
                && $0.previsaoDeInicio < fim && $0.previsaoDeFim > inicio
        }
    }

    func ocupacao(da cadeiraId: String?) -> OcupacaoDeCadeira? {
        guard let cadeiraId else { return nil }
        return carga.valor?.giro.porCadeira.first { $0.cadeira.id == cadeiraId }
    }
}
