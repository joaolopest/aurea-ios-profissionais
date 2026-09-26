import SwiftUI

/// Tipos sanguíneos do seletor. A API aceita texto livre (até 5 caracteres); o seletor
/// evita "0+" com zero no lugar do O, que o texto livre deixava passar.
enum TiposSanguineosDoCadastro {
    static let todos = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    static func opcoes(incluindo atual: String?) -> [(valor: String, nome: String)] {
        var lista = todos
        if let atual, !lista.contains(atual) { lista.append(atual) }
        return lista.map { ($0, $0) }
    }
}

/// Texto de apoio abaixo de um campo — explica o porquê, ou aponta o erro daquele campo.
struct ApoioDeCampoDoCadastro: View {
    let texto: String
    var ehErro = false

    var body: some View {
        Label {
            Text(texto).fixedSize(horizontal: false, vertical: true)
        } icon: {
            if ehErro { Image(systemName: "exclamationmark.circle") }
        }
        .labelStyle(ApoioLabelStyle(comIcone: ehErro))
        .font(Tipo.apoio)
        .foregroundStyle(ehErro ? Cor.texto : Cor.textoSuave)
        .padding(.horizontal, 4)
    }

    private struct ApoioLabelStyle: LabelStyle {
        let comIcone: Bool
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if comIcone { configuration.icon }
                configuration.title
            }
        }
    }
}

/// Data de nascimento que começa VAZIA. Um `DatePicker` sempre tem valor, e um padrão
/// qualquer (hoje, 1970) vira data de nascimento de alguém no primeiro "Salvar" apressado.
struct CampoDeDataOpcionalDoCadastro: View {
    let rotulo: String
    @Binding var data: Date?
    var dica = "Escolher data"
    var ate: Date = .now

    var body: some View {
        if let valor = data {
            CampoDeData(rotulo: rotulo,
                        data: Binding(get: { valor }, set: { data = $0 }),
                        intervalo: Date(timeIntervalSince1970: -2_208_988_800)...ate)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(rotulo).estiloDeRotulo().accessibilityHidden(true)
                Button {
                    Tato.selecao()
                    data = Calendar.current.date(byAdding: .year, value: -50, to: .now)
                } label: {
                    HStack {
                        Text(dica).font(Tipo.corpo).foregroundStyle(Cor.textoFraco)
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(Cor.textoFraco)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .superficie(.afundado, raio: Raio.controle)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rotulo): não informada")
                .accessibilityHint("Abre o seletor de data")
            }
        }
    }
}

// MARK: - Novo paciente

/// Cria o login (CPF + senha provisória) e a ficha, juntos, numa transação da API.
///
/// Fica de fora a história de vida: o `POST` aceita tabagismo, atividade e álcool com 201
/// e NÃO grava (conferido lendo de volta). Ela entra pela edição, que grava. Contatos
/// também não cabem aqui — a API não os recebe na criação; a tela abre a ficha logo depois
/// para isso.
struct FormularioDeNovoPaciente: View {
    let concluir: (RotaDaFichaDoCadastro) -> Void

