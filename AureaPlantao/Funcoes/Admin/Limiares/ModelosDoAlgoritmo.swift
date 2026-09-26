import Foundation

// Contrato do algoritmo (`apps/api/src/rotas/admin.ts`).
//
// 🔴 Modelado a partir da RESPOSTA REAL (curl com admin@ em 25/09/2026), não do tipo do web:
// - `GET /admin/limiares` devolve `ativo` (não `estado`) e `regras` como NÚMERO (contagem),
//   mais `classificacoesProduzidas` e `validadoPor` — o web recalcula `estado` no cliente.
// - `GET /admin/limiares/:id` NÃO traz `ativo`, `publicadoEm` nem `criadoEm`; traz `politica`,
//   `problemasDeIntegridade` e, em cada regra, a frase `descricao`. `valoresDeTexto` só vem
//   nas regras que têm (ESTA_EM), e `valor` chega inteiro ou decimal.
// - A diferença é calculada NO SERVIDOR (`entraram`/`sairam`/`mudaram`/`politica`), por
//   identidade de decisão — não por `id`, que muda a cada conjunto importado.

// MARK: - Enums com saída para valor novo

enum ClassificacaoDaRegra: Hashable, Sendable, Decodable {
    case verde, amarelo, vermelho
    case desconhecido(String)

    static let todas: [ClassificacaoDaRegra] = [.verde, .amarelo, .vermelho]

    init(codigo: String) {
        switch codigo {
        case "VERDE": self = .verde
        case "AMARELO": self = .amarelo
        case "VERMELHO": self = .vermelho
        default: self = .desconhecido(codigo)
        }
    }

    init(from decoder: Decoder) throws {
        self.init(codigo: try decoder.singleValueContainer().decode(String.self))
    }

    var codigo: String {
        switch self {
        case .verde: "VERDE"
        case .amarelo: "AMARELO"
        case .vermelho: "VERMELHO"
        case .desconhecido(let c): c
        }
    }

    /// A única porta para a cor: pela situação clínica. Valor desconhecido não ganha cor.
    var situacao: SituacaoClinica? {
        switch self {
        case .verde: .verde
        case .amarelo: .amarelo
        case .vermelho: .vermelho
        case .desconhecido: nil
        }
    }

    var nome: String {
        switch self {
        case .verde: "Verde"
        case .amarelo: "Amarelo"
        case .vermelho: "Vermelho"
        case .desconhecido(let c): c
        }
    }

    /// Gravidade, para achar o pior de um grupo.
    var peso: Int {
        switch self {
        case .vermelho: 3
        case .amarelo: 2
        case .verde: 1
        case .desconhecido: 0
        }
    }
}

enum OperadorDaRegra: Hashable, Sendable, Decodable {
    case maiorOuIgual, maiorQue, menorOuIgual, menorQue, igual, entre, eVerdadeiro, eFalso, estaEm
    case desconhecido(String)

    init(codigo: String) {
        switch codigo {
        case "MAIOR_OU_IGUAL": self = .maiorOuIgual
        case "MAIOR_QUE": self = .maiorQue
        case "MENOR_OU_IGUAL": self = .menorOuIgual
        case "MENOR_QUE": self = .menorQue
        case "IGUAL": self = .igual
        case "ENTRE": self = .entre
        case "E_VERDADEIRO": self = .eVerdadeiro
        case "E_FALSO": self = .eFalso
        case "ESTA_EM": self = .estaEm
        default: self = .desconhecido(codigo)
        }
    }

    init(from decoder: Decoder) throws {
        self.init(codigo: try decoder.singleValueContainer().decode(String.self))
    }

    var codigo: String {
        switch self {
        case .maiorOuIgual: "MAIOR_OU_IGUAL"
        case .maiorQue: "MAIOR_QUE"
        case .menorOuIgual: "MENOR_OU_IGUAL"
        case .menorQue: "MENOR_QUE"
        case .igual: "IGUAL"
        case .entre: "ENTRE"
        case .eVerdadeiro: "E_VERDADEIRO"
        case .eFalso: "E_FALSO"
        case .estaEm: "ESTA_EM"
        case .desconhecido(let c): c
        }
    }

    /// Rótulo do seletor (`ROTULO_DO_OPERADOR` do web).
    var nome: String {
        switch self {
        case .maiorOuIgual: "maior ou igual a"
        case .maiorQue: "maior que"
        case .menorOuIgual: "menor ou igual a"
        case .menorQue: "menor que"
        case .igual: "igual a"
        case .entre: "entre"
        case .eVerdadeiro: "é verdadeiro (sim)"
        case .eFalso: "é falso (não)"
        case .estaEm: "está entre os valores"
        case .desconhecido(let c): c
        }
    }

