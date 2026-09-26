import Foundation

/// A árvore de triagem vista do admin: quais campos cada sintoma tem, de que tipo, com que
/// unidade. Espelho de `packages/contratos/src/sintomas.ts` (`ARVORE_DE_TRIAGEM`).
///
/// Existe no app por um motivo só: o formulário de regra oferece o CAMPO numa lista, não num
/// texto livre. Campo digitado errado é regra que nunca dispara — a API recusa com 422, mas o
/// certo é não deixar errar. A árvore é código no AUREA (muda com tela nova e revisão
/// clínica), então duplicá-la aqui não fere a regra 1 do ADR-001: o que é dado — o corte —
/// continua vindo do banco.
enum ArvoreDoAlgoritmo {
    enum Tipo: Sendable { case booleano, numerico, inteiro, opcao }

    struct Campo: Hashable, Sendable {
        let codigo: String
        let nome: String
        let tipo: Tipo
        var unidade: String? = nil
        var opcoes: [String] = []
    }

    static let sintomas = ["FEBRE", "DIARREIA", "NAUSEA_VOMITO", "DOR", "FALTA_DE_AR"]

    static func campos(de sintoma: String) -> [Campo] {
        switch sintoma {
        case "FEBRE":
            [Campo(codigo: "apresentouFebre", nome: "Teve febre", tipo: .booleano),
             Campo(codigo: "temperaturaMaxima", nome: "Temperatura máxima", tipo: .numerico, unidade: "°C"),
             Campo(codigo: "usouAntitermico", nome: "Tomou antitérmico", tipo: .booleano)]
        case "DIARREIA":
            [Campo(codigo: "apresentouDiarreia", nome: "Teve diarreia", tipo: .booleano),
             Campo(codigo: "episodiosEm24h", nome: "Evacuações em 24 h", tipo: .inteiro),
             Campo(codigo: "presencaDeSangue", nome: "Sangue nas fezes", tipo: .booleano)]
        case "NAUSEA_VOMITO":
            [Campo(codigo: "sentiuNausea", nome: "Sentiu enjoo", tipo: .booleano),
             Campo(codigo: "vomitou", nome: "Vomitou", tipo: .booleano),
             Campo(codigo: "episodiosDeVomito", nome: "Vômitos", tipo: .inteiro),
             Campo(codigo: "consegueBeberLiquidos", nome: "Consegue beber líquidos", tipo: .booleano),
             Campo(codigo: "consegueComer", nome: "Consegue comer", tipo: .booleano)]
        case "DOR":
            [Campo(codigo: "apresentouDor", nome: "Sentiu dor", tipo: .booleano),
             Campo(codigo: "localizacao", nome: "Local da dor", tipo: .opcao,
                   opcoes: ["ABDOMINAL", "TORACICA", "CABECA", "BOCA_OU_GARGANTA", "OSSOS_OU_ARTICULACOES", "LOCAL_DO_CATETER", "OUTRO"]),
             Campo(codigo: "intensidade", nome: "Intensidade da dor (0 a 10)", tipo: .inteiro)]
        case "FALTA_DE_AR":
            [Campo(codigo: "apresentouFaltaDeAr", nome: "Sentiu falta de ar", tipo: .booleano),
             Campo(codigo: "esforco", nome: "Esforço que provoca falta de ar", tipo: .opcao,
                   opcoes: ["AO_CAMINHAR", "AO_FALAR", "EM_REPOUSO"])]
        default: []
        }
    }

    static func campo(_ codigo: String, de sintoma: String) -> Campo? {
        campos(de: sintoma).first { $0.codigo == codigo }
    }

    /// Operadores que fazem sentido para o tipo do campo — o mesmo que
    /// `conferirIntegridadeDoConjunto` exige no servidor.
    static func operadores(para tipo: Tipo) -> [OperadorDaRegra] {
        switch tipo {
        case .numerico, .inteiro: [.maiorOuIgual, .maiorQue, .menorOuIgual, .menorQue, .igual, .entre]
        case .booleano: [.eVerdadeiro, .eFalso]
        case .opcao: [.estaEm]
        }
    }
}

