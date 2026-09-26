import Foundation

/// `GET /painel/pacientes-do-dia` — conferido com curl em 25/09/2026.
struct PacientesDoDia: Decodable, Sendable {
    let cards: [CartaoDoPlantao]
    let silencio: ContagemDeSilencio
    let resumo: Resumo

    struct Resumo: Decodable, Sendable {
        let total: Int
        let vermelhos: Int
        let amarelos: Int
        let verdes: Int
        let semResposta: Int
    }

    struct ContagemDeSilencio: Decodable, Sendable {
        let umDia: Int
        let doisDias: Int
        let tresDias: Int
        let umaSemana: Int
        let nuncaRespondeu: Int
        let total: Int
    }
}

struct CartaoDoPlantao: Decodable, Sendable, Identifiable, Hashable {
    let pacienteId: String
    let nome: String
    /// `null` para paciente sem tratamento ativo — nem todo cartão tem protocolo.
    let protocolo: String?
    let situacao: Situacao
    let respondeuHoje: Bool
    let diasSemResponder: Int?
    let nuncaRespondeu: Bool
    let ultimaSessaoId: String?
    let diaDoCiclo: Int?
    let regrasDisparadas: [RegraDisparada]
    let faixaDeSilencio: FaixaDeSilencio
    let nivelDePrioridade: NivelDePrioridade
    let motivos: [Motivo]
    let sinalizadores: Sinalizadores

    var id: String { pacienteId }

    struct Motivo: Decodable, Sendable, Hashable {
        /// `sintoma` | `silencio`
        let tipo: String
        let texto: String
    }

    struct Sinalizadores: Decodable, Sendable, Hashable {
        let internadoAte: Date?
    }

    /// `VERMELHO | AMARELO | VERDE | SEM_RESPOSTA_HOJE` (`apps/api/src/rotas/painel.ts:25`).
    enum Situacao: Decodable, Sendable, Hashable {
        case vermelho, amarelo, verde, semRespostaHoje
        case desconhecida(String)

        init(from decoder: Decoder) throws {
            let v = try decoder.singleValueContainer().decode(String.self)
            switch v {
            case "VERMELHO": self = .vermelho
            case "AMARELO": self = .amarelo
            case "VERDE": self = .verde
            case "SEM_RESPOSTA_HOJE": self = .semRespostaHoje
            default: self = .desconhecida(v)
            }
        }
    }

    enum FaixaDeSilencio: String, Decodable, Sendable {
        case hoje = "HOJE"
        case umDia = "UM_DIA"
        case doisDias = "DOIS_DIAS"
        case tresDias = "TRES_DIAS"
        case umaSemana = "UMA_SEMANA"
        case nuncaRespondeu = "NUNCA_RESPONDEU"
    }

    enum NivelDePrioridade: String, Decodable, Sendable {
        case alta = "ALTA"
        case intermediaria = "INTERMEDIARIA"
        case baixa = "BAIXA"
    }

    /// Onde o paciente cai na escala. Silêncio não é verde (lei 3 do produto):
    /// quem não respondeu hoje fica cinza, nunca verde por omissão.
    var situacaoClinica: SituacaoClinica {
        switch situacao {
        case .vermelho: .vermelho
        case .amarelo: .amarelo
        case .verde: .verde
        case .semRespostaHoje, .desconhecida: .silencio
        }
    }

    /// "Precisa de você": vermelho ou amarelo de hoje. MESMA conta do cartão em destaque do
    /// web (`resumo.vermelhos + resumo.amarelos`) — dois caminhos para o mesmo número que
    /// discordam fazem a equipe parar de confiar nos dois.
    var precisaDeAtencao: Bool {
        situacaoClinica == .vermelho || situacaoClinica == .amarelo
    }

    /// A regra mais grave, que vai na linha da fila.
    var regraPrincipal: RegraDisparada? {
        regrasDisparadas.first { $0.classificacao == .vermelho } ?? regrasDisparadas.first
    }

    /// A linha de motivo da fila.
    ///
    /// 🔴 Quem não respondeu hoje ainda carrega em `regrasDisparadas` as regras do ÚLTIMO
    /// check-in — que pode ter semanas. Mostrar "Febre · 38,7 °C" na linha de quem está calado
    /// há 22 dias faz a enfermeira ler um sintoma velho como se fosse de hoje. Para o silêncio,
    /// o motivo é o silêncio; o sintoma antigo entra como contexto, rotulado como passado.
    var resumoDoMotivo: String {
        let silencioso = situacao == .semRespostaHoje
        if nuncaRespondeu { return "Nunca respondeu o questionário" }
        if let regra = regraPrincipal {
            let sintoma = descricao(regra)
            return silencioso ? "Última resposta: \(sintoma)" : sintoma
        }
        if silencioso { return "Ainda não respondeu hoje" }
        return motivos.first?.texto ?? "Sem sinal nas respostas de hoje"
    }

    /// "Febre · 38,7 °C". Sem valor, só o sintoma — "Diarreia · sim" não informa nada.
    private func descricao(_ regra: RegraDisparada) -> String {
        let valor = Formato.observado(regra)
        return valor.isEmpty ? regra.sintoma.nome : "\(regra.sintoma.nome) · \(valor)"
    }
}