    @State private var nome = ""
    @State private var cpf = ""
    @State private var nascimento: Date?
    @State private var sexo: SexoDoCadastro? = .naoInformado
    @State private var diagnostico = ""
    @State private var convenio = ""
    @State private var tipoSanguineo: String?
    @State private var habito = ""
    @State private var senha = ""
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        FolhaDeFormulario(
            rotulo: "Cadastro · dado sintético",
            titulo: "Novo paciente",
            acao: "Cadastrar paciente",
            icone: "person.badge.plus",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            CampoDeEntrada(rotulo: "Nome completo", texto: $nome, conteudo: .name)

            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "CPF", texto: $cpf, teclado: .numberPad)
                    .onChange(of: cpf) { _, novo in
                        let mascarado = CPFDoCadastro.mascaraDeDigitacao(novo)
                        if mascarado != novo { cpf = mascarado }
                    }
                if CPFDoCadastro.normalizar(cpf).count == 11, !CPFDoCadastro.ehValido(cpf) {
                    ApoioDeCampoDoCadastro(texto: "CPF inválido; confira os dígitos.", ehErro: true)
                } else {
                    ApoioDeCampoDoCadastro(texto: "É o login do paciente no app e não muda depois de cadastrado.")
                }
            }

            CampoDeDataOpcionalDoCadastro(rotulo: "Data de nascimento", data: $nascimento)
            CampoDeEscolha(rotulo: "Sexo", opcoes: SexoDoCadastro.opcoes, selecionado: $sexo)
            CampoDeEntrada(rotulo: "Diagnóstico", texto: $diagnostico)
            CampoDeEntrada(rotulo: "Convênio (opcional)", texto: $convenio)
            CampoDeEscolha(rotulo: "Tipo sanguíneo (opcional)", opcoes: TiposSanguineosDoCadastro.opcoes(incluindo: nil),
                           selecionado: $tipoSanguineo, dica: "Não informado")

            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "Hábito intestinal basal (opcional)", texto: $habito, teclado: .numberPad)
                ApoioDeCampoDoCadastro(texto: "Evacuações por dia, antes do tratamento. É a referência para avaliar diarreia por comparação depois.")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: Espaco.s) {
                    CampoDeEntrada(rotulo: "Senha provisória", texto: $senha, conteudo: .newPassword)
                    BotaoDeAcaoEmLinha(titulo: "Gerar", icone: "wand.and.stars") { senha = Self.senhaAleatoria() }
                        .padding(.bottom, 6)
                }
                ApoioDeCampoDoCadastro(texto: "Mínimo de 10 caracteres. Entregue ao paciente: é com o CPF e esta senha que ele entra no app.")
            }
        }
    }

    private func validar() -> String? {
        let n = TextoDoCadastro.aparado(nome)
        if n.count < 2 { return "Informe o nome completo." }
        if n.count > 180 { return "O nome passa de 180 caracteres." }
        if CPFDoCadastro.normalizar(cpf).isEmpty { return "Informe o CPF." }
        if !CPFDoCadastro.ehValido(cpf) { return "CPF inválido; confira os dígitos." }
        guard let nascimento else { return "Informe a data de nascimento." }
        if nascimento > .now { return "A data de nascimento não pode estar no futuro." }
        let d = TextoDoCadastro.aparado(diagnostico)
        if d.count < 2 { return "Informe o diagnóstico." }
        if d.count > 255 { return "O diagnóstico passa de 255 caracteres." }
        if TextoDoCadastro.aparado(convenio).count > 120 { return "O convênio passa de 120 caracteres." }
        if let erro = Self.validarHabito(habito) { return erro }
        if senha.count < 10 { return "A senha provisória precisa de pelo menos 10 caracteres." }
        if senha.count > 200 { return "A senha provisória passa de 200 caracteres." }
        return nil
    }

    static func validarHabito(_ texto: String) -> String? {
        let t = TextoDoCadastro.aparado(texto)
        guard !t.isEmpty else { return nil }
        guard let n = Int(t), (0...20).contains(n) else {
            return "Hábito intestinal basal: informe um número inteiro de 0 a 20."
        }
        return nil
    }

    private func enviar() async {
        if let problema = validar() {
            Tato.erro()
            erro = problema
            return
        }
        guard let nascimento else { return }
        enviando = true
        erro = nil
        defer { enviando = false }
        let corpo = NovoPacienteDoCadastro(
            nome: TextoDoCadastro.aparado(nome),
            cpf: CPFDoCadastro.normalizar(cpf),
            dataNascimento: DataCivil.paraAPI(nascimento),
            sexo: sexo ?? .naoInformado,
            diagnostico: TextoDoCadastro.aparado(diagnostico),
            convenio: TextoDoCadastro.opcional(convenio),
            tipoSanguineo: tipoSanguineo,
            habitoIntestinalBasal: Int(TextoDoCadastro.aparado(habito)),
            senhaProvisoria: senha
        )
        do {
            let criado: RespostaDeEscritaDoCadastro = try await ClienteAPI.compartilhado.enviar("/admin/pacientes", corpo: corpo)
            concluir(RotaDaFichaDoCadastro(id: criado.id, nome: corpo.nome))
        } catch ErroDaAPI.conflito {
            // O 409 daqui é sempre CPF repetido; a mensagem da API não chega (chave `erro`).
            Tato.erro()
            erro = "Já existe um cadastro com este CPF."
        } catch {
            Tato.erro()
            erro = ErroDoCadastro.mensagem(error)
        }
    }

    /// 12 caracteres sem os que se confundem no papel (0/O, 1/l/I).
    private static func senhaAleatoria() -> String {
        let alfabeto = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789")
        var gerador = SystemRandomNumberGenerator()
        return String((0..<12).map { _ in alfabeto.randomElement(using: &gerador)! })
    }
}

// MARK: - Edição

/// Edita o que a API deixa editar. CPF e senha ficam de fora por decisão da API: CPF é
/// identidade de login e trocá-lo por aqui seria trocar a identidade sem rastro.
/// Só vai no `PATCH` o que mudou.
struct FormularioDeEdicaoDoPaciente: View {
    let ficha: FichaDoCadastro
    let store: FichaDoPacienteStore
    let concluir: () -> Void

