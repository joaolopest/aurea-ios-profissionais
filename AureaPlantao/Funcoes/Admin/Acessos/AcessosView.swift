import Charts
import SwiftUI

/// Uma linha de `GET /admin/registro-de-acessos` — do jeito que a API manda (curl de
/// 25/09/2026), não do tipo do web: `ocorridoEm` (o web renomeia para `aconteceuEm`),
/// `usuario` como objeto `{email, perfil}` e `paciente` como `{nome}` ou `null`.
/// `email` é opcional porque o login do paciente é CPF — a coluna é anulável no banco.
struct RegistroDeAcesso: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let acao: String
    let rota: String
    let metodo: String
    let ip: String?
    let ocorridoEm: Date
    let usuario: Usuario
    let paciente: Paciente?

    struct Usuario: Decodable, Sendable, Hashable {
        let email: String?
        let perfil: String
    }

    struct Paciente: Decodable, Sendable, Hashable {
        let nome: String
    }

    var quem: String { usuario.email ?? "Paciente (entra por CPF)" }
}

enum NomesDoRegistro {
    /// `ROTULO_DA_ACAO` do web; ação nova aparece com o código, nunca some.
    static func acao(_ codigo: String) -> String {
        switch codigo {
        case "LOGIN": "Entrada no sistema"
        case "LOGIN_RECUSADO": "Entrada recusada"
        case "LOGOUT": "Saída do sistema"
        case "TROCA_DE_SENHA": "Troca de senha"
        case "CONSENTIMENTO_REGISTRADO": "Consentimento registrado"
        case "LEITURA_DE_HISTORICO": "Leitura de histórico"
        case "LEITURA_DE_PACIENTE": "Leitura de paciente"
        case "REGISTRO_DE_INTERVENCAO": "Registro de intervenção"
        case "ATENDIMENTO_DE_SOLICITACAO": "Atendimento de solicitação"
        case "CRIACAO_DE_CADASTRO": "Criação de cadastro"
        case "EDICAO_DE_CADASTRO": "Edição de cadastro"
        case "EDICAO_DE_ORIENTACAO": "Edição de orientação"
        case "EDICAO_DE_ALGORITMO": "Edição do algoritmo"
        case "PUBLICACAO_DE_ALGORITMO": "Publicação do algoritmo"
        case "VALIDACAO_CLINICA_DE_ALGORITMO": "Validação clínica do algoritmo"
        case "REPROCESSAMENTO_DE_HISTORICO": "Reprocessamento de histórico"
        case "EXPORTACAO_DE_PESQUISA": "Exportação de pesquisa"
        default: codigo
        }
    }

    static func perfil(_ codigo: String) -> String {
        switch codigo {
        case "ADMINISTRADOR": "administração"
        case "PROFISSIONAL": "equipe"
        case "PACIENTE": "paciente"
        default: codigo.lowercased()
        }
    }
}

@MainActor
@Observable
final class AcessosStore {
    private(set) var carga: Carga<[RegistroDeAcesso]> = .carregando
    var limite = 200

    nonisolated init() {}

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await ClienteAPI.compartilhado.obter(
                "/admin/registro-de-acessos", consulta: [URLQueryItem(name: "limite", value: "\(limite)")]))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }
}

/// A9 — Registro de acessos. Existe por LGPD: toda leitura de prontuário, exportação e
/// mudança do algoritmo fica rastreada. Não é telemetria de produto, é obrigação legal —
/// e por isso a tela mostra data e hora exatas, não "há 3 horas".
struct AcessosView: View {
    @State private var store = AcessosStore()
    @State private var filtro = "TODAS"

    /// Empurrada por `telaSecundaria`, que não é isolada no MainActor.
    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(rotulo: "Auditoria", titulo: "Registro de acessos",
                            contexto: "Toda leitura de prontuário, exportação e alteração do algoritmo fica registrada — exigência de LGPD, não telemetria de produto.")

