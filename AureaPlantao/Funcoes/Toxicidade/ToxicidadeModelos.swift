import Foundation

// `GET /painel/indicadores-de-toxicidade?dias=N` (painel.ts; motor em
// `packages/contratos/src/indicadores-de-toxicidade.ts`).
//
// 🔴 Modelado a partir da resposta REAL (curl com enfermagem@ e medico@, 25/09/2026, com
// dias = 7, 14, 30, 60, 90, 180 e 365). Nenhum campo veio nulo em nenhuma variante, exceto
// `porProtocolo[].sintomaMaisFrequente`, que o motor declara `Sintoma | null` — fica opcional.
// `serie` vem com UMA entrada por dia da janela, zeros inclusive, do mais antigo ao mais novo.
// `dias` fora de 7…365 devolve 500 "Erro interno." (deveria ser 400) — a tela só oferece
// janelas dentro da faixa.

struct IndicadoresDeToxicidade: Decodable, Sendable, Equatable {
    let diasConsiderados: Int
    let totalDeSessoes: Int
    let taxas: [Taxa]
    let porProtocolo: [PorProtocolo]
    let amostraSuficiente: Bool
    let serie: [PontoDaSerie]
    let janelaAnterior: JanelaAnterior

    struct Taxa: Decodable, Sendable, Equatable {
        let sintoma: SintomaDeToxicidade
        /// Em quantas sessões o sintoma passou do limiar (amarelo ou vermelho).
        let ocorrencias: Int
        let totalDeSessoes: Int
        /// 0 a 100, já arredondado pelo motor.
        let percentual: Int
    }

    struct PorProtocolo: Decodable, Sendable, Equatable {
        let protocolo: String
        let totalDeSessoes: Int
        let sintomaMaisFrequente: SintomaDeToxicidade?
        let ocorrenciasDoMaisFrequente: Int
        let amostraSuficiente: Bool
    }

    struct PontoDaSerie: Decodable, Sendable, Equatable {
        /// `AAAA-MM-DD`, no fuso do serviço.
        let dia: String
        let ocorrencias: Int
    }

    struct JanelaAnterior: Decodable, Sendable, Equatable {
        let totalDeSessoes: Int
        let ocorrencias: Int
        /// Só verdadeiro quando a janela anterior tem amostra que sustente a conta. Falso,
        /// a variação NÃO aparece — "de 0 para 23" seria uma descoberta inventada.
        let comparavel: Bool
    }

    /// Soma das ocorrências na janela — o número do cartão em destaque.
    var ocorrenciasNaJanela: Int { taxas.reduce(0) { $0 + $1.ocorrencias } }

    /// Variação contra a janela anterior, com o denominador em OCORRÊNCIAS dos dois lados
    /// (comparar ocorrências com sessões daria um número sem significado). Nula quando o
    /// motor diz que não é comparável, ou quando antes era zero.
    var variacao: (percentual: Int, antes: Int)? {
        guard janelaAnterior.comparavel, janelaAnterior.ocorrencias > 0 else { return nil }
        let antes = janelaAnterior.ocorrencias
        let bruto = Double(ocorrenciasNaJanela - antes) / Double(antes) * 100
        return (FormatoAnalitico.arredondarComoWeb(bruto), antes)
    }
}

/// Os sintomas do MVP. Valor novo da API não derruba a tela: cai em `.desconhecido` e
/// aparece com o identificador cru — esconder um sintoma é pior que exibi-lo feio.
enum SintomaDeToxicidade: Decodable, Sendable, Equatable, Hashable {
    case febre, diarreia, nauseaVomito, dor, faltaDeAr
    case desconhecido(String)

    init(from decoder: Decoder) throws {
        let bruto = try decoder.singleValueContainer().decode(String.self)
        switch bruto {
        case "FEBRE": self = .febre
        case "DIARREIA": self = .diarreia
        case "NAUSEA_VOMITO": self = .nauseaVomito
        case "DOR": self = .dor
        case "FALTA_DE_AR": self = .faltaDeAr
        default: self = .desconhecido(bruto)
        }
    }

    var codigo: String {
        switch self {
        case .febre: "FEBRE"
        case .diarreia: "DIARREIA"
        case .nauseaVomito: "NAUSEA_VOMITO"
        case .dor: "DOR"
        case .faltaDeAr: "FALTA_DE_AR"
        case .desconhecido(let c): c
        }
    }

    /// Rótulos do web desta tela (`painel/toxicidade/page.tsx`, `ROTULO_DO_SINTOMA`).
    var nome: String {
        switch self {
        case .febre: "Febre"
        case .diarreia: "Diarreia"
        case .nauseaVomito: "Náusea e vômito"
        case .dor: "Dor"
        case .faltaDeAr: "Falta de ar"
        case .desconhecido(let c): c
        }
    }
}
