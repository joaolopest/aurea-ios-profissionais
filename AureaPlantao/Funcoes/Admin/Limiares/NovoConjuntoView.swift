import SwiftUI

/// Uma regra ainda na mão de quem monta o conjunto. Carrega os campos que o formulário não
/// edita (janela do ciclo, protocolo) para que copiar um conjunto não os perca no caminho.
struct RascunhoDeRegra: Identifiable, Hashable, Sendable {
    let id = UUID()
    var ordem: Int
    var sintoma: String
    var campo: String
    var operador: OperadorDaRegra
    var valor: Double?
    var valorSecundario: Double?
    var valoresDeTexto: [String]?
    var classificacao: ClassificacaoDaRegra
    var justificativa: String
    var diaDoCicloMinimo: Int?
    var diaDoCicloMaximo: Int?
    var protocoloId: String?

    init(ordem: Int, sintoma: String, campo: String, operador: OperadorDaRegra, valor: Double?,
         valorSecundario: Double?, valoresDeTexto: [String]?, classificacao: ClassificacaoDaRegra,
         justificativa: String, diaDoCicloMinimo: Int? = nil, diaDoCicloMaximo: Int? = nil, protocoloId: String? = nil) {
        self.ordem = ordem
        self.sintoma = sintoma
        self.campo = campo
        self.operador = operador
        self.valor = valor
        self.valorSecundario = valorSecundario
        self.valoresDeTexto = valoresDeTexto
        self.classificacao = classificacao
        self.justificativa = justificativa
        self.diaDoCicloMinimo = diaDoCicloMinimo
        self.diaDoCicloMaximo = diaDoCicloMaximo
        self.protocoloId = protocoloId
    }

    init(copiaDe r: RegraDoConjunto) {
        self.init(ordem: r.ordem, sintoma: r.sintoma, campo: r.campo, operador: r.operador, valor: r.valor,
                  valorSecundario: r.valorSecundario, valoresDeTexto: r.valoresDeTexto, classificacao: r.classificacao,
                  justificativa: r.justificativa, diaDoCicloMinimo: r.diaDoCicloMinimo,
                  diaDoCicloMaximo: r.diaDoCicloMaximo, protocoloId: r.protocoloId)
    }

    var frase: String {
        NomesDoAlgoritmo.frase(sintoma: sintoma, campo: campo, operador: operador, valor: valor,
                               valorSecundario: valorSecundario, valoresDeTexto: valoresDeTexto,
                               diaMinimo: diaDoCicloMinimo, diaMaximo: diaDoCicloMaximo, protocoloId: protocoloId)
    }

    var paraEnviar: RegraParaEnviar {
        RegraParaEnviar(ordem: ordem, sintoma: sintoma, campo: campo, operador: operador.codigo,
                        valor: operador.precisaDeValor ? valor : nil,
                        valorSecundario: operador == .entre ? valorSecundario : nil,
                        valoresDeTexto: operador == .estaEm ? valoresDeTexto : nil,
                        classificacao: classificacao.codigo, justificativa: justificativa,
                        diaDoCicloMinimo: diaDoCicloMinimo, diaDoCicloMaximo: diaDoCicloMaximo, protocoloId: protocoloId)
    }
}

/// A3 — Novo conjunto de limiares. Nasce SEMPRE rascunho (a API garante): não classifica
/// ninguém até alguém com permissão de publicar passar pela confirmação.
///
/// Diferente do web, que monta o conjunto só em memória, aqui ele grava de verdade
/// (`POST /admin/limiares`) e é lido de volta antes de dizer "criado". E começa, por padrão,
/// de uma cópia do publicado: conjunto não se edita, e o jeito real de ajustar um corte é
/// copiar o que vale hoje, mudar a regra e publicar a cópia.
struct NovoConjuntoView: View {
    let lista: LimiaresStore
    let baseId: String?

