import SwiftUI

/// Resumo de `GET /admin/exportacao/pesquisa`, só para a tela contar o que vai no arquivo.
/// O arquivo em si sai com os bytes que o servidor montou — nenhum modelo no meio que possa
/// descartar campo da pesquisa.
///
/// ⚠️ Modelado do CÓDIGO da rota (`rotas/conteudo-e-pesquisa.ts`), não de curl: nenhuma
/// conta de demonstração tem `EXPORTAR_CONJUNTO_DE_PESQUISA`, e a rota responde 403 a todas.
struct ResumoDaExportacao: Decodable, Sendable {
    let geradoEm: Date
    let participantes: [Participante]

    struct Participante: Decodable, Sendable {
        let participanteId: String
        let sessoes: [Sessao]
    }

    struct Sessao: Decodable, Sendable {
        let respostas: [Qualquer]
        let classificacoes: [Qualquer]
    }

    /// Conta o item sem ler o conteúdo.
    struct Qualquer: Decodable, Sendable {
        init(from decoder: Decoder) throws {}
    }

    var sessoes: Int { participantes.map(\.sessoes.count).reduce(0, +) }
    var respostas: Int { participantes.flatMap(\.sessoes).map(\.respostas.count).reduce(0, +) }
    var classificacoes: Int { participantes.flatMap(\.sessoes).map(\.classificacoes.count).reduce(0, +) }
}

/// Arquivo pronto para compartilhar.
struct ExportacaoPronta: Sendable {
    let resumo: ResumoDaExportacao
    let arquivo: URL
}

@MainActor
@Observable
final class PesquisaStore {
    private(set) var estado: Carga<ExportacaoPronta>?

    nonisolated init() {}

    func exportar(de: Date?, ate: Date?) async {
        estado = .carregando
        var consulta: [URLQueryItem] = []
        let iso = Date.ISO8601FormatStyle()
        if let de { consulta.append(URLQueryItem(name: "de", value: de.formatted(iso))) }
        if let ate { consulta.append(URLQueryItem(name: "ate", value: ate.formatted(iso))) }
        do {
            let dados = try await ChamadaDoAdmin.compartilhada.bruto("/admin/exportacao/pesquisa", consulta: consulta)
            let resumo = try ClienteAPI.decodificador.decode(ResumoDaExportacao.self, from: dados)
            let nome = "aurea-pesquisa-\(resumo.geradoEm.formatted(.iso8601.year().month().day())).json"
            let url = FileManager.default.temporaryDirectory.appending(path: nome)
            // Pseudonimizado não é público: o arquivo fica cifrado enquanto o aparelho está
            // travado, e some quando a pessoa sai da tela.
            try dados.write(to: url, options: [.atomic, .completeFileProtection])
            estado = .pronto(ExportacaoPronta(resumo: resumo, arquivo: url))
        } catch let erro as DecodingError {
            estado = .falhou(.formatoInesperado(String(describing: erro)), anterior: nil)
        } catch {
            estado = .falhou(ErroDaAPI(error), anterior: nil)
        }
    }

    func descartarArquivo() {
        if let url = estado?.valor?.arquivo { try? FileManager.default.removeItem(at: url) }
    }
}

/// Exportação do conjunto de pesquisa — regra 7 do ADR-001: a base operacional e o conjunto
/// de pesquisa são coisas separadas. O que sai daqui é pseudonimizado por desenho, e a tela
/// diz o que sai e o que fica, porque é isso que o Comitê de Ética vai perguntar.
struct PesquisaView: View {
    @State private var store = PesquisaStore()
    @State private var comPeriodo = false
    @State private var de = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var ate = Date.now
    @State private var erroDePeriodo: String?

    /// Empurrada por `telaSecundaria`, que não é isolada no MainActor.
    nonisolated init() {}

