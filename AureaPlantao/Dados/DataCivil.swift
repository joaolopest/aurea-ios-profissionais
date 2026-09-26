import Foundation

/// Data sem hora (`@db.Date` no Prisma): nascimento, início e fim de tratamento, ciclo,
/// prescrição, internação, pendência. A API grava o DIA e devolve meia-noite UTC
/// (`2026-09-26T00:00:00.000Z`). Formatado no fuso do aparelho (UTC−3), isso vira o dia
/// ANTERIOR — "25/09" para uma data que é 26/09, e a idade com um ano a menos na véspera do
/// aniversário. O web teve esse defeito até 26/09/2026 (commit 3aa48e9).
///
/// Regra única do app, e por isso UM tipo só (antes eram três, com nomes que diferiam por
/// uma letra — conta repetida é conta que diverge):
/// - **lendo da API:** sempre em UTC;
/// - **escrevendo para a API:** o dia que a pessoa escolheu no seletor, no calendário
///   local, como `aaaa-mm-dd`;
/// - **ponte com o seletor:** meio-dia local do mesmo dia, longe de qualquer virada de fuso.
enum DataCivil {
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    private static let ptBR = Locale(identifier: "pt_BR")

    private static var calendarioUTC: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    private static func estilo(_ base: Date.FormatStyle) -> Date.FormatStyle {
        var e = base
        e.timeZone = utc
        e.locale = ptBR
        return e
    }

    // MARK: Exibir (dado vindo da API)

    /// "26 de set."
    static func textoCurto(_ data: Date) -> String {
        data.formatted(estilo(.dateTime.day().month(.abbreviated)))
    }

    /// "26 de set. de 2026"
    static func textoCompleto(_ data: Date) -> String {
        data.formatted(estilo(.dateTime.day().month(.abbreviated).year()))
    }

    /// "26/09/2026"
    static func numerica(_ data: Date) -> String {
        data.formatted(estilo(.dateTime.day(.twoDigits).month(.twoDigits).year()))
    }

    /// "26/09" — indicador, onde o ano é óbvio.
    static func curta(_ data: Date) -> String {
        data.formatted(estilo(.dateTime.day(.twoDigits).month(.twoDigits)))
    }

    /// "26 de setembro de 2026" — para o VoiceOver, que lê "26/09" como fração.
    static func porExtenso(_ data: Date) -> String {
        data.formatted(estilo(.dateTime.day().month(.wide).year()))
    }

    /// `aaaa-mm-dd` da data da API — comparável como texto.
    static func chave(_ data: Date) -> String {
        let c = calendarioUTC.dateComponents([.year, .month, .day], from: data)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Escrever (dado indo para a API)

    /// O dia escolhido no seletor (calendário local) no formato que a API grava.
    static func paraAPI(_ data: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: data)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Hoje, no formato da API.
    static var hoje: String { paraAPI(.now) }

    // MARK: Ponte com o seletor

    /// A data da API levada ao `DatePicker`: meio-dia local do mesmo dia civil.
    static func paraSeletor(_ data: Date) -> Date {
        var c = calendarioUTC.dateComponents([.year, .month, .day], from: data)
        c.hour = 12
        return Calendar.current.date(from: c) ?? data
    }

    // MARK: Contas

    /// Anos completos por data civil — nunca por subtração de instantes, que erra perto do
    /// aniversário (mesma disciplina de `idadeEmAnos` na API).
    static func idade(_ nascimento: Date, hoje: Date = .now) -> Int {
        let n = calendarioUTC.dateComponents([.year, .month, .day], from: nascimento)
        let h = Calendar.current.dateComponents([.year, .month, .day], from: hoje)
        guard let an = n.year, let ah = h.year else { return 0 }
        var anos = ah - an
        if (h.month ?? 0, h.day ?? 0) < (n.month ?? 0, n.day ?? 0) { anos -= 1 }
        return anos
    }

    /// Dias de hoje até a data civil (negativo = já passou).
    static func diasAte(_ data: Date, agora: Date = .now) -> Int {
        let alvo = calendarioUTC.dateComponents([.year, .month, .day], from: data)
        let hoje = Calendar.current.dateComponents([.year, .month, .day], from: agora)
        let g = Calendar(identifier: .gregorian)
        guard let a = g.date(from: alvo), let h = g.date(from: hoje) else { return 0 }
        return g.dateComponents([.day], from: h, to: a).day ?? 0
    }
}
