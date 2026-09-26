import Foundation
import LocalAuthentication
import Observation

/// O estado de quem está usando o app, do lado de fora das telas.
///
/// Quatro fases, e a ordem é a porta:
/// `fora` → (entrar) → `trocandoSenha`? → `trancado` ⇄ `dentro`
///
/// `trancado` existe mesmo com token válido: o app pede Face ID ao abrir e ao voltar do
/// fundo. Celular pessoal com prontuário oncológico não abre com um toque de quem o pegou
/// na bancada do posto.
@MainActor
@Observable
final class Sessao {
    enum Fase: Equatable {
        case verificando
        case fora
        case trocandoSenha(senhaAtual: String)
        case trancado
        case dentro
    }

    private(set) var fase: Fase = .verificando
    private(set) var eu: QuemSou?
    /// Mensagem que a tela de entrada mostra ao voltar (ex.: sessão expirada).
    var avisoDeEntrada: String?

    private let api: ClienteAPI
    private let token: GuardaDeToken

    /// Tranca por Face ID/código ao abrir e ao voltar do fundo.
    ///
    /// DESLIGADA a pedido do João (25/09/2026): por enquanto o app entra só com e-mail e
    /// senha, como o web. O código da tranca continua inteiro — religar é trocar para `true`.
    /// ⚠️ Antes de ir para aparelho da equipe, isto volta à mesa junto com o parecer do
    /// Comitê de Ética: prontuário oncológico em celular pessoal sem trava própria.
    static let trancaBiometricaLigada = false

    init(api: ClienteAPI = .compartilhado, token: GuardaDeToken = .compartilhado) {
        self.api = api
        self.token = token
    }

    /// Abertura do app: com token, tranca e pede Face ID; sem token, vai para a entrada.
    func iniciar() {
        guard token.ler() != nil else { fase = .fora; return }
        if Self.trancaBiometricaLigada {
            fase = .trancado
        } else {
            // Como o web: sessão guardada, entra direto. Se o token venceu, o /eu devolve
            // 401 e a pessoa volta para a entrada.
            fase = .verificando
            Task { await concluirDestrava() }
        }
    }

    // MARK: Entrar e sair

    func entrar(email: String, senha: String, manterConectado: Bool) async throws {
        struct Corpo: Encodable, Sendable { let email: String; let senha: String; let manterConectado: Bool }
        let resposta: RespostaDeEntrada = try await api.enviar(
            "/autenticacao/entrar",
            corpo: Corpo(email: email.trimmingCharacters(in: .whitespaces).lowercased(), senha: senha, manterConectado: manterConectado)
        )

        // App da equipe. Paciente tem o app dele — e o painel recusaria de qualquer forma.
        guard resposta.perfil != "PACIENTE" else {
            throw ErroDaAPI.recusado("Este app é da equipe de enfermagem. O paciente usa o app AUREA dele.")
        }

        token.guardar(resposta.token)
        eu = try await api.obter("/autenticacao/eu")
        avisoDeEntrada = nil

        // Acabou de provar a senha: não pede Face ID de novo agora.
        fase = resposta.precisaVerPrimeiroAcesso ? .trocandoSenha(senhaAtual: senha) : .dentro
    }

    /// Troca de senha do primeiro acesso. A API revoga TODAS as sessões ao trocar —
    /// inclusive esta —, então a pessoa volta para a entrada com a senha nova.
    func trocarSenha(atual: String, nova: String) async throws {
        struct Corpo: Encodable, Sendable { let senhaAtual: String; let senhaNova: String }
        let _: Vazio = try await api.enviar("/conta/senha", corpo: Corpo(senhaAtual: atual, senhaNova: nova))
        encerrarLocalmente(aviso: "Senha trocada. Entre com a senha nova.")
    }

    #if DEBUG
    /// Só na demonstração: a senha das contas de demo é compartilhada, e trocá-la aqui
    /// trancaria a equipe inteira fora do ambiente. Em produção esta porta não existe.
    func pularTrocaDeSenhaNaDemonstracao() { fase = .dentro }
    #endif

    func sair() async {
        struct Nada: Encodable, Sendable {}
        try? await api.enviarSemResposta("/autenticacao/sair", corpo: Nada())
        encerrarLocalmente(aviso: nil)
    }

    /// A API respondeu 401 no meio do uso.
    func sessaoExpirou() {
        encerrarLocalmente(aviso: "Sua sessão terminou. Entre de novo.")
    }

    private func encerrarLocalmente(aviso: String?) {
        token.apagar()
        eu = nil
        avisoDeEntrada = aviso
        fase = .fora
    }

    // MARK: Tranca

    /// Chamado quando o app vai para o fundo.
    func trancar() {
        if Self.trancaBiometricaLigada, fase == .dentro { fase = .trancado }
    }

    /// Face ID, com o código do aparelho como alternativa (luva, máscara).
    func destrancar() async -> String? {
        let contexto = LAContext()
        contexto.localizedFallbackTitle = "Usar código do iPhone"
        var erro: NSError?

        guard contexto.canEvaluatePolicy(.deviceOwnerAuthentication, error: &erro) else {
            #if DEBUG
            // Simulador sem código configurado. No aparelho, sem código não há como proteger.
            if (erro as? LAError)?.code == .passcodeNotSet {
                await concluirDestrava()
                return nil
            }
            #endif
            return "Configure um código de acesso no iPhone para usar o AUREA. O app mostra dado de saúde e não abre sem trava."
        }

        do {
            try await contexto.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Abrir o plantão")
            await concluirDestrava()
            return nil
        } catch let erro as LAError where erro.code == .userCancel || erro.code == .appCancel || erro.code == .systemCancel {
            return nil
        } catch {
            return "Não foi possível confirmar que é você. Tente de novo."
        }
    }

    private func concluirDestrava() async {
        if eu == nil {
            do {
                eu = try await api.obter("/autenticacao/eu")
            } catch ErroDaAPI.sessaoEncerrada {
                sessaoExpirou()
                return
            } catch {
                // Sem rede ao destravar: entra mesmo assim, cada tela mostra o próprio erro.
            }
        }
        fase = .dentro
    }
}
