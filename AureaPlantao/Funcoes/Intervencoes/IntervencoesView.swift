import SwiftUI

// Acompanhamento de intervenções (bloco 7 dos prints; `apps/web/src/app/painel/intervencoes`).
//
// Responde a pergunta que ficava sem dono: o que aconteceu DEPOIS que a enfermagem ligou.
// Sem esta tela a conduta ficava no prontuário e o follow-up vivia na memória de quem
// atendeu — e memória não passa de plantão para plantão.

/// `GET /painel/intervencoes` — conferido com curl em 25/09/2026 (enfermagem@).
struct AcompanhamentoDeIntervencoes: Decodable, Sendable {
    let itens: [IntervencaoEmAcompanhamento]
    /// `abertas` e `total` contam SÓ o que veio na lista (a API corta em 200).
    let resumo: Resumo

    struct Resumo: Decodable, Sendable {
        let abertas: Int
        let total: Int
    }
}

struct IntervencaoEmAcompanhamento: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let pacienteId: String
    /// 🔴 Aqui é o NOME (texto), não um objeto paciente.
    let paciente: String
    let sessaoId: String
    /// Sintoma da regra mais grave da classificação original. `null` quando a sessão não
    /// tem classificação ou a explicação é de um formato antigo.
    let motivo: Sintoma?
    let justificativa: String?
    let classificacao: Classificacao?
    let situacao: DesfechoDaIntervencao
    let conduta: String
    /// 🔴 Nome do profissional em texto; no histórico do prontuário é objeto `{nome, funcao}`.
    let profissional: String
    let contatoRealizadoEm: Date
    let registradaEm: Date

    /// Ordem de leitura do web: encaminhado ao PA no topo (o paciente saiu do alcance da
    /// equipe), resolvido por último (não pede ação).
    var peso: Int {
        switch situacao {
        case .encaminhadoAoPA: 0
        case .aguardandoRetorno: 1
        case .reavaliar: 2
        case .emAcompanhamento: 3
        case .desconhecido: 4
        case .resolvido: 5
        }
    }
}

/// Leva ao prontuário a partir de uma intervenção. Tipo próprio para o `navigationDestination`
/// desta tela não disputar com o de outras pilhas.
struct ProntuarioPorIntervencao: Hashable {
    let pacienteId: String
    let nome: String
}

enum FiltroDeIntervencoes: Hashable {
    case abertas, todas
}

@MainActor
@Observable
final class IntervencoesStore {
    private(set) var carga: Carga<AcompanhamentoDeIntervencoes> = .carregando
    private(set) var filtro: FiltroDeIntervencoes = .abertas
    private let api: ClienteAPI

    /// `nonisolated`: a tela é criada por `telaSecundaria(_:)`, função fora do ator principal.
    nonisolated init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        // 🔴 O parâmetro vai SÓ quando é `true`. A API usa `z.coerce.boolean()`, que lê a
        // string "false" como verdadeira: `?incluirResolvidas=false` devolve as resolvidas
        // também (o web cai nisso e mostra resolvidas no filtro "só as abertas").
        let consulta = filtro == .todas ? [URLQueryItem(name: "incluirResolvidas", value: "true")] : []
        do {
            carga = .pronto(try await api.obter("/painel/intervencoes", consulta: consulta))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    func trocar(para novo: FiltroDeIntervencoes) async {
        guard novo != filtro else { return }
        filtro = novo
        // Troca de conjunto: a lista antiga não vale para o filtro novo — esqueleto.
        carga = .carregando
        await carregar()
    }

    /// Na ordem do web: por desfecho e, dentro do mesmo desfecho, o mais antigo primeiro —
    /// quem espera há mais tempo é quem corre risco de ser esquecido.
    var linhas: [IntervencaoEmAcompanhamento] {
        (carga.valor?.itens ?? []).sorted {
            $0.peso != $1.peso ? $0.peso < $1.peso : $0.registradaEm < $1.registradaEm
        }
    }

    func contar(_ desfecho: DesfechoDaIntervencao) -> Int {
        (carga.valor?.itens ?? []).filter { $0.situacao == desfecho }.count
    }
}

struct IntervencoesView: View {
    @State private var store = IntervencoesStore()
    @State private var filtro: FiltroDeIntervencoes = .abertas

    /// Criada por `telaSecundaria(_:)`, que não roda no ator principal.
    nonisolated init() {}