/// Os nomes em português de tudo que a API manda em código.
enum NomesDoAlgoritmo {
    static func sintoma(_ codigo: String) -> String {
        switch codigo {
        case "FEBRE": "Febre"
        case "DIARREIA": "Diarreia"
        case "NAUSEA_VOMITO": "Náusea ou vômito"
        case "DOR": "Dor"
        case "FALTA_DE_AR": "Falta de ar"
        default: codigo
        }
    }

    /// Opções da árvore, no vocabulário da equipe (o do paciente mora no app dele).
    static func opcao(_ codigo: String) -> String {
        switch codigo {
        case "ABDOMINAL": "abdominal"
        case "TORACICA": "torácica"
        case "CABECA": "cabeça"
        case "BOCA_OU_GARGANTA": "boca ou garganta"
        case "OSSOS_OU_ARTICULACOES": "ossos ou articulações"
        case "LOCAL_DO_CATETER": "local do cateter"
        case "OUTRO": "outro local"
        case "AO_CAMINHAR": "ao caminhar"
        case "AO_FALAR": "ao falar"
        case "EM_REPOUSO": "em repouso"
        default: codigo.replacingOccurrences(of: "_", with: " ").lowercased()
        }
    }

    // MARK: Política

    static func combinacao(_ codigo: String) -> (nome: String, explicacao: String) {
        switch codigo {
        case "PIOR_ISOLADO": ("Pior isolado", "Cada sintoma é avaliado sozinho; o resultado do dia é o pior entre eles.")
        case "DOIS_AMARELOS_VIRAM_VERMELHO": ("Dois amarelos viram vermelho", "Dois ou mais sintomas amarelos no mesmo dia elevam o resultado do dia a vermelho.")
        default: (codigo, "Política que este app não conhece.")
        }
    }

    static func antitermico(_ codigo: String) -> (nome: String, explicacao: String) {
        switch codigo {
        case "IGNORAR": ("Ignorar", "O uso de antitérmico não altera a classificação da febre.")
        case "ELEVAR_UM_NIVEL": ("Elevar um nível", "Febre respondida com antitérmico sobe um nível na classificação (verde vira amarelo, amarelo vira vermelho).")
        default: (codigo, "Política que este app não conhece.")
        }
    }

    static func abandono(_ codigo: String) -> (nome: String, explicacao: String) {
        switch codigo {
        case "NAO_CLASSIFICAR": ("Não classificar", "Questionário abandonado no meio não gera classificação nesse dia.")
        case "PIOR_DOS_RESPONDIDOS": ("Pior dos respondidos", "Questionário abandonado é classificado pelo pior resultado entre os sintomas já respondidos.")
        default: (codigo, "Política que este app não conhece.")
        }
    }

    /// Campo de política na diferença (`politica[].campo`) e o valor dele, por extenso.
    static func politica(campo: String, valor: String) -> (campo: String, valor: String) {
        switch campo {
        case "combinacao": ("Combinação de sintomas", combinacao(valor).nome)
        case "efeitoDoAntitermico": ("Efeito do antitérmico", antitermico(valor).nome)
        case "tratamentoDeAbandono": ("Tratamento de abandono", abandono(valor).nome)
        default: (campo, valor)
        }
    }

    /// Nome de campo do formulário de conjunto, para os problemas que o Zod devolve.
    static func campoDoFormulario(_ caminho: String) -> String {
        switch caminho.split(separator: ".").first.map(String.init) ?? caminho {
        case "versao": "Versão"
        case "descricao": "Descrição"
        case "origem": "Origem"
        case "regras": "Regras"
        default: caminho
        }
    }

    // MARK: Regra por extenso

