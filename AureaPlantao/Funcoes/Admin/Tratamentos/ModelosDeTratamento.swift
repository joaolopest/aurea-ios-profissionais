import Foundation

// Contrato de `apps/api/src/rotas/cadastro-de-tratamentos.ts`, modelado da resposta real
// (`curl` com admin@, 25/09/2026). O web destas três telas nunca chamou a API — guardava
// tudo em estado local —, então não havia tipo TypeScript confiável para copiar.

/// Item de `GET /admin/tratamentos` e resposta 201 do POST.
///
/// A lista NÃO traz `encerradoEm` — só `ativo`. A data de encerramento só aparece na
/// resposta do `PATCH …/encerrar`.
struct TratamentoAdmin: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let paciente: ReferenciaDeCadastro
    let protocolo: ReferenciaDeCadastro
    /// Nulo na maioria da seed: o campo é opcional no cadastro.
    let medicoResponsavel: ProfissionalDeCadastro?
    /// `@db.Date` — meia-noite UTC. Ler com `DataCivil`.
    let iniciadoEm: Date
    let ativo: Bool
}

/// Resposta de `PATCH /admin/tratamentos/:id/encerrar`.
struct TratamentoEncerrado: Decodable, Sendable {
    let id: String
    let encerradoEm: Date
    let ativo: Bool
}

/// Item de `GET /admin/tratamentos/:id/ciclos` (linha inteira do Prisma), resposta do POST
/// e do `PATCH /admin/ciclos/:id`.
struct CicloAdmin: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let tratamentoId: String
    let numero: Int
    let sessaoRealizadaEm: Date
    /// Nula enquanto não há previsão — a data real depende de exame e de agenda.
    let previsaoDaProximaSessao: Date?
    let criadoEm: Date
}

/// Item de `GET /admin/pacientes/:id/prescricoes` e resposta 201 do POST.
struct PrescricaoAdmin: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let pacienteId: String
    let medicamentoId: String
    /// Dose, via e frequência num texto só — a API não separa dose e via.
    let posologia: String
    let iniciadaEm: Date
    let encerradaEm: Date?
    let prescritaPorId: String?
    let criadaEm: Date
    let medicamento: Medicamento
    let prescritaPor: ProfissionalDeCadastro?
    let ativa: Bool

    struct Medicamento: Decodable, Sendable, Hashable {
        let id: String
        let nome: String
        let principioAtivo: String?
    }
}

/// Resposta de `PATCH /admin/prescricoes/:id/encerrar`.
struct PrescricaoEncerrada: Decodable, Sendable {
    let id: String
    let encerradaEm: Date
    let ativa: Bool
}
