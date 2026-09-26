import SwiftUI

/// O ciclo de vida de um dado remoto numa tela.
///
/// `recarregando` guarda o valor anterior: puxar para atualizar não apaga a fila e mostra
/// esqueleto de novo — a enfermeira continua lendo enquanto o novo chega.
enum Carga<Valor: Sendable>: Sendable {
    case carregando
    case pronto(Valor)
    case falhou(ErroDaAPI, anterior: Valor?)

    var valor: Valor? {
        switch self {
        case .carregando: nil
        case .pronto(let v): v
        case .falhou(_, let anterior): anterior
        }
    }

    var erro: ErroDaAPI? {
        if case .falhou(let e, _) = self { return e }
        return nil
    }
}

extension ErroDaAPI {
    init(_ erro: Error) {
        self = (erro as? ErroDaAPI) ?? .semConexao
    }
}

/// Quando qualquer tela recebe 401, a sessão inteira acaba — não só aquela tela.
struct EncerraSessaoNo401: ViewModifier {
    let erro: ErroDaAPI?
    @Environment(Sessao.self) private var sessao

    func body(content: Content) -> some View {
        content.onChange(of: erro) { _, novo in
            if novo == .sessaoEncerrada { sessao.sessaoExpirou() }
        }
    }
}

extension View {
    func encerraSessaoNo401(_ erro: ErroDaAPI?) -> some View {
        modifier(EncerraSessaoNo401(erro: erro))
    }
}
