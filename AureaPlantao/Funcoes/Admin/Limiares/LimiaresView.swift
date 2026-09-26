import SwiftUI

@MainActor
@Observable
final class LimiaresStore {
    private(set) var carga: Carga<[ConjuntoResumido]> = .carregando
    private let api: ClienteAPI

    init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/admin/limiares"))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    var publicado: ConjuntoResumido? { carga.valor?.first(where: \.ativo) }
}

/// Os lugares dentro da aba Algoritmo. Ficam num enum só para que o Início do admin empurre
/// as mesmas telas sem saber como são montadas.
enum RotaDoAlgoritmo: Hashable {
    case conjunto(id: String)
    case diferenca(de: String?, para: String?)
    case novo(baseId: String?)
}

/// Monta a tela de uma rota. Quem empurra passa o store da lista, para que publicar ou criar
/// um conjunto atualize a lista de trás sem esperar o puxar-para-atualizar.
@MainActor @ViewBuilder
func telaDoAlgoritmo(_ rota: RotaDoAlgoritmo, store: LimiaresStore) -> some View {
    switch rota {
    case .conjunto(let id): DetalheDoConjuntoView(conjuntoId: id, lista: store)
    case .diferenca(let de, let para): DiferencaDeConjuntosView(lista: store, de: de, para: para)
    case .novo(let base): NovoConjuntoView(lista: store, baseId: base)
    }
}

/// A1 — Conjuntos de limiares. O algoritmo inteiro é esta lista: versões congeladas do corte
/// clínico (ADR-001, regra 1). Só uma classifica pacientes reais por vez — a publicada — e a
/// tela tem que deixar isso óbvio à primeira vista.
struct LimiaresView: View {
    @State private var store = LimiaresStore()
    @Environment(Sessao.self) private var sessao

    private var podeEditar: Bool { sessao.eu?.permissoes.contains("EDITAR_ALGORITMO") == true }

    var body: some View {
        TelaDeAba(aoAtualizar: { await store.carregar() }) {
            CabecalhoDeTela(
                rotulo: "Algoritmo",
                titulo: "Conjuntos de limiares",
                contexto: "Cada linha é uma versão inteira do algoritmo de classificação, congelada. Publicar troca qual delas classifica pacientes reais.",
                mostrarConta: true
            )
            // Dentro da pilha da aba — fora dela o link não teria para onde empurrar.
            .navigationDestination(for: RotaDoAlgoritmo.self) { telaDoAlgoritmo($0, store: store) }

            ConteudoDaCarga(
                carga: store.carga,
                vazio: { $0.isEmpty },
                tituloVazio: "Nenhum conjunto de limiares.",
                textoVazio: podeEditar
                    ? "Sem conjunto, o algoritmo não tem o que aplicar. Crie o primeiro."
                    : "Sem conjunto, o algoritmo não tem o que aplicar. Criar exige a permissão de editar o algoritmo.",
                iconeVazio: "slider.horizontal.3",
                tentarDeNovo: { Task { await store.carregar() } }
            ) { conjuntos in
                ListaDeConjuntos(conjuntos: conjuntos, podeEditar: podeEditar)
            }

            if store.carga.valor?.isEmpty == true, podeEditar {
                NavigationLink(value: RotaDoAlgoritmo.novo(baseId: nil)) {
                    Label("Novo conjunto", systemImage: "plus")
                        .font(Tipo.corpoForte)
                        .foregroundStyle(Cor.textoInvertido)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Capsule().fill(Cor.azulProfundo))
                }
                .buttonStyle(.pressionavel)
            }
        }
        .task { await store.carregar() }
    }
}

/// O miolo da lista, com os indicadores do topo. Separado para o Início reaproveitar a
/// leitura do conjunto publicado sem repetir a conta.
private struct ListaDeConjuntos: View {
    let conjuntos: [ConjuntoResumido]
    let podeEditar: Bool