            ConteudoDaCarga(carga: store.carga, vazio: { $0.isEmpty },
                            tituloVazio: "Nenhum acesso registrado.",
                            textoVazio: "O registro começa na primeira entrada no sistema. Se isto aparece com a equipe usando o AUREA, a trilha de LGPD parou de gravar.",
                            iconeVazio: "lock.doc",
                            tentarDeNovo: { Task { await store.carregar() } }) { registros in
                conteudo(registros)
            }
        }
        .telaEmpurradaDoAdmin()
        .task { await store.carregar() }
        .encerraSessaoNo401(store.carga.erro)
    }

    @ViewBuilder
    private func conteudo(_ registros: [RegistroDeAcesso]) -> some View {
        let ultimo = registros.first

        GradeDeIndicadoresDoAdmin {
            CartaoDeIndicador(rotulo: "Registros", valor: "\(registros.count)",
                              apoio: registros.count >= store.limite ? "os \(store.limite) mais recentes" : "todos os registrados",
                              destaque: true)
            CartaoDeIndicador(rotulo: "Usuários", valor: "\(Set(registros.map(\.quem)).count)", apoio: "distintos")
            CartaoDeIndicador(rotulo: "Tipos de ação", valor: "\(Set(registros.map(\.acao)).count)")
            CartaoDeIndicador(rotulo: "Último registro", valor: ultimo.map { DataDoAdmin.diaCurto($0.ocorridoEm) } ?? "nenhum",
                              apoio: ultimo.map { DataDoAdmin.anoEHora($0.ocorridoEm) })
        }

        Menu {
            ForEach([50, 100, 200], id: \.self) { n in
                Button {
                    Tato.selecao()
                    store.limite = n
                    Task { await store.carregar() }
                } label: {
                    if store.limite == n { Label("Últimos \(n)", systemImage: "checkmark") } else { Text("Últimos \(n)") }
                }
            }
        } label: {
            Label("Mostrando os \(store.limite) mais recentes", systemImage: "line.3.horizontal.decrease.circle")
                .font(Tipo.apoioForte)
                .foregroundStyle(Cor.azulProfundo)
                .frame(minHeight: 44)
        }
        .accessibilityHint("Escolhe quantos registros carregar. O máximo da API é 200.")

        VolumePorDia(registros: registros)

        let presentes = acoesPorFrequencia(registros)
        CabecalhoDeSecao(titulo: "Acessos")
        SeletorDePilulas(
            opcoes: [OpcaoDeSeletor(id: "TODAS", titulo: "Todas", contador: registros.count)]
                + presentes.map { OpcaoDeSeletor(id: $0.acao, titulo: NomesDoRegistro.acao($0.acao), contador: $0.total) },
            selecionado: $filtro
        )
        .padding(.horizontal, -Espaco.margem)

        let filtrados = filtro == "TODAS" ? registros : registros.filter { $0.acao == filtro }
        if filtrados.isEmpty {
            EstadoVazio(titulo: "Nenhum acesso deste tipo.", texto: "Nos registros carregados, ninguém fez esta ação.", icone: "line.3.horizontal.decrease")
                .superficie()
        } else {
            LazyVStack(spacing: Espaco.s) {
                ForEach(Array(filtrados.enumerated()), id: \.element.id) { i, r in
                    LinhaDeRegistro(registro: r).entradaEscalonada(i)
                }
            }
        }
    }

    private func acoesPorFrequencia(_ registros: [RegistroDeAcesso]) -> [(acao: String, total: Int)] {
        Dictionary(grouping: registros, by: \.acao)
            .map { (acao: $0.key, total: $0.value.count) }
            .sorted { $0.total == $1.total ? $0.acao < $1.acao : $0.total > $1.total }
    }
}

private struct LinhaDeRegistro: View {
    let registro: RegistroDeAcesso

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NomesDoRegistro.acao(registro.acao))
                    .font(Tipo.corpoForte)
                    .foregroundStyle(Cor.texto)
                Text("\(registro.quem) · \(NomesDoRegistro.perfil(registro.usuario.perfil))")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .lineLimit(2)
                // O paciente tocado importa mais que a rota para quem audita; a rota entra
                // quando não há paciente envolvido.
                Text(registro.paciente.map { "Paciente: \($0.nome)" } ?? "\(registro.metodo) \(registro.rota)")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoFraco)
                    .lineLimit(2)
                if let ip = registro.ip {
                    Text("Origem \(ip)")
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoFraco)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(DataDoAdmin.dia(registro.ocorridoEm)).font(Tipo.coluna).foregroundStyle(Cor.textoSuave)
                Text(DataDoAdmin.hora(registro.ocorridoEm)).font(Tipo.colunaForte).foregroundStyle(Cor.texto)
            }
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(NomesDoRegistro.acao(registro.acao)), \(registro.quem), \(registro.paciente.map { "paciente \($0.nome)" } ?? registro.rota), em \(DataDoAdmin.diaEHora(registro.ocorridoEm))")
    }
}

// MARK: - Volume por dia

