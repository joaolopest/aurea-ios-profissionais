import SwiftUI

/// A4 — O que muda de uma versão para outra. É o que responde, antes de publicar, "o que
/// acontece com o paciente se eu apertar esse botão".
///
/// A diferença vem PRONTA do servidor (`/admin/limiares/:de/diferenca/:para`), comparando
/// regras pelo que elas decidem. O web calcula no cliente comparando por `id` — e o id é
/// da linha, novo a cada conjunto importado: contra a API real, toda regra apareceria
/// removida e reincluída. Aqui não.
struct DiferencaDeConjuntosView: View {
    let lista: LimiaresStore
    @State private var de: String?
    @State private var para: String?
    @State private var carga: Carga<DiferencaDeConjuntos>?

    init(lista: LimiaresStore, de: String?, para: String?) {
        self.lista = lista
        _de = State(initialValue: de)
        _para = State(initialValue: para)
    }

    private var conjuntos: [ConjuntoResumido] { lista.carga.valor ?? [] }

    var body: some View {
        TelaRolavel(aoAtualizar: { await comparar() }) {
            CabecalhoDeTela(rotulo: "Algoritmo", titulo: "Comparar versões",
                            contexto: "Regras que entraram, saíram ou mudaram de valor entre dois conjuntos, e o que mudou na política.")

            VStack(alignment: .leading, spacing: Espaco.m) {
                CampoDeEscolha(rotulo: "De (versão anterior)", opcoes: opcoes, selecionado: $de, dica: "Escolher conjunto")
                if let c = conjuntos.first(where: { $0.id == de }), !c.validadoClinicamente {
                    AvisoNaoValidado(versao: c.versao)
                }
                CampoDeEscolha(rotulo: "Para (versão nova)", opcoes: opcoes, selecionado: $para, dica: "Escolher conjunto")
                if let c = conjuntos.first(where: { $0.id == para }), !c.validadoClinicamente {
                    AvisoNaoValidado(versao: c.versao)
                }
            }
            .padding(Espaco.l)
            .superficie()

            resultado
        }
        .telaEmpurradaDoAdmin()
        .task {
            if lista.carga.valor == nil { await lista.carregar() }
            // Aberta da lista, sem par escolhido: a origem natural é o que vale hoje.
            if de == nil, para == nil { de = lista.publicado?.id }
        }
        .task(id: "\(de ?? "")|\(para ?? "")") { await comparar() }
        .encerraSessaoNo401(carga?.erro)
    }

    private var opcoes: [(valor: String, nome: String)] {
        conjuntos.map { (valor: $0.id, nome: "\($0.versao) · \($0.estado.nome.lowercased())") }
    }