    var precisaDeValor: Bool {
        switch self {
        case .maiorOuIgual, .maiorQue, .menorOuIgual, .menorQue, .igual, .entre: true
        default: false
        }
    }
}

// MARK: - Lista

struct ConjuntoResumido: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let versao: String
    let descricao: String
    let origem: String
    let ativo: Bool
    let validadoClinicamente: Bool
    let validadoPor: Validador?
    let validadoEm: Date?
    let publicadoEm: Date?
    let criadoEm: Date
    /// Contagem, não lista.
    let regras: Int
    let classificacoesProduzidas: Int

    struct Validador: Decodable, Sendable, Hashable {
        let nome: String
        let funcao: String?
        let registroDoConselho: String?
    }

    /// O web deriva o estado assim, e é o que a API quer dizer: `ativo` classifica agora;
    /// já publicado e não ativo foi substituído; o resto nunca saiu do rascunho.
    var estado: EstadoDoConjunto {
        if ativo { return .publicado }
        return publicadoEm == nil ? .rascunho : .arquivado
    }
}

enum EstadoDoConjunto: Sendable {
    case publicado, rascunho, arquivado

    var nome: String {
        switch self {
        case .publicado: "Publicado"
        case .rascunho: "Rascunho"
        case .arquivado: "Arquivado"
        }
    }
}

// MARK: - Detalhe

struct ConjuntoDetalhado: Decodable, Sendable {
    let id: String
    let versao: String
    let descricao: String
    let origem: String
    let validadoClinicamente: Bool
    let politica: Politica
    let regras: [RegraDoConjunto]
    let problemasDeIntegridade: [String]

    struct Politica: Decodable, Sendable, Hashable {
        let combinacao: String
        let efeitoDoAntitermico: String
        let tratamentoDeAbandono: String
    }
}

struct RegraDoConjunto: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let ordem: Int
    let sintoma: String
    let campo: String
    let operador: OperadorDaRegra
    let valor: Double?
    let valorSecundario: Double?
    let valoresDeTexto: [String]?
    let classificacao: ClassificacaoDaRegra
    let justificativa: String
    let diaDoCicloMinimo: Int?
    let diaDoCicloMaximo: Int?
    let protocoloId: String?
    /// A frase técnica do servidor ("temperaturaMaxima a partir de 38,5 → vermelho").
    let descricao: String
}

// MARK: - Diferença

struct DiferencaDeConjuntos: Decodable, Sendable {
    let de: Lado
    let para: Lado
    let entraram: [String]
    let sairam: [String]
    let mudaram: [Alteracao]
    let politica: [Alteracao]
    let semDiferenca: Bool
    let regrasRepetidas: [String]

    struct Lado: Decodable, Sendable {
        let versao: String
        let regras: Int
    }

    struct Alteracao: Decodable, Sendable, Hashable {
        let sintoma: String
        let campo: String
        let antes: String
        let depois: String
    }

    var total: Int { entraram.count + sairam.count + mudaram.count + politica.count }
}

// MARK: - Escrita

/// Corpo de `POST /admin/limiares`. Opcional ausente não vai no JSON (o Zod aceita).
struct NovoConjuntoDeLimiares: Encodable, Sendable {
    let versao: String
    let descricao: String
    let origem: String
    let combinacao: String
    let efeitoDoAntitermico: String
    let tratamentoDeAbandono: String
    let regras: [RegraParaEnviar]
}

struct RegraParaEnviar: Encodable, Sendable, Hashable {
    let ordem: Int
    let sintoma: String
    let campo: String
    let operador: String
    let valor: Double?
    let valorSecundario: Double?
    let valoresDeTexto: [String]?
    let classificacao: String
    let justificativa: String
    let diaDoCicloMinimo: Int?
    let diaDoCicloMaximo: Int?
    let protocoloId: String?
}

/// `201` de `POST /admin/limiares`.
struct ConjuntoCriado: Decodable, Sendable {
    let id: String
    let versao: String
    let ativo: Bool
    let aviso: String
}

/// `200` de `POST /admin/limiares/:id/publicar`.
struct ConjuntoPublicado: Decodable, Sendable {
    let publicado: String
    let substituiu: String?
    let validadoClinicamente: Bool
    let aviso: String?
}

/// `200` de `POST /admin/limiares/:id/validar`.
struct ConjuntoValidado: Decodable, Sendable {
    let versao: String
    let validadoEm: Date
}