    var body: some View {
        TelaRolavel(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Plantão",
                titulo: "Intervenções",
                contexto: "O que aconteceu depois do contato. Intervenção sem desfecho registrado é paciente esperando retorno que ninguém sabe que prometeu."
            )

            if let dados = store.carga.valor {
                Indicadores(abertas: dados.resumo.abertas,
                            encaminhados: store.contar(.encaminhadoAoPA),
                            aguardando: store.contar(.aguardandoRetorno),
                            reavaliar: store.contar(.reavaliar))
            }

            SeletorDePilulas(
                opcoes: [
                    OpcaoDeSeletor(id: FiltroDeIntervencoes.abertas, titulo: "Em aberto",
                                   contador: store.carga.valor?.resumo.abertas),
                    OpcaoDeSeletor(id: FiltroDeIntervencoes.todas, titulo: "Incluir resolvidas",
                                   contador: store.filtro == .todas ? store.carga.valor?.resumo.total : nil),
                ],
                selecionado: $filtro
            )
            .padding(.horizontal, -Espaco.margem)

            ConteudoDaCarga(
                carga: store.carga,
                vazio: { $0.itens.isEmpty },
                tituloVazio: store.filtro == .abertas ? "Nenhuma intervenção em aberto." : "Nenhuma intervenção registrada.",
                textoVazio: store.filtro == .abertas
                    ? "Toda intervenção registrada foi encerrada. Vale conferir se alguma deixou de ser registrada."
                    : "Quando a equipe registrar uma conduta no prontuário, ela aparece aqui até o desfecho.",
                iconeVazio: "checkmark",
                tentarDeNovo: { Task { await store.carregar() } }
            ) { _ in
                VStack(spacing: Espaco.s) {
                    ForEach(Array(store.linhas.enumerated()), id: \.element.id) { i, item in
                        NavigationLink(value: ProntuarioPorIntervencao(pacienteId: item.pacienteId, nome: item.paciente)) {
                            CartaoDeIntervencao(item: item)
                        }
                        .buttonStyle(.pressionavel)
                        .entradaEscalonada(i)
                    }
                }
                if let dados = store.carga.valor, dados.itens.count >= 200 {
                    Text("Mostrando as 200 mais recentes.")
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoFraco)
                }
            }
        }
        // Dentro da pilha do "Mais": empurra o prontuário sem criar pilha própria.
        .navigationDestination(for: ProntuarioPorIntervencao.self) { destino in
            ProntuarioView(pacienteId: destino.pacienteId, nome: destino.nome, situacao: nil)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Volta do prontuário com conduta nova: a lista relê (sem esqueleto — o valor fica).
        .onAppear { Task { await store.carregar() } }
        .onChange(of: filtro) { _, novo in Task { await store.trocar(para: novo) } }
        .encerraSessaoNo401(store.carga.erro)
    }
}

// MARK: - Indicadores

private struct Indicadores: View {
    let abertas: Int
    let encaminhados: Int
    let aguardando: Int
    let reavaliar: Int

    var body: some View {
        VStack(spacing: Espaco.s) {
            CartaoDeIndicador(rotulo: "Em aberto", valor: "\(abertas)",
                              apoio: abertas == 1 ? "conduta esperando desfecho" : "condutas esperando desfecho",
                              destaque: true)
            HStack(spacing: Espaco.s) {
                CartaoDeIndicador(rotulo: "No PA", valor: "\(encaminhados)")
                    .accessibilityLabel("Encaminhados ao pronto atendimento: \(encaminhados)")
                CartaoDeIndicador(rotulo: "Retorno", valor: "\(aguardando)")
                    .accessibilityLabel("Aguardando retorno: \(aguardando)")
                CartaoDeIndicador(rotulo: "Reavaliar", valor: "\(reavaliar)")
                    .accessibilityLabel("A reavaliar: \(reavaliar)")
            }
        }
    }
}

// MARK: - Cartão

/// Uma intervenção: quem, por quê (a regra que disparou, por extenso), o que foi feito e em
/// que pé está. A cor do selo é da CLASSIFICAÇÃO de origem; o desfecho é dito por palavra.
private struct CartaoDeIntervencao: View {
    let item: IntervencaoEmAcompanhamento

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Iniciais(nome: item.paciente, tamanho: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.paciente)
                        .font(Tipo.corpoForte)
                        .foregroundStyle(Cor.texto)
                        .lineLimit(2)
                    Text("Registrada \(Formato.quando(item.registradaEm))")
                        .font(Tipo.apoio)
                        .monospacedDigit()
                        .foregroundStyle(Cor.textoFraco)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Cor.textoFraco.opacity(0.7))
            }

            PontoDeDesfecho(desfecho: item.situacao)

            // O motivo é o sintoma da regra mais grave — e a regra vem por extenso junto.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.motivo?.nome ?? "Motivo não registrado")
                        .font(Tipo.apoioForte)
                        .foregroundStyle(item.motivo == nil ? Cor.textoSuave : Cor.texto)
                    if let c = item.classificacao, item.justificativa != nil {
                        SeloClinico(situacao: c.situacao)
                    }
                }
                if let justificativa = item.justificativa {
                    Text(justificativa)
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Conduta").estiloDeRotulo()
                Text(item.conduta)
                    .font(Tipo.corpo)
                    .foregroundStyle(Cor.texto)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.profissional)
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
            }
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rotuloAcessivel)
        .accessibilityHint("Abre o prontuário")
    }

    private var rotuloAcessivel: String {
        var partes = [item.paciente, "Situação: \(item.situacao.nome)"]
        if let m = item.motivo { partes.append("Motivo: \(m.nome)") }
        if let c = item.classificacao, item.justificativa != nil { partes.append("Classificação \(c.situacao.nome)") }
        if let j = item.justificativa { partes.append(j) }
        partes.append("Conduta: \(item.conduta), por \(item.profissional)")
        partes.append("Registrada \(Formato.quando(item.registradaEm))")
        return partes.joined(separator: ". ")
    }
}