    @State private var nome: String
    @State private var nascimento: Date?
    @State private var sexo: SexoDoCadastro?
    @State private var diagnostico: String
    @State private var convenio: String
    @State private var tipoSanguineo: String?
    @State private var habito: String
    @State private var tabagismo: TabagismoDoCadastro?
    @State private var parouDeFumar: Date?
    @State private var atividade: AtividadeFisicaDoCadastro?
    @State private var descricaoDaAtividade: String
    @State private var alcool: ConsumoDeAlcoolDoCadastro?
    @State private var enviando = false
    @State private var erro: String?

    init(ficha: FichaDoCadastro, store: FichaDoPacienteStore, concluir: @escaping () -> Void) {
        self.ficha = ficha
        self.store = store
        self.concluir = concluir
        _nome = State(initialValue: ficha.nome)
        _nascimento = State(initialValue: DataCivil.paraSeletor(ficha.dataNascimento))
        _sexo = State(initialValue: ficha.sexo)
        _diagnostico = State(initialValue: ficha.diagnostico)
        _convenio = State(initialValue: ficha.convenio ?? "")
        _tipoSanguineo = State(initialValue: ficha.tipoSanguineo)
        _habito = State(initialValue: ficha.habitoIntestinalBasal.map(String.init) ?? "")
        _tabagismo = State(initialValue: ficha.tabagismo)
        _parouDeFumar = State(initialValue: ficha.parouDeFumarEm.map(DataCivil.paraSeletor))
        _atividade = State(initialValue: ficha.atividadeFisica)
        _descricaoDaAtividade = State(initialValue: ficha.descricaoDaAtividade ?? "")
        _alcool = State(initialValue: ficha.consumoDeAlcool)
    }

