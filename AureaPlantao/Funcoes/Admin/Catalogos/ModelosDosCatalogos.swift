import Foundation

// Contrato de `GET/POST /admin/protocolos` e `GET/POST /admin/medicamentos`
// (`apps/api/src/rotas/admin.ts`), modelado da resposta real. O GET devolve a linha
// inteira do Prisma — mais campos do que o tipo `Protocolo` do web conhece.

/// Linha de `GET /admin/protocolos`.
struct ProtocoloDoCatalogo: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let nome: String
    /// Nula em protocolo cadastrado sem descrição.
    let descricao: String?
    let ativo: Bool
    // Atributos que pesam no risco — característica do PROTOCOLO, não do paciente.
    let imunoterapia: Bool
    let altoRiscoDeNeutropenia: Bool
    let bombaInfusora: Bool
    let tratamentoOral: Bool
    // Tempos que, somados, dizem quanto a poltrona fica ocupada.
    let tempoDePreparoEmMinutos: Int
    let tempoDePreMedicacaoEmMinutos: Int
    let tempoDeInfusaoEmMinutos: Int
    let tempoDeObservacaoEmMinutos: Int
    let criadoEm: Date

    var semDescricao: Bool {
        (descricao ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var minutosDeCadeira: Int {
        tempoDePreparoEmMinutos + tempoDePreMedicacaoEmMinutos + tempoDeInfusaoEmMinutos + tempoDeObservacaoEmMinutos
    }

    /// "2 h 50 min", "45 min".
    var tempoDeCadeira: String {
        let h = minutosDeCadeira / 60, m = minutosDeCadeira % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    var atributos: [String] {
        var lista: [String] = []
        if imunoterapia { lista.append("imunoterapia") }
        if altoRiscoDeNeutropenia { lista.append("alto risco de neutropenia") }
        if bombaInfusora { lista.append("bomba infusora") }
        if tratamentoOral { lista.append("oral") }
        return lista
    }
}

/// Linha de `GET /admin/medicamentos`.
struct MedicamentoDoCatalogo: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let nome: String
    let principioAtivo: String?
    let criadoEm: Date

    var semPrincipioAtivo: Bool {
        (principioAtivo ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Resposta 201 do POST — só o `id` importa: a lista é relida para conferir a gravação.
struct RegistroCriadoNoCatalogo: Decodable, Sendable {
    let id: String
}
