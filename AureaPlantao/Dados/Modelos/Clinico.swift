import Foundation

// Tipos clínicos compartilhados.
//
// 🔴 Modelados a partir da RESPOSTA REAL da API (curl com o token de enfermagem em
// 25/09/2026), nunca do tipo do front. O web teve cinco telas quebradas por confiar no
// tipo: `solicitadaEm`/`criadaEm`, `descricao`/`substancia`, `motivoDeNaoClassificar`/
// `motivo`, `assunto`/`titulo`, `CONSULTA_MEDICA`/`CONSULTA`.
//
// Contrato de decodificação: campo faltando QUEBRA (não é opcional se a API sempre manda);
// campo a mais é ignorado; valor de enum desconhecido NÃO quebra — cai em `.desconhecido`
// e a tela mostra o identificador cru, porque esconder um sintoma novo é pior que exibi-lo feio.

/// A situação de um paciente na escala clínica. É o ÚNICO caminho para as cores de `Faixa`.
enum SituacaoClinica: Sendable, Equatable {
    case vermelho, amarelo, verde, silencio

    var nome: String {
        switch self {
        case .vermelho: "Vermelho"
        case .amarelo: "Amarelo"
        case .verde: "Verde"
        case .silencio: "Sem resposta"
        }
    }
}

/// `VERMELHO | AMARELO | VERDE` — a classificação de uma regra ou de um check-in.
enum Classificacao: String, Decodable, Sendable {
    case vermelho = "VERMELHO"
    case amarelo = "AMARELO"
    case verde = "VERDE"

    var situacao: SituacaoClinica {
        switch self {
        case .vermelho: .vermelho
        case .amarelo: .amarelo
        case .verde: .verde
        }
    }
}

/// Os cinco sintomas do MVP (`packages/contratos/src/sintomas.ts`).
struct Sintoma: Decodable, Hashable, Sendable {
    let codigo: String

    init(from decoder: Decoder) throws {
        codigo = try decoder.singleValueContainer().decode(String.self)
    }

    /// Rótulos do web (`apps/web/src/sistema/formato.ts`, `ROTULO_DO_SINTOMA`).
    var nome: String {
        switch codigo {
        case "FEBRE": "Febre"
        case "DIARREIA": "Diarreia"
        case "NAUSEA_VOMITO": "Náusea ou vômito"
        case "DOR": "Dor"
        case "FALTA_DE_AR": "Falta de ar"
        default: codigo
        }
    }
}

/// `valorObservado` chega em QUATRO tipos na mesma coluna: inteiro (`4` episódios), decimal
/// (`38.9` °C), booleano (`consegueBeberLiquidos: false`) e texto (`"AO_CAMINHAR"`).
/// Um `Decodable` com `Double` quebraria no primeiro booleano.
enum ValorObservado: Decodable, Sendable, Hashable {
    case numero(Double)
    case booleano(Bool)
    case texto(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Booleano antes de número: JSONDecoder não converte `true` em Double, mas a ordem
        // deixa a intenção explícita.
        if let b = try? c.decode(Bool.self) { self = .booleano(b); return }
        if let n = try? c.decode(Double.self) { self = .numero(n); return }
        self = .texto(try c.decode(String.self))
    }
}

/// Uma regra que disparou. Toda classificação vem com a regra que a produziu (lei 2 do produto).
struct RegraDisparada: Decodable, Sendable, Hashable, Identifiable {
    let regraId: String
    let sintoma: Sintoma
    let campo: String
    let valorObservado: ValorObservado
    let classificacao: Classificacao
    let justificativa: String

    var id: String { regraId + campo }
}

enum Formato {
    /// Descrição curta do que foi observado, em linguagem de enfermagem: "4 episódios em 24 h".
    /// Serve à linha da fila; a justificativa inteira vai para o prontuário.
    static func observado(_ regra: RegraDisparada) -> String {
        switch (regra.campo, regra.valorObservado) {
        case ("temperaturaMaxima", .numero(let v)):
            return "\(decimal(v)) °C"
        case ("episodiosEm24h", .numero(let v)):
            return "\(inteiro(v)) evacuações em 24 h"
        case ("episodiosDeVomito", .numero(let v)):
            return "\(inteiro(v)) vômitos em 24 h"
        case ("intensidade", .numero(let v)):
            return "intensidade \(inteiro(v)) de 10"
        case ("consegueBeberLiquidos", .booleano(let b)):
            return b ? "consegue beber líquidos" : "não retém líquidos"
        case ("esforco", .texto(let t)):
            return esforco(t)
        case (_, .numero(let v)):
            return decimal(v)
        case (_, .booleano):
            // Booleano sem campo conhecido: o sintoma já diz tudo. "sim" sozinho não informa.
            return ""
        case (_, .texto(let t)):
            return t.replacingOccurrences(of: "_", with: " ").lowercased()
        }
    }

    private static func esforco(_ t: String) -> String {
        switch t {
        case "AO_CAMINHAR": "ao caminhar"
        case "AO_FALAR": "ao falar"
        case "EM_REPOUSO": "em repouso"
        default: t.lowercased()
        }
    }

    static func decimal(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
    }

    static func inteiro(_ v: Double) -> String { String(Int(v.rounded())) }

    /// "há 12 min", "há 3 h", "ontem" — tempo desde um instante, curto, para coluna.
    static func desde(_ data: Date, agora: Date = .now) -> String {
        let s = max(0, agora.timeIntervalSince(data))
        switch s {
        case ..<60: return "agora"
        case ..<3600: return "há \(Int(s / 60)) min"
        case ..<86_400: return "há \(Int(s / 3600)) h"
        case ..<172_800: return "ontem"
        default: return "há \(Int(s / 86_400)) dias"
        }
    }

    static func hora(_ data: Date) -> String {
        data.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "pt_BR")))
    }

    static func dia(_ data: Date) -> String {
        data.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))
    }

    /// "hoje · 20:05", "ontem · 08:12", "12 de ago. · 14:00".
    static func quando(_ data: Date) -> String {
        let cal = Calendar.current
        let dia = cal.isDateInToday(data) ? "hoje" : cal.isDateInYesterday(data) ? "ontem" : Formato.dia(data)
        return "\(dia) · \(hora(data))"
    }

    /// "25/09" — data de coluna, curta e alinhável.
    static func diaCurto(_ data: Date) -> String {
        data.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Locale(identifier: "pt_BR")))
    }

    static func diaCompleto(_ data: Date) -> String {
        data.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "pt_BR")))
    }

    /// Telefone brasileiro: "79911111111" → "(79) 91111-1111".
    static func telefone(_ bruto: String) -> String {
        let d = bruto.filter(\.isNumber)
        guard d.count == 11 || d.count == 10 else { return bruto }
        let ddd = d.prefix(2)
        let resto = d.dropFirst(2)
        let corte = resto.count == 9 ? 5 : 4
        return "(\(ddd)) \(resto.prefix(corte))-\(resto.dropFirst(corte))"
    }

    static func idade(nascimento: Date, agora: Date = .now) -> Int {
        Calendar(identifier: .gregorian).dateComponents([.year], from: nascimento, to: agora).year ?? 0
    }
}