    private var publicado: ConjuntoResumido? { conjuntos.first(where: \.ativo) }
    private var aguardandoValidacao: Int { conjuntos.filter { !$0.validadoClinicamente }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            // O destaque abre a grade: é o número que importa numa tela de algoritmo sem
            // assinatura clínica. Os outros três são inventário.
            // A versão publicada é texto longo ("rascunho-0"): em meia largura, a 30 pt, ela
            // quebra no hífen. Ganha a largura inteira; a contagem de regras vira apoio dela.
            CartaoDeIndicador(rotulo: "Publicado", valor: publicado?.versao ?? "nenhum",
                              apoio: publicado.map { "classificando pacientes agora · \($0.regras) regras" }
                                  ?? "nenhum conjunto classifica agora")
            GradeDeIndicadoresDoAdmin {
                CartaoDeIndicador(rotulo: "Aguardam validação", valor: "\(aguardandoValidacao)",
                                  apoio: "sem assinatura clínica", destaque: true)
                CartaoDeIndicador(rotulo: "Conjuntos", valor: "\(conjuntos.count)", apoio: "cadastrados")
            }

            HStack(spacing: Espaco.s) {
                if podeEditar {
                    NavigationLink(value: RotaDoAlgoritmo.novo(baseId: publicado?.id)) {
                        rotuloDeAcao("Novo conjunto", icone: "plus")
                    }
                    .buttonStyle(.pressionavel)
                }
                if conjuntos.count >= 2 {
                    NavigationLink(value: RotaDoAlgoritmo.diferenca(de: nil, para: nil)) {
                        rotuloDeAcao("Comparar versões", icone: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.pressionavel)
                }
            }

            CabecalhoDeSecao(titulo: "Todos os conjuntos", contagem: conjuntos.count)
            VStack(spacing: Espaco.s) {
                ForEach(Array(conjuntos.enumerated()), id: \.element.id) { i, conjunto in
                    NavigationLink(value: RotaDoAlgoritmo.conjunto(id: conjunto.id)) {
                        LinhaDeConjunto(conjunto: conjunto)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }

            AvisoDoAdmin(texto: "Apenas um conjunto fica publicado por vez. É ele, e só ele, que classifica o check-in dos pacientes hoje.")
        }
    }

    /// Mesmo desenho do `BotaoDeAcaoEmLinha`, mas como rótulo de `NavigationLink`.
    private func rotuloDeAcao(_ titulo: String, icone: String) -> some View {
        Label(titulo, systemImage: icone)
            .font(Tipo.apoioForte)
            .foregroundStyle(Cor.azulProfundo)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(Cor.azulGelo.opacity(0.45)))
            .contentShape(Capsule())
    }
}

struct LinhaDeConjunto: View {
    let conjunto: ConjuntoResumido

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(conjunto.versao)
                    .font(Tipo.destaque)
                    .foregroundStyle(Cor.texto)
                    .lineLimit(2)
                Spacer(minLength: 8)
                SeloDeEstadoDoConjunto(estado: conjunto.estado)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Cor.textoFraco.opacity(0.7))
            }
            if conjunto.ativo {
                Text("Classificando pacientes agora")
                    .font(Tipo.apoioForte)
                    .foregroundStyle(Cor.azulProfundo)
            }
            Text(conjunto.descricao)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .lineLimit(2)
            Text("Origem: \(conjunto.origem)")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoFraco)
                .lineLimit(2)
            HStack(spacing: Espaco.m) {
                Text(conjunto.regras == 1 ? "1 regra" : "\(conjunto.regras) regras")
                Text("·")
                Text(conjunto.publicadoEm.map { "publicado em \(DataDoAdmin.dia($0))" } ?? "criado em \(DataDoAdmin.dia(conjunto.criadoEm))")
            }
            .font(Tipo.apoio)
            .monospacedDigit()
            .foregroundStyle(Cor.textoFraco)
            if !conjunto.validadoClinicamente {
                AvisoNaoValidado()
            }
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre as regras do conjunto")
    }
}