    private func comparar() async {
        guard let de, let para else { carga = nil; return }
        let anterior = carga?.valor
        carga = .carregando
        do {
            let r: DiferencaDeConjuntos = try await ClienteAPI.compartilhado.obter("/admin/limiares/\(de)/diferenca/\(para)")
            withAnimation(Movimento.chegada) { carga = .pronto(r) }
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    @ViewBuilder
    private var resultado: some View {
        if de == nil || para == nil {
            EstadoVazio(titulo: "Escolha as duas versões.",
                        texto: "A de origem é a que vale hoje; a de destino é a que você pensa em publicar.",
                        icone: "arrow.left.arrow.right")
                .superficie()
        } else if de == para {
            EstadoVazio(titulo: "É o mesmo conjunto.", texto: "Escolha duas versões diferentes para ver o que muda.", icone: "equal")
                .superficie()
        } else if let carga {
            ConteudoDaCarga(carga: carga, linhasDeEsqueleto: 3, tentarDeNovo: { Task { await comparar() } }) { d in
                diferenca(d)
            }
        }
    }

    @ViewBuilder
    private func diferenca(_ d: DiferencaDeConjuntos) -> some View {
        if d.semDiferenca {
            EstadoVazio(titulo: "As duas versões decidem igual.",
                        texto: "Mesmas regras, mesmos valores, mesma política. Publicar uma no lugar da outra não muda a cor de nenhum check-in.",
                        icone: "equal")
                .superficie()
        } else {
            GradeDeIndicadoresDoAdmin {
                CartaoDeIndicador(rotulo: "Diferenças", valor: "\(d.total)", apoio: "\(d.de.versao) → \(d.para.versao)", destaque: true)
                CartaoDeIndicador(rotulo: "Mudaram", valor: "\(d.mudaram.count)", apoio: "mesmo corte, outro valor")
                CartaoDeIndicador(rotulo: "Entraram", valor: "\(d.entraram.count)")
                CartaoDeIndicador(rotulo: "Saíram", valor: "\(d.sairam.count)")
            }

            if !d.mudaram.isEmpty {
                CabecalhoDeSecao(titulo: "Mudaram", contagem: d.mudaram.count)
                ForEach(Array(d.mudaram.enumerated()), id: \.offset) { i, m in
                    CartaoDeAlteracao(titulo: NomesDoAlgoritmo.sintoma(m.sintoma), antes: NomesDoAlgoritmo.humanizar(m.antes), depois: NomesDoAlgoritmo.humanizar(m.depois))
                        .entradaEscalonada(i)
                }
            }
            if !d.politica.isEmpty {
                CabecalhoDeSecao(titulo: "Política", contagem: d.politica.count)
                ForEach(Array(d.politica.enumerated()), id: \.offset) { i, p in
                    let antes = NomesDoAlgoritmo.politica(campo: p.campo, valor: p.antes)
                    let depois = NomesDoAlgoritmo.politica(campo: p.campo, valor: p.depois)
                    CartaoDeAlteracao(titulo: antes.campo, antes: antes.valor, depois: depois.valor)
                        .entradaEscalonada(i)
                }
            }
            if !d.entraram.isEmpty {
                CabecalhoDeSecao(titulo: "Entraram", contagem: d.entraram.count)
                listaDeFrases(d.entraram, icone: "plus")
            }
            if !d.sairam.isEmpty {
                CabecalhoDeSecao(titulo: "Saíram", contagem: d.sairam.count)
                listaDeFrases(d.sairam, icone: "minus")
            }
        }

        if !d.regrasRepetidas.isEmpty {
            AvisoDoAdmin(titulo: "Regras cadastradas em dobro",
                         texto: "Não mudam o resultado, mas a segunda nunca acrescenta nada:\n" + d.regrasRepetidas.map { "• \($0)" }.joined(separator: "\n"),
                         grave: true)
        }

        AvisoDoAdmin(texto: "A comparação olha o que cada regra decide: campo, operador, valores e cor. Regra que muda de cor aparece como uma saindo e outra entrando. Mudança só no texto da justificativa não aparece aqui — confira no detalhe do conjunto.")
    }

    private func listaDeFrases(_ frases: [String], icone: String) -> some View {
        VStack(spacing: Espaco.s) {
            ForEach(Array(frases.enumerated()), id: \.offset) { i, frase in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: icone)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Cor.azulProfundo)
                    Text(NomesDoAlgoritmo.humanizar(frase))
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.texto)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Espaco.l)
                .superficie(raio: Raio.linha)
                .entradaEscalonada(i)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Antes e depois, um embaixo do outro — no telefone, duas colunas espremem a frase.
private struct CartaoDeAlteracao: View {
    let titulo: String
    let antes: String
    let depois: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo).estiloDeRotulo()
            VStack(alignment: .leading, spacing: 2) {
                Text("Antes").font(Tipo.apoioForte).foregroundStyle(Cor.textoFraco)
                Text(antes).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    .strikethrough(color: Cor.textoFraco.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Depois").font(Tipo.apoioForte).foregroundStyle(Cor.azulProfundo)
                Text(depois).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titulo). Antes: \(antes). Depois: \(depois).")
    }
}