    var body: some View {
        FolhaDeFormulario(
            rotulo: ficha.nome,
            titulo: "Editar cadastro",
            acao: "Salvar alterações",
            enviando: enviando,
            erro: erro,
            enviar: { Task { await enviar() } }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CPF").estiloDeRotulo()
                Text(CPFDoCadastro.mascarado(ficha.cpf))
                    .font(Tipo.colunaForte).foregroundStyle(Cor.textoSuave)
                    .privacySensitive()
                ApoioDeCampoDoCadastro(texto: "O CPF é o login do paciente e não se altera por aqui.")
            }
            .accessibilityElement(children: .combine)

            CampoDeEntrada(rotulo: "Nome completo", texto: $nome, conteudo: .name)
            CampoDeDataOpcionalDoCadastro(rotulo: "Data de nascimento", data: $nascimento)
            CampoDeEscolha(rotulo: "Sexo", opcoes: SexoDoCadastro.opcoes, selecionado: $sexo)
            CampoDeEntrada(rotulo: "Diagnóstico", texto: $diagnostico)
            CampoDeEntrada(rotulo: "Convênio (opcional)", texto: $convenio)
            CampoDeEscolha(rotulo: "Tipo sanguíneo (opcional)",
                           opcoes: TiposSanguineosDoCadastro.opcoes(incluindo: ficha.tipoSanguineo),
                           selecionado: $tipoSanguineo, dica: "Não informado")
            if tipoSanguineo != nil {
                Button("Limpar tipo sanguíneo") { tipoSanguineo = nil }
                    .font(Tipo.apoioForte).foregroundStyle(Cor.azulProfundo)
                    .frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                CampoDeEntrada(rotulo: "Hábito intestinal basal (opcional)", texto: $habito, teclado: .numberPad)
                ApoioDeCampoDoCadastro(texto: "Evacuações por dia, antes do tratamento. Em branco, a diarreia fica sem referência para comparar.")
            }

            Text("História de vida").font(Tipo.tituloDeBloco).foregroundStyle(Cor.texto)
                .padding(.top, Espaco.s)
            ApoioDeCampoDoCadastro(texto: "“Não informado” é a resposta honesta quando ninguém perguntou. Não escolha “nunca fumou” só para preencher.")

            CampoDeEscolha(rotulo: "Tabagismo", opcoes: TabagismoDoCadastro.opcoes, selecionado: $tabagismo)
            if tabagismo == .exFumante {
                CampoDeDataOpcionalDoCadastro(rotulo: "Parou de fumar em (opcional)", data: $parouDeFumar, dica: "Não informado")
                if parouDeFumar != nil {
                    Button("Limpar data de parada") { parouDeFumar = nil }
                        .font(Tipo.apoioForte).foregroundStyle(Cor.azulProfundo)
                        .frame(minHeight: 44)
                }
            }
            CampoDeEscolha(rotulo: "Atividade física", opcoes: AtividadeFisicaDoCadastro.opcoes, selecionado: $atividade)
            CampoDeEntrada(rotulo: "Qual atividade (opcional)", texto: $descricaoDaAtividade)
            CampoDeEscolha(rotulo: "Álcool", opcoes: ConsumoDeAlcoolDoCadastro.opcoes, selecionado: $alcool)
        }
    }

    private func montarAlteracao() -> Result<AlteracaoDoPacienteDoCadastro, MotivoDoCadastro> {
        var a = AlteracaoDoPacienteDoCadastro()

        let n = TextoDoCadastro.aparado(nome)
        if n.count < 2 { return .failure(.init("Informe o nome completo.")) }
        if n.count > 180 { return .failure(.init("O nome passa de 180 caracteres.")) }
        if n != ficha.nome { a.nome = .some(n) }

        guard let nascimento else { return .failure(.init("Informe a data de nascimento.")) }
        if nascimento > .now { return .failure(.init("A data de nascimento não pode estar no futuro.")) }
        let nascimentoAPI = DataCivil.paraAPI(nascimento)
        if nascimentoAPI != DataCivil.paraAPI(DataCivil.paraSeletor(ficha.dataNascimento)) {
            a.dataNascimento = .some(nascimentoAPI)
        }

        if let sexo, sexo != ficha.sexo { a.sexo = .some(sexo) }

        let d = TextoDoCadastro.aparado(diagnostico)
        if d.count < 2 { return .failure(.init("Informe o diagnóstico.")) }
        if d.count > 255 { return .failure(.init("O diagnóstico passa de 255 caracteres.")) }
        if d != ficha.diagnostico { a.diagnostico = .some(d) }

        let c = TextoDoCadastro.opcional(convenio)
        if (c?.count ?? 0) > 120 { return .failure(.init("O convênio passa de 120 caracteres.")) }
        if c != ficha.convenio { a.convenio = .some(c) }

        if tipoSanguineo != ficha.tipoSanguineo { a.tipoSanguineo = .some(tipoSanguineo) }

        if let problema = FormularioDeNovoPaciente.validarHabito(habito) { return .failure(.init(problema)) }
        let h = Int(TextoDoCadastro.aparado(habito))
        if h != ficha.habitoIntestinalBasal { a.habitoIntestinalBasal = .some(h) }

        if let tabagismo, tabagismo != ficha.tabagismo { a.tabagismo = .some(tabagismo) }
        // Data de parada só existe para ex-fumante. Saindo de ex-fumante, a data vai a
        // `null` junto — senão o banco guardaria "nunca fumou, parou em 2010".
        let parada = tabagismo == .exFumante ? parouDeFumar.map(DataCivil.paraAPI) : nil
        let paradaAtual = ficha.parouDeFumarEm.map { DataCivil.paraAPI(DataCivil.paraSeletor($0)) }
        if parada != paradaAtual {
            a.parouDeFumarEm = .some(parada)
            // A API só aceita data de parada junto de um tabagismo explícito de ex-fumante.
            if parada != nil, a.tabagismo == nil { a.tabagismo = .some(.exFumante) }
        }
        if let p = parouDeFumar, tabagismo == .exFumante, p > .now {
            return .failure(.init("A data de parada do fumo não pode estar no futuro."))
        }

        if let atividade, atividade != ficha.atividadeFisica { a.atividadeFisica = .some(atividade) }
        let desc = TextoDoCadastro.opcional(descricaoDaAtividade)
        if (desc?.count ?? 0) > 200 { return .failure(.init("A descrição da atividade passa de 200 caracteres.")) }
        if desc != ficha.descricaoDaAtividade { a.descricaoDaAtividade = .some(desc) }

        if let alcool, alcool != ficha.consumoDeAlcool { a.consumoDeAlcool = .some(alcool) }
        return .success(a)
    }

    private func enviar() async {
        let alteracao: AlteracaoDoPacienteDoCadastro
        switch montarAlteracao() {
        case .failure(let motivo):
            Tato.erro()
            erro = motivo.texto
            return
        case .success(let a):
            alteracao = a
        }
        // Nada mudou: fechar é a resposta certa; a API recusaria o corpo vazio.
        guard !alteracao.vazia else {
            concluir()
            return
        }
        enviando = true
        erro = nil
        defer { enviando = false }
        do {
            try await store.salvar(alteracao)
            concluir()
        } catch {
            Tato.erro()
            erro = ErroDoCadastro.mensagem(error)
        }
    }
}

/// Motivo de recusa na validação local. Tipo próprio só para caber no `Result`.
struct MotivoDoCadastro: Error {
    let texto: String
    init(_ texto: String) { self.texto = texto }
}