/// Volume por dia, empilhado por tipo de ação — a paleta de dado do ADR-005, sem o
/// petróleo-teal. Registro de acesso é operação pura, e é exatamente por isso que aqui a
/// paleta fria pode aparecer: nenhuma barra diz nada sobre paciente.
///
/// Quatro ações mais frequentes ganham cor própria e o resto vira "Outras", no neutro —
/// repetir cor faria duas ações diferentes ficarem idênticas.
///
/// O dia é o do SERVIÇO (America/Sao_Paulo), não o do UTC: um pico de leitura de
/// prontuário às 22h não pode migrar para o dia seguinte numa tela de auditoria. (O web
/// agrupa pela string ISO, que está em UTC — o contrário do que o comentário de lá promete.)
private struct VolumePorDia: View {
    let registros: [RegistroDeAcesso]

    private static let cores: [Color] = [Color(hex: 0x35597F), Color(hex: 0x4C4A86), Color(hex: 0x74477A), Color(hex: 0x8A4668)]
    private static let neutro = Color(hex: 0x6F6F72)

    struct Parcela: Identifiable {
        let dia: String
        let serie: String
        let total: Int
        var id: String { dia + serie }
    }

    private var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        return c
    }

    private var montagem: (series: [String], parcelas: [Parcela], dias: [(rotulo: String, total: Int)]) {
        let contagem = Dictionary(grouping: registros, by: \.acao).mapValues(\.count)
        let principais = contagem.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(4).map(\.key)
        let temOutras = contagem.count > principais.count
        let series = principais.map(NomesDoRegistro.acao) + (temOutras ? ["Outras"] : [])

        let cal = calendario
        let porDia = Dictionary(grouping: registros) { cal.startOfDay(for: $0.ocorridoEm) }
        // Últimos 14 dias com registro. Barra fina demais não é gráfico, é textura.
        let dias = porDia.keys.sorted().suffix(14)

        var fmt = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).locale(Locale(identifier: "pt_BR"))
        fmt.timeZone = cal.timeZone

        var parcelas: [Parcela] = []
        var totais: [(String, Int)] = []
        for dia in dias {
            let rotulo = dia.formatted(fmt)
            let doDia = porDia[dia] ?? []
            totais.append((rotulo, doDia.count))
            for acao in principais {
                let n = doDia.filter { $0.acao == acao }.count
                if n > 0 { parcelas.append(Parcela(dia: rotulo, serie: NomesDoRegistro.acao(acao), total: n)) }
            }
            if temOutras {
                let n = doDia.filter { !principais.contains($0.acao) }.count
                if n > 0 { parcelas.append(Parcela(dia: rotulo, serie: "Outras", total: n)) }
            }
        }
        return (series, parcelas, totais.map { (rotulo: $0.0, total: $0.1) })
    }

    var body: some View {
        let m = montagem
        let cores = m.series.enumerated().map { i, s in s == "Outras" ? Self.neutro : Self.cores[min(i, Self.cores.count - 1)] }

        VStack(alignment: .leading, spacing: Espaco.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Volume por dia").font(Tipo.tituloDeBloco).foregroundStyle(Cor.texto)
                Spacer()
                Text(m.dias.count == 1 ? "1 dia" : "\(m.dias.count) dias").estiloDeRotulo()
            }
            Text("Serve para achar pico fora do horário e concentração num único tipo de acesso.")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)

            Chart(m.parcelas) { p in
                BarMark(x: .value("Dia", p.dia), y: .value("Registros", p.total))
                    .foregroundStyle(by: .value("Ação", p.serie))
            }
            .chartForegroundStyleScale(domain: m.series, range: cores)
            .chartXScale(domain: m.dias.map(\.rotulo))
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Cor.filete)
                    AxisValueLabel().font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                }
            }
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Registros de acesso por dia")
            .accessibilityValue(m.dias.map { "\($0.rotulo): \($0.total) registros" }.joined(separator: "; "))

            // Legenda com nome e total: o gráfico nunca depende só de cor.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(m.series.enumerated()), id: \.offset) { i, serie in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(cores[i]).frame(width: 12, height: 12)
                        Text(serie).font(Tipo.apoio).foregroundStyle(Cor.texto)
                        Spacer()
                        Text("\(m.parcelas.filter { $0.serie == serie }.map(\.total).reduce(0, +))")
                            .font(Tipo.apoioForte).monospacedDigit().foregroundStyle(Cor.textoSuave)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Espaco.l)
        .superficie()
    }
}
