import Foundation

/// CPF do paciente: identidade de login e dado sensível.
///
/// A validação é a MESMA de `packages/contratos/src/cpf.ts` (dígito verificador, não só
/// formato, e sequência repetida recusada). Duas implementações que divergem significam a
/// tela aceitar um CPF que o servidor recusa. Nada aqui imprime o CPF — nem em DEBUG.
enum CPFDoCadastro {
    /// Só os dígitos. `123.456.789-09` e `12345678909` são o mesmo CPF.
    static func normalizar(_ entrada: String) -> String {
        entrada.filter(\.isASCII).filter(\.isNumber)
    }

    static func ehValido(_ entrada: String) -> Bool {
        let cpf = normalizar(entrada)
        guard cpf.count == 11 else { return false }
        let digitos = cpf.compactMap { $0.wholeNumberValue }
        // Sequência repetida passa no cálculo mas é inválida por convenção da Receita.
        guard Set(digitos).count > 1 else { return false }
        for posicao in 9..<11 {
            let peso = posicao + 1
            var soma = 0
            for indice in 0..<posicao { soma += digitos[indice] * (peso - indice) }
            let esperado = ((soma * 10) % 11) % 10
            if digitos[posicao] != esperado { return false }
        }
        return true
    }

    /// Máscara progressiva enquanto digita: "12345" → "123.45". Corta em 11 dígitos.
    static func mascaraDeDigitacao(_ entrada: String) -> String {
        let d = Array(normalizar(entrada).prefix(11))
        var saida = ""
        for (i, c) in d.enumerated() {
            if i == 3 || i == 6 { saida.append(".") }
            if i == 9 { saida.append("-") }
            saida.append(c)
        }
        return saida
    }

    /// Mascarado para lista e ficha: "•••.456.789-••". O miolo basta para a equipe
    /// conferir com o documento sem expor o número inteiro na tela.
    static func mascarado(_ entrada: String) -> String {
        let d = Array(normalizar(entrada))
        guard d.count == 11 else { return "•••.•••.•••-••" }
        return "•••.\(String(d[3..<6])).\(String(d[6..<9]))-••"
    }

    static func formatado(_ entrada: String) -> String {
        let d = Array(normalizar(entrada))
        guard d.count == 11 else { return entrada }
        return "\(String(d[0..<3])).\(String(d[3..<6])).\(String(d[6..<9]))-\(String(d[9..<11]))"
    }
}

enum InstanteDoCadastro {
    /// Instante para a API (agenda): ISO 8601 em UTC com milissegundos.
    static func paraAPI(_ data: Date) -> String {
        data.formatted(.iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: true).timeSeparator(.colon).timeZone(separator: .omitted))
    }

    /// "qui., 2 de out. · 10:30".
    static func exibir(_ data: Date) -> String {
        let dia = data.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))
        return "\(dia) · \(Formato.hora(data))"
    }
}

enum TextoDoCadastro {
    /// Aparado; vazio vira `nil` (a API recusa string vazia onde aceita ausência).
    static func opcional(_ texto: String) -> String? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func aparado(_ texto: String) -> String {
        texto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Busca sem acento e sem caixa: "joao" acha "João".
    static func contem(_ texto: String, _ termo: String) -> Bool {
        texto.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