    /// A regra como a equipe lê: "Temperatura máxima a partir de 38,5 °C". Lei clínica 4 —
    /// toda classificação mostra a regra que a produziu, por extenso.
    static func frase(sintoma: String, campo codigo: String, operador: OperadorDaRegra,
                      valor: Double?, valorSecundario: Double?, valoresDeTexto: [String]?,
                      diaMinimo: Int?, diaMaximo: Int?, protocoloId: String?) -> String {
        let campo = ArvoreDoAlgoritmo.campo(codigo, de: sintoma)
        let nome = campo?.nome ?? codigo
        let unidade = campo?.unidade.map { " \($0)" } ?? ""

        var texto: String
        switch operador {
        case .maiorOuIgual: texto = "\(nome) a partir de \(numero(valor))\(unidade)"
        case .maiorQue: texto = "\(nome) acima de \(numero(valor))\(unidade)"
        case .menorOuIgual: texto = "\(nome) até \(numero(valor))\(unidade)"
        case .menorQue: texto = "\(nome) abaixo de \(numero(valor))\(unidade)"
        case .igual:
            if let textos = valoresDeTexto, !textos.isEmpty {
                texto = "\(nome): \(textos.map(opcao).joined(separator: " ou "))"
            } else {
                texto = "\(nome) igual a \(numero(valor))\(unidade)"
            }
        case .entre: texto = "\(nome) entre \(numero(valor)) e \(numero(valorSecundario))\(unidade)"
        case .eVerdadeiro: texto = "\(nome): sim"
        case .eFalso: texto = "\(nome): não"
        case .estaEm: texto = "\(nome): \((valoresDeTexto ?? []).map(opcao).joined(separator: " ou "))"
        case .desconhecido(let c): texto = "\(nome) \(c) \(numero(valor))"
        }

        if diaMinimo != nil || diaMaximo != nil {
            texto += ", do dia \(diaMinimo ?? 0) ao \(diaMaximo.map(String.init) ?? "fim") do ciclo"
        }
        if protocoloId != nil { texto += ", só num protocolo" }
        return texto
    }

    static func frase(_ r: RegraDoConjunto) -> String {
        frase(sintoma: r.sintoma, campo: r.campo, operador: r.operador, valor: r.valor,
              valorSecundario: r.valorSecundario, valoresDeTexto: r.valoresDeTexto,
              diaMinimo: r.diaDoCicloMinimo, diaMaximo: r.diaDoCicloMaximo, protocoloId: r.protocoloId)
    }

    /// A frase técnica do servidor ("esforco quando for AO_FALAR ou EM_REPOUSO → vermelho")
    /// com os códigos trocados pelos nomes da árvore. A estrutura da frase é do servidor;
    /// só o vocabulário muda.
    static func humanizar(_ frase: String) -> String {
        var texto = frase
        for sintoma in ArvoreDoAlgoritmo.sintomas {
            for campo in ArvoreDoAlgoritmo.campos(de: sintoma) {
                texto = texto.replacingOccurrences(of: "\\b\(campo.codigo)\\b", with: campo.nome, options: .regularExpression)
                for opcao in campo.opcoes {
                    texto = texto.replacingOccurrences(of: "\\b\(opcao)\\b", with: Self.opcao(opcao), options: .regularExpression)
                }
            }
        }
        return texto
    }

    static func numero(_ v: Double?) -> String {
        guard let v else { return "sem valor" }
        return v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "pt_BR")))
    }
}

/// Datas do admin: "30/07/2026" e "16:13". Auditoria lê data exata, não "há 3 dias".
enum DataDoAdmin {
    private static let brasil = Locale(identifier: "pt_BR")

    static func dia(_ d: Date) -> String {
        d.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(brasil))
    }

    static func hora(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(brasil))
    }

    static func diaEHora(_ d: Date) -> String { "\(dia(d)) às \(hora(d))" }

    /// Para cartão de indicador: o número grande não cabe "25/09/2026" em meia largura
    /// sem quebrar; dia e mês vão no valor, ano e hora no apoio.
    static func diaCurto(_ d: Date) -> String {
        d.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(brasil))
    }

    static func anoEHora(_ d: Date) -> String {
        "\(d.formatted(.dateTime.year().locale(brasil))), às \(hora(d))"
    }
}