    var body: some View {
        TelaRolavel {
            CabecalhoDeTela(rotulo: "Pesquisa", titulo: "Conjunto de pesquisa",
                            contexto: "Sessões de check-in, respostas e classificações dos participantes do estudo, em arquivo JSON pseudonimizado.")

            CabecalhoDeSecao(titulo: "O que sai no arquivo")
            VStack(alignment: .leading, spacing: 10) {
                item("checkmark", "Código do participante, idade em anos, sexo e diagnóstico.")
                item("checkmark", "Cada sessão de check-in, com as respostas cruas e as classificações — e a versão do conjunto de limiares que produziu cada uma.")
                item("xmark", "Nome, CPF, e-mail, telefone, endereço e a data de nascimento completa.")
                item("xmark", "O identificador do prontuário, condutas da enfermagem e nome de profissional.")
                item("xmark", "Quem saiu do estudo: o consentimento retirado vale daqui em diante.")
            }
            .padding(Espaco.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .superficie()

            AvisoDoAdmin(texto: "Cada exportação entra no registro de acessos como leitura do histórico de cada participante — é o pior caso da LGPD, e fica rastreado como tal.")
            AvisoNaoValidado()

            CabecalhoDeSecao(titulo: "Período")
            CampoInterruptor(titulo: "Só um período", explicacao: "Sem período, saem todas as sessões registradas.", ligado: $comPeriodo)
            if comPeriodo {
                CampoDeData(rotulo: "De", data: $de, intervalo: Date.distantPast...ate)
                CampoDeData(rotulo: "Até", data: $ate, intervalo: de...Date.now)
            }
            if let erroDePeriodo {
                AvisoDoAdmin(texto: erroDePeriodo, grave: true)
            }

            resultado

            BotaoPrimario(titulo: store.estado?.valor == nil ? "Gerar exportação" : "Gerar de novo",
                          icone: "square.and.arrow.down",
                          carregando: store.estado.map { if case .carregando = $0 { true } else { false } } ?? false) {
                Task { await exportar() }
            }
        }
        .telaEmpurradaDoAdmin()
        .encerraSessaoNo401(store.estado?.erro)
        .onDisappear { store.descartarArquivo() }
    }

    private func item(_ icone: String, _ texto: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icone)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(icone == "checkmark" ? Cor.azulProfundo : Cor.textoFraco)
                .accessibilityLabel(icone == "checkmark" ? "Sai:" : "Não sai:")
            Text(texto)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.texto)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resultado: some View {
        if let erro = store.estado?.erro {
            CartaoDeErro(erro: erro) { Task { await exportar() } }
        } else if let pronta = store.estado?.valor {
            let r = pronta.resumo
            GradeDeIndicadoresDoAdmin {
                CartaoDeIndicador(rotulo: "Participantes", valor: "\(r.participantes.count)", destaque: true)
                CartaoDeIndicador(rotulo: "Sessões", valor: "\(r.sessoes)")
                CartaoDeIndicador(rotulo: "Respostas", valor: "\(r.respostas)")
                CartaoDeIndicador(rotulo: "Classificações", valor: "\(r.classificacoes)")
            }
            Text("Gerado em \(DataDoAdmin.diaEHora(r.geradoEm)).")
                .font(Tipo.apoio)
                .monospacedDigit()
                .foregroundStyle(Cor.textoSuave)
            ShareLink(item: pronta.arquivo) {
                Label("Compartilhar o arquivo JSON", systemImage: "square.and.arrow.up")
                    .font(Tipo.corpoForte)
                    .foregroundStyle(Cor.texto)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Cor.superficie))
                    .overlay(Capsule().strokeBorder(Cor.fileteForte, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressionavel)
        }
    }

    private func exportar() async {
        erroDePeriodo = nil
        if comPeriodo {
            let cal = Calendar.current
            let inicio = cal.startOfDay(for: de)
            // "Até" inclui o dia inteiro: a rota compara com `lte`.
            let fim = cal.date(byAdding: DateComponents(day: 1, second: -1), to: cal.startOfDay(for: ate)) ?? ate
            guard fim >= inicio else {
                erroDePeriodo = "A data final vem antes da inicial."
                return
            }
            store.descartarArquivo()
            await store.exportar(de: inicio, ate: fim)
        } else {
            store.descartarArquivo()
            await store.exportar(de: nil, ate: nil)
        }
        if store.estado?.valor != nil { Tato.sucesso() } else { Tato.erro() }
    }
}
