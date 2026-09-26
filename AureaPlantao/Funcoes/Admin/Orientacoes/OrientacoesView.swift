import SwiftUI

/// `GET /admin/orientacoes` — do jeito que a API manda (curl de 25/09/2026). O web lê só
/// `titulo` e renomeia `corpo` para `texto`; a resposta real traz também `ordem`,
/// `medicamento {nome}`, `verbeteId` e `avisoDeMedicamento` (a regra 8 do ADR-001 dita para
/// quem cadastra). `sintoma` nunca vem nulo — não existe orientação "geral" no banco, ao
/// contrário do que o tipo do web supõe.
struct OrientacoesDoConjunto: Decodable, Sendable {
    let conjunto: Conjunto?
    let orientacoes: [OrientacaoAoPaciente]

    struct Conjunto: Decodable, Sendable {
        let id: String
        let versao: String
        let publicadoEm: Date?
    }
}

struct OrientacaoAoPaciente: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let sintoma: String
    let classificacao: ClassificacaoDaRegra
    let protocoloId: String?
    let ordem: Int
    let titulo: String
    let corpo: String
    let medicamento: Medicamento?
    let verbeteId: String?
    let avisoDeMedicamento: String?

    struct Medicamento: Decodable, Sendable, Hashable {
        let nome: String
    }
}

@MainActor
@Observable
final class OrientacoesStore {
    private(set) var carga: Carga<OrientacoesDoConjunto> = .carregando

    nonisolated init() {}

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await ClienteAPI.compartilhado.obter("/admin/orientacoes"))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }
}

/// A8 — O que o paciente lê ao fim do check-in, por sintoma e classificação.
///
/// Somente leitura, como no web — mas por um motivo que o web não sabia: a API TEM escrita
/// (`POST`/`PATCH /admin/orientacoes`), só que ela nunca toca o conjunto publicado. Toda
/// escrita cai num rascunho clonado, e não existe rota que leia esse rascunho nem que o
/// publique. Um editor aqui gravaria, diria "salvo", e o texto nunca chegaria a paciente
/// nenhum nem voltaria a esta tela. Isso é mentir para quem edita; está no relatório.
struct OrientacoesView: View {
    @State private var store = OrientacoesStore()
    @State private var filtro = "TODOS"

    /// Empurrada por `telaSecundaria`, que não é isolada no MainActor.
    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(rotulo: "Algoritmo", titulo: "Orientações",
                            contexto: "Os textos que o paciente recebe ao final do check-in, por sintoma e classificação.")