    @State private var base: String?
    @State private var carregandoBase = false
    @State private var versao = ""
    @State private var descricao = ""
    @State private var origem = ""
    @State private var combinacao: String? = "PIOR_ISOLADO"
    @State private var antitermico: String? = "IGNORAR"
    @State private var abandono: String? = "NAO_CLASSIFICAR"
    @State private var regras: [RascunhoDeRegra] = []
    @State private var editando: RascunhoDeRegra?
    @State private var criandoRegra = false
    @State private var enviando = false
    @State private var erro: String?
    @State private var criado: ConjuntoCriado?
    @State private var identificando = false

    private static let emBranco = "EM_BRANCO"

    init(lista: LimiaresStore, baseId: String?) {
        self.lista = lista
        self.baseId = baseId
        _base = State(initialValue: baseId ?? Self.emBranco)
    }

    var body: some View {
        TelaRolavel {
            CabecalhoDeTela(rotulo: "Algoritmo", titulo: "Novo conjunto",
                            contexto: "Nasce como rascunho: não classifica ninguém até ser publicado. Regra sem justificativa não entra.")

            if let criado {
                sucesso(criado)
            } else {
                formulario
            }
        }
        .telaEmpurradaDoAdmin()
        .task {
            if lista.carga.valor == nil { await lista.carregar() }
        }
        .task(id: base) { await carregarBase() }
        .sheet(item: $editando) { regra in
            FolhaDeRegra(original: regra, proximaOrdem: proximaOrdem) { resultado in
                editando = nil
                if let i = regras.firstIndex(where: { $0.id == regra.id }) {
                    withAnimation(Movimento.interface) {
                        if let resultado { regras[i] = resultado } else { regras.remove(at: i) }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $identificando) {
            FolhaDeFormulario(rotulo: "\(regras.count) regras · rascunho", titulo: "Identificar o conjunto",
                              acao: "Salvar rascunho", icone: "tray.and.arrow.down",
                              enviando: enviando, erro: erro, enviar: { Task { await salvar() } }) {
                CampoDeEntrada(rotulo: "Versão", texto: $versao)
                CampoDeTextoLongo(rotulo: "Descrição", texto: $descricao, dica: "O que muda neste conjunto", linhas: 2)
                CampoDeEntrada(rotulo: "Origem dos números", texto: $origem)
                Text("De onde vêm os cortes: CTCAE v5.0, protocolo do serviço, provisório.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoFraco)
                Text("Nasce inativo. Não classifica ninguém até alguém com permissão publicar, pela confirmação do detalhe.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled(enviando)
        }
        .sheet(isPresented: $criandoRegra) {
            FolhaDeRegra(original: nil, proximaOrdem: proximaOrdem) { resultado in
                criandoRegra = false
                if let resultado { withAnimation(Movimento.interface) { regras.append(resultado) } }
            }
            .presentationDetents([.large])
        }
    }

    private var proximaOrdem: Int { (regras.map(\.ordem).max() ?? 0) + 1 }

    // MARK: Formulário

    @ViewBuilder
    private var formulario: some View {
        GradeDeIndicadoresDoAdmin {
            CartaoDeIndicador(rotulo: "Regras", valor: "\(regras.count)", apoio: "no rascunho")
            CartaoDeIndicador(rotulo: "Sintomas cobertos", valor: "\(Set(regras.map(\.sintoma)).count)",
                              apoio: "de \(ArvoreDoAlgoritmo.sintomas.count) do check-in")
        }

        CabecalhoDeSecao(titulo: "Ponto de partida")
        VStack(alignment: .leading, spacing: Espaco.s) {
            CampoDeEscolha(rotulo: "Começar a partir de", opcoes: opcoesDeBase, selecionado: $base)
            Text(base == Self.emBranco
                 ? "Todas as regras são escritas do zero."
                 : "As regras e a política do conjunto escolhido entram como ponto de partida. Trocar o ponto de partida descarta o que você mudou nas regras.")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
        }

        CabecalhoDeSecao(titulo: "Política de classificação")
        Text("São decisões clínicas, não preferências de interface: cada opção muda o resultado que o paciente recebe.")
            .font(Tipo.apoio)
            .foregroundStyle(Cor.textoSuave)
            .fixedSize(horizontal: false, vertical: true)
        politica("Combinação de sintomas", ["PIOR_ISOLADO", "DOIS_AMARELOS_VIRAM_VERMELHO"], $combinacao, NomesDoAlgoritmo.combinacao)
        politica("Efeito do antitérmico", ["IGNORAR", "ELEVAR_UM_NIVEL"], $antitermico, NomesDoAlgoritmo.antitermico)
        politica("Questionário abandonado", ["NAO_CLASSIFICAR", "PIOR_DOS_RESPONDIDOS"], $abandono, NomesDoAlgoritmo.abandono)

        HStack {
            CabecalhoDeSecao(titulo: "Regras", contagem: regras.count)
            BotaoDeAcaoEmLinha(titulo: "Adicionar regra") { criandoRegra = true }
        }
        .padding(.top, Espaco.s)

        if carregandoBase {
            ForEach(0..<3, id: \.self) { _ in LinhaDeEsqueleto() }
        } else if regras.isEmpty {
            EstadoVazio(titulo: "Nenhuma regra ainda.", texto: "Um conjunto precisa de pelo menos uma regra para ser salvo.", icone: "list.bullet")
                .superficie()
        } else {
            ForEach(ArvoreDoAlgoritmo.sintomas + outrosSintomas, id: \.self) { sintoma in
                let doSintoma = regras.filter { $0.sintoma == sintoma }.sorted { $0.ordem < $1.ordem }
                if !doSintoma.isEmpty {
                    Text(NomesDoAlgoritmo.sintoma(sintoma))
                        .font(Tipo.tituloDeBloco)
                        .foregroundStyle(Cor.texto)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(doSintoma) { regra in
                        Button {
                            Tato.selecao()
                            editando = regra
                        } label: {
                            LinhaDeRascunho(regra: regra)
                        }
                        .buttonStyle(.pressionavel)
                        .contextMenu {
                            Button("Remover regra", systemImage: "trash", role: .destructive) {
                                withAnimation(Movimento.interface) { regras.removeAll { $0.id == regra.id } }
                            }
                        }
                    }
                }
            }
        }

        if let erro, !identificando {
            AvisoDoAdmin(titulo: "Atenção", texto: erro, grave: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        // O texto (versão, descrição, origem) vai numa folha: esta tela não se afasta do
        // teclado (a casca das abas ignora a área do teclado), e a folha sim. É também o
        // último olhar antes de gravar.
        BotaoPrimario(titulo: "Salvar como rascunho…", icone: "tray.and.arrow.down") {
            erro = nil
            identificando = true
        }
        .padding(.top, Espaco.s)
    }

    private var outrosSintomas: [String] {
        Array(Set(regras.map(\.sintoma)).subtracting(ArvoreDoAlgoritmo.sintomas)).sorted()
    }

    private var opcoesDeBase: [(valor: String, nome: String)] {
        [(valor: Self.emBranco, nome: "Em branco")]
            + (lista.carga.valor ?? []).map { (valor: $0.id, nome: "\($0.versao) · \($0.estado.nome.lowercased())") }
    }

    private func politica(_ rotulo: String, _ codigos: [String], _ selecionado: Binding<String?>,
                          _ nomes: @escaping (String) -> (nome: String, explicacao: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CampoDeEscolha(rotulo: rotulo, opcoes: codigos.map { (valor: $0, nome: nomes($0).nome) }, selecionado: selecionado)
            if let atual = selecionado.wrappedValue {
                Text(nomes(atual).explicacao)
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sucesso(_ c: ConjuntoCriado) -> some View {
        VStack(alignment: .leading, spacing: Espaco.l) {
            EstadoVazio(titulo: "Rascunho \(c.versao) criado.", texto: c.aviso, icone: "tray.and.arrow.down")
                .superficie()
            NavigationLink(value: RotaDoAlgoritmo.conjunto(id: c.id)) {
                LinhaPadrao(icone: "slider.horizontal.3", titulo: "Abrir o rascunho",
                            apoio: "Conferir as regras, comparar com o publicado e publicar")
            }
            .buttonStyle(.pressionavel)
        }
    }

    // MARK: Ações

    private func carregarBase() async {
        guard let base, base != Self.emBranco else {
            if base == Self.emBranco, baseId != nil || !regras.isEmpty { regras = [] }
            return
        }
        carregandoBase = true
        defer { carregandoBase = false }
        do {
            let d: ConjuntoDetalhado = try await ClienteAPI.compartilhado.obter("/admin/limiares/\(base)")
            withAnimation(Movimento.chegada) {
                regras = d.regras.map(RascunhoDeRegra.init(copiaDe:))
                combinacao = d.politica.combinacao
                antitermico = d.politica.efeitoDoAntitermico
                abandono = d.politica.tratamentoDeAbandono
            }
        } catch {
            erro = "Não deu para copiar as regras do conjunto escolhido. \(ErroDaAPI(error).mensagem)"
        }
    }

    private func salvar() async {
        let v = versao.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = descricao.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = origem.trimmingCharacters(in: .whitespacesAndNewlines)

        // As mesmas regras do Zod da rota, ditas antes de gastar a viagem.
        var faltas: [String] = []
        if v.isEmpty || v.count > 60 { faltas.append("Versão: de 1 a 60 caracteres.") }
        if (lista.carga.valor ?? []).contains(where: { $0.versao == v }) { faltas.append("Já existe um conjunto com a versão “\(v)”.") }
        if d.count < 3 { faltas.append("Descrição: pelo menos 3 caracteres.") }
        if o.count < 3 || o.count > 255 { faltas.append("Origem: de 3 a 255 caracteres.") }
        if regras.isEmpty { faltas.append("Adicione pelo menos uma regra.") }
        guard faltas.isEmpty, let combinacao, let antitermico, let abandono else {
            Tato.erro()
            withAnimation(Movimento.interface) { erro = faltas.joined(separator: "\n") }
            return
        }

        enviando = true
        erro = nil
        defer { enviando = false }
        let corpo = NovoConjuntoDeLimiares(versao: v, descricao: d, origem: o, combinacao: combinacao,
                                           efeitoDoAntitermico: antitermico, tratamentoDeAbandono: abandono,
                                           regras: regras.map(\.paraEnviar))
        do {
            let c: ConjuntoCriado = try await ChamadaDoAdmin.compartilhada.enviar("/admin/limiares", corpo: corpo)
            // Lido de volta antes de dizer "criado": a lição dos campos que a API aceitava
            // com 200 e jogava fora.
            let gravado: ConjuntoDetalhado = try await ClienteAPI.compartilhado.obter("/admin/limiares/\(c.id)")
            guard gravado.regras.count == corpo.regras.count,
                  gravado.politica.combinacao == combinacao,
                  gravado.politica.efeitoDoAntitermico == antitermico,
                  gravado.politica.tratamentoDeAbandono == abandono else {
                Tato.aviso()
                erro = "O AUREA criou o rascunho \(c.versao), mas ele voltou diferente do enviado (\(gravado.regras.count) de \(corpo.regras.count) regras). Confira o rascunho antes de qualquer publicação."
                await lista.carregar()
                return
            }
            Tato.sucesso()
            await lista.carregar()
            identificando = false
            withAnimation(Movimento.chegada) { criado = c }
        } catch {
            Tato.erro()
            withAnimation(Movimento.interface) { erro = ErroDaAPI(error).mensagem }
        }
    }
}

private struct LinhaDeRascunho: View {
    let regra: RascunhoDeRegra

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let s = regra.classificacao.situacao { SeloClinico(situacao: s) }
                    Text(regra.frase)
                        .font(Tipo.corpoForte)
                        .foregroundStyle(Cor.texto)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(regra.justificativa)
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Cor.textoFraco)
        }
        .padding(Espaco.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edita a regra. Toque e segure para remover.")
    }
}

// MARK: - Folha de regra

/// Uma regra por folha. O campo sai da árvore do sintoma e o operador sai do tipo do campo:
/// o formulário não deixa montar regra que a API recusaria por incoerência.
private struct FolhaDeRegra: View {
    let original: RascunhoDeRegra?
    let proximaOrdem: Int
    /// `nil` = remover (só na edição).
    let concluir: (RascunhoDeRegra?) -> Void

    @State private var sintoma: String?
    @State private var campo: String?
    @State private var operador: OperadorDaRegra?
    @State private var valor = ""
    @State private var valorFinal = ""
    @State private var opcoes: Set<String> = []
    @State private var classificacao: ClassificacaoDaRegra?
    @State private var justificativa = ""
    @State private var erro: String?

    init(original: RascunhoDeRegra?, proximaOrdem: Int, concluir: @escaping (RascunhoDeRegra?) -> Void) {
        self.original = original
        self.proximaOrdem = proximaOrdem
        self.concluir = concluir
        _sintoma = State(initialValue: original?.sintoma ?? ArvoreDoAlgoritmo.sintomas.first)
        _campo = State(initialValue: original?.campo)
        _operador = State(initialValue: original?.operador)
        _valor = State(initialValue: original?.valor.map(NomesDoAlgoritmo.numero) ?? "")
        _valorFinal = State(initialValue: original?.valorSecundario.map(NomesDoAlgoritmo.numero) ?? "")
        _opcoes = State(initialValue: Set(original?.valoresDeTexto ?? []))
        _classificacao = State(initialValue: original?.classificacao)
        _justificativa = State(initialValue: original?.justificativa ?? "")
    }

    private var definicao: ArvoreDoAlgoritmo.Campo? {
        guard let sintoma, let campo else { return nil }
        return ArvoreDoAlgoritmo.campo(campo, de: sintoma)
    }

    var body: some View {
        FolhaDeFormulario(rotulo: "Regra de corte", titulo: original == nil ? "Nova regra" : "Editar regra",
                          acao: "Guardar regra", erro: erro, enviar: guardar) {
            CampoDeEscolha(rotulo: "Sintoma",
                           opcoes: ArvoreDoAlgoritmo.sintomas.map { (valor: $0, nome: NomesDoAlgoritmo.sintoma($0)) },
                           selecionado: $sintoma)
            CampoDeEscolha(rotulo: "Campo observado",
                           opcoes: ArvoreDoAlgoritmo.campos(de: sintoma ?? "").map { (valor: $0.codigo, nome: $0.nome) },
                           selecionado: $campo, dica: "Escolher campo")
            if let definicao {
                CampoDeEscolha(rotulo: "Operador",
                               opcoes: ArvoreDoAlgoritmo.operadores(para: definicao.tipo).map { (valor: $0, nome: $0.nome) },
                               selecionado: $operador, dica: "Escolher operador")
            }
            if let operador, operador.precisaDeValor {
                CampoDeEntrada(rotulo: operador == .entre ? "De\(unidade)" : "Valor\(unidade)", texto: $valor, teclado: .decimalPad)
                if operador == .entre {
                    CampoDeEntrada(rotulo: "Até\(unidade)", texto: $valorFinal, teclado: .decimalPad)
                }
            }
            if operador == .estaEm, let definicao {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quando for").estiloDeRotulo()
                    ForEach(definicao.opcoes, id: \.self) { opcao in
                        let marcada = opcoes.contains(opcao)
                        Button {
                            Tato.selecao()
                            if marcada { opcoes.remove(opcao) } else { opcoes.insert(opcao) }
                        } label: {
                            HStack {
                                Image(systemName: marcada ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(marcada ? Cor.azulProfundo : Cor.textoFraco)
                                Text(NomesDoAlgoritmo.opcao(opcao).capitalizedPrimeira)
                                    .font(Tipo.corpo)
                                    .foregroundStyle(Cor.texto)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .superficie(.afundado, raio: Raio.controle)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(marcada ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
            CampoDeEscolha(rotulo: "Classificação que a regra produz",
                           opcoes: ClassificacaoDaRegra.todas.map { (valor: $0, nome: $0.nome) },
                           selecionado: $classificacao, dica: "Escolher cor")
            CampoDeTextoLongo(rotulo: "Justificativa clínica", texto: $justificativa,
                              dica: "Por que este corte existe; vai para a explicação do resultado e para a defesa do critério.")

            if let previa {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Como a regra vai ser lida").estiloDeRotulo()
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if let s = classificacao?.situacao { SeloClinico(situacao: s) }
                        Text(previa).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Espaco.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficie(raio: Raio.linha)
            }

            if original != nil {
                BotaoSecundario(titulo: "Remover regra", icone: "trash") {
                    Tato.aviso()
                    concluir(nil)
                }
            }
        }
        .onChange(of: sintoma) { _, novo in
            guard let novo, ArvoreDoAlgoritmo.campo(campo ?? "", de: novo) == nil else { return }
            campo = nil
            operador = nil
        }
        .onChange(of: campo) { _, _ in
            guard let definicao else { operador = nil; return }
            let validos = ArvoreDoAlgoritmo.operadores(para: definicao.tipo)
            if let operador, validos.contains(operador) { return }
            operador = validos.count == 1 ? validos[0] : nil
            opcoes = []
        }
    }

    private var unidade: String { definicao?.unidade.map { " (\($0))" } ?? "" }

    private var previa: String? {
        guard let rascunho = montar(validando: false) else { return nil }
        return rascunho.frase
    }

    private func numero(_ texto: String) -> Double? {
        Double(texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Monta a regra; com `validando`, devolve nil e escreve o motivo.
    private func montar(validando: Bool) -> RascunhoDeRegra? {
        func falha(_ m: String) -> RascunhoDeRegra? {
            if validando { erro = m }
            return nil
        }
        guard let sintoma, let campo, definicao != nil else { return falha("Escolha o campo que a regra observa.") }
        guard let operador else { return falha("Escolha o operador.") }
        var v: Double?
        var v2: Double?
        if operador.precisaDeValor {
            guard let n = numero(valor) else { return falha("O valor precisa ser um número.") }
            v = n
            if operador == .entre {
                guard let n2 = numero(valorFinal) else { return falha("Informe o fim do intervalo.") }
                guard n2 > n else { return falha("O fim do intervalo precisa ser maior que o início.") }
                v2 = n2
            }
        }
        if operador == .estaEm, opcoes.isEmpty { return falha("Marque pelo menos uma opção.") }
        guard let classificacao else { return falha("Escolha a classificação que a regra produz.") }
        let texto = justificativa.trimmingCharacters(in: .whitespacesAndNewlines)
        if validando, texto.count < 3 { return falha("Justificativa é obrigatória: regra sem justificativa não entra.") }

        let ordenadas = operador == .estaEm
            ? (ArvoreDoAlgoritmo.campo(campo, de: sintoma)?.opcoes ?? []).filter(opcoes.contains)
            : nil
        return RascunhoDeRegra(ordem: original?.ordem ?? proximaOrdem, sintoma: sintoma, campo: campo, operador: operador,
                               valor: v, valorSecundario: v2, valoresDeTexto: ordenadas, classificacao: classificacao,
                               justificativa: texto, diaDoCicloMinimo: original?.diaDoCicloMinimo,
                               diaDoCicloMaximo: original?.diaDoCicloMaximo, protocoloId: original?.protocoloId)
    }

    private func guardar() {
        guard let regra = montar(validando: true) else {
            Tato.erro()
            return
        }
        Tato.sucesso()
        concluir(regra)
    }
}

private extension String {
    var capitalizedPrimeira: String { prefix(1).uppercased() + dropFirst() }
}