            ConteudoDaCarga(carga: store.carga,
                            vazio: { $0.conjunto == nil || $0.orientacoes.isEmpty },
                            tituloVazio: "Nenhuma orientação publicada.",
                            textoVazio: "Sem orientação, o check-in termina sem conduta: o paciente é classificado e não recebe o que fazer.",
                            iconeVazio: "text.book.closed",
                            tentarDeNovo: { Task { await store.carregar() } }) { dados in
                conteudo(dados)
            }
        }
        .telaEmpurradaDoAdmin()
        .task { await store.carregar() }
        .encerraSessaoNo401(store.carga.erro)
    }

    @ViewBuilder
    private func conteudo(_ dados: OrientacoesDoConjunto) -> some View {
        let orientacoes = dados.orientacoes
        let cobertos = Set(orientacoes.map(\.sintoma))
        let descobertos = ArvoreDoAlgoritmo.sintomas.filter { !cobertos.contains($0) }
        // O buraco que tem consequência: sintoma que pode sair amarelo ou vermelho e não tem
        // texto para aquela cor. O paciente é classificado e a tela de resultado termina vazia.
        let lacunas = ArvoreDoAlgoritmo.sintomas.flatMap { s in
            [ClassificacaoDaRegra.amarelo, .vermelho].compactMap { c in
                orientacoes.contains { $0.sintoma == s && $0.classificacao == c } ? nil : "\(NomesDoAlgoritmo.sintoma(s)) \(c.nome.lowercased())"
            }
        }

        if let conjunto = dados.conjunto {
            Text("Conjunto \(conjunto.versao)\(conjunto.publicadoEm.map { " · publicado em \(DataDoAdmin.dia($0))" } ?? "")")
                .font(Tipo.apoio)
                .monospacedDigit()
                .foregroundStyle(Cor.textoSuave)
        }

        GradeDeIndicadoresDoAdmin {
            CartaoDeIndicador(rotulo: "Orientações", valor: "\(orientacoes.count)", apoio: "no conjunto publicado", destaque: true)
            CartaoDeIndicador(rotulo: "Sintomas cobertos", valor: "\(cobertos.count)", apoio: "de \(ArvoreDoAlgoritmo.sintomas.count) do check-in")
            CartaoDeIndicador(rotulo: "Sem orientação", valor: "\(descobertos.count)",
                              apoio: descobertos.isEmpty ? "todo sintoma tem texto" : descobertos.map(NomesDoAlgoritmo.sintoma).joined(separator: ", "))
            CartaoDeIndicador(rotulo: "Citam remédio", valor: "\(orientacoes.filter { $0.medicamento != nil }.count)",
                              apoio: "só chegam a quem tem a prescrição")
        }

        if !lacunas.isEmpty {
            AvisoDoAdmin(titulo: "Classificação sem conduta",
                         texto: "Estes resultados não têm texto para o paciente: \(lacunas.joined(separator: ", ")). O check-in termina sem dizer o que fazer.",
                         grave: true)
        }

        AvisoDoAdmin(titulo: "Edição ainda não disponível",
                     texto: "O AUREA grava a edição de uma orientação num rascunho que ainda não pode ser aberto nem publicado. Um editor aqui diria \"salvo\" e o texto nunca chegaria ao paciente — por isso a tela é só de leitura até a publicação de orientações existir.")

        let presentes = ArvoreDoAlgoritmo.sintomas.filter(cobertos.contains)
            + cobertos.subtracting(ArvoreDoAlgoritmo.sintomas).sorted()
        SeletorDePilulas(
            opcoes: [OpcaoDeSeletor(id: "TODOS", titulo: "Todos", contador: orientacoes.count)]
                + presentes.map { s in OpcaoDeSeletor(id: s, titulo: NomesDoAlgoritmo.sintoma(s), contador: orientacoes.filter { $0.sintoma == s }.count) },
            selecionado: $filtro
        )
        .padding(.horizontal, -Espaco.margem)

        ForEach(presentes.filter { filtro == "TODOS" || $0 == filtro }, id: \.self) { sintoma in
            let doSintoma = orientacoes.filter { $0.sintoma == sintoma }
                .sorted { ($0.classificacao.peso, -$0.ordem) > ($1.classificacao.peso, -$1.ordem) }
            VStack(alignment: .leading, spacing: Espaco.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(NomesDoAlgoritmo.sintoma(sintoma))
                        .font(Tipo.tituloDeBloco)
                        .foregroundStyle(Cor.texto)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(doSintoma.count == 1 ? "1 orientação" : "\(doSintoma.count) orientações")
                        .font(Tipo.apoio).monospacedDigit().foregroundStyle(Cor.textoFraco)
                }
                .padding(.top, Espaco.s)
                ForEach(Array(doSintoma.enumerated()), id: \.element.id) { i, o in
                    CartaoDeOrientacao(orientacao: o).entradaEscalonada(i)
                }
            }
        }
    }
}

/// A orientação como o paciente vai ler, inteira. A cor é a classificação que a dispara —
/// é faixa clínica de verdade, por isso passa pelo `SeloClinico`.
private struct CartaoDeOrientacao: View {
    let orientacao: OrientacaoAoPaciente

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let s = orientacao.classificacao.situacao {
                    SeloClinico(situacao: s)
                } else {
                    Text(orientacao.classificacao.nome).font(Tipo.rotulo).foregroundStyle(Cor.textoSuave)
                }
                Spacer(minLength: 0)
                Text("ordem \(orientacao.ordem)")
                    .font(Tipo.apoio)
                    .monospacedDigit()
                    .foregroundStyle(Cor.textoFraco)
            }
            Text(orientacao.titulo)
                .font(Tipo.corpoForte)
                .foregroundStyle(Cor.texto)
            Text(orientacao.corpo)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
            if let aviso = orientacao.avisoDeMedicamento {
                Label(aviso, systemImage: "pills")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.texto)
                    .padding(Espaco.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficie(.afundado, raio: Raio.controle)
            }
            if orientacao.verbeteId != nil || orientacao.protocoloId != nil {
                HStack(spacing: Espaco.m) {
                    if orientacao.verbeteId != nil {
                        Label("Leva a um verbete da biblioteca", systemImage: "book")
                    }
                    if orientacao.protocoloId != nil {
                        Label("Só num protocolo", systemImage: "list.bullet.clipboard")
                    }
                }
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoFraco)
            }
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .accessibilityElement(children: .combine)
    }
}
