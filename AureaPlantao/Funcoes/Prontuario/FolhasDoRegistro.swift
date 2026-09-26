import SwiftUI

// As folhas de registro do plantão. Apresentadas pela `ProntuarioView` de FORA da proteção
// de captura (lá dentro o `Environment` não chega, e a folha precisa do `dismiss`).
//
// Todas seguem o mesmo contrato: validam antes de enviar, mostram o erro da API na própria
// folha (nada some calado) e só fecham depois que o servidor confirmou. Quem abriu recarrega
// o prontuário e mostra o aviso.

/// Qual folha está aberta. `id` distinto por caso para o `.sheet(item:)`.
enum FolhaDoRegistro: Identifiable {
    case barreira
    case pendencia
    case internacao
    case contextoSocial(GravacaoDoRegistro.ContextoSocial, avaliado: Bool)
    case intervencao(sessaoId: String, iniciadaEm: Date)

    var id: String {
        switch self {
        case .barreira: "barreira"
        case .pendencia: "pendencia"
        case .internacao: "internacao"
        case .contextoSocial: "contexto"
        case .intervencao(let id, _): "intervencao-\(id)"
        }
    }
}

/// O estado comum de uma folha que grava: enviando, erro, e o ciclo tentar → fechar.
@MainActor
@Observable
final class EnvioDaFolha {
    private(set) var enviando = false
    var erro: String?

    /// Roda a gravação; em sucesso, haptic de sucesso e `aoConcluir`. Em falha, a folha fica
    /// aberta com o texto preenchido — ninguém redigita uma conduta por causa da rede.
    func enviar(acao: String, _ trabalho: @escaping @MainActor () async throws -> Void, aoConcluir: @escaping @MainActor () -> Void) {
        guard !enviando else { return }
        enviando = true
        erro = nil
        Task {
            do {
                try await trabalho()
                enviando = false
                Tato.sucesso()
                aoConcluir()
            } catch {
                enviando = false
                self.erro = FalhaDeGravacao.mensagem(error, acao: acao)
                Tato.erro()
            }
        }
    }

    func recusar(_ motivo: String) {
        erro = motivo
        Tato.erro()
    }
}

/// Explicação curta abaixo do título: por que este registro importa.
private struct Explicacao: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(Tipo.apoio)
            .foregroundStyle(Cor.textoSuave)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Barreira

struct FolhaDeBarreira: View {
    let pacienteId: String
    let gravacao: GravacaoDoRegistro
    let aoConcluir: @MainActor () -> Void

    @State private var tipo: TipoDeBarreira?
    @State private var descricao = ""
    @State private var envio = EnvioDaFolha()
    @Environment(\.dismiss) private var fechar

    var body: some View {
        FolhaDeFormulario(rotulo: "Registro do plantão", titulo: "Registrar barreira",
                          acao: "Registrar barreira", enviando: envio.enviando, erro: envio.erro,
                          enviar: enviar) {
            Explicacao(texto: "O que impede o paciente de chegar ao tratamento. Alimenta o mapa da tela de navegação.")
            CampoDeEscolha(rotulo: "Tipo", opcoes: TipoDeBarreira.todos.map { ($0, $0.nome) },
                           selecionado: $tipo, dica: "Escolher o tipo")
            CampoDeTextoLongo(rotulo: "Detalhe, se houver", texto: $descricao,
                              dica: "Ex.: depende de carona do vizinho", linhas: 2)
        }
    }

    private func enviar() {
        guard let tipo else { return envio.recusar("Escolha o tipo da barreira.") }
        let detalhe = descricao.aparadoOuNulo
        if let detalhe, detalhe.count > 255 { return envio.recusar("O detalhe passa de 255 caracteres. Encurte.") }
        let corpo = GravacaoDoRegistro.NovaBarreira(tipo: tipo.bruto, descricao: detalhe)
        envio.enviar(acao: "registrar no prontuário",
                     { try await gravacao.registrarBarreira(pacienteId: pacienteId, corpo) },
                     aoConcluir: { aoConcluir(); fechar() })
    }
}

// MARK: - Pendência

struct FolhaDePendencia: View {
    let pacienteId: String
    let gravacao: GravacaoDoRegistro
    let aoConcluir: @MainActor () -> Void

    @State private var tipo: TipoDePendencia?
    @State private var referenteA = Date.now
    @State private var descricao = ""
    @State private var envio = EnvioDaFolha()
    @Environment(\.dismiss) private var fechar

    var body: some View {
        FolhaDeFormulario(rotulo: "Registro do plantão", titulo: "Registrar pendência",
                          acao: "Registrar pendência", enviando: envio.enviando, erro: envio.erro,
                          enviar: enviar) {
            Explicacao(texto: "O que pode suspender a sessão. Aparece na tela de navegação no dia anterior.")
            CampoDeEscolha(rotulo: "Tipo", opcoes: TipoDePendencia.todos.map { ($0, $0.nome) },
                           selecionado: $tipo, dica: "Escolher o tipo")
            CampoDeData(rotulo: "Data do tratamento", data: $referenteA)
            CampoDeTextoLongo(rotulo: "Detalhe, se houver", texto: $descricao,
                              dica: "Ex.: hemograma ainda sem resultado", linhas: 2)
        }
    }

    private func enviar() {
        guard let tipo else { return envio.recusar("Escolha o tipo da pendência.") }
        let detalhe = descricao.aparadoOuNulo
        if let detalhe, detalhe.count > 255 { return envio.recusar("O detalhe passa de 255 caracteres. Encurte.") }
        let corpo = GravacaoDoRegistro.NovaPendencia(tipo: tipo.bruto, referenteA: DataCivil.paraAPI(referenteA),
                                                     descricao: detalhe)
        envio.enviar(acao: "registrar no prontuário",
                     { try await gravacao.registrarPendencia(pacienteId: pacienteId, corpo) },
                     aoConcluir: { aoConcluir(); fechar() })
    }
}

// MARK: - Internação

struct FolhaDeInternacao: View {
    let pacienteId: String
    let gravacao: GravacaoDoRegistro
    let aoConcluir: @MainActor () -> Void

    @State private var motivo = ""
    @State private var local = ""
    @State private var entrada = Date.now
    @State private var jaTeveAlta = false
    @State private var alta = Date.now
    @State private var envio = EnvioDaFolha()
    @Environment(\.dismiss) private var fechar

    var body: some View {
        FolhaDeFormulario(rotulo: "Registro do plantão", titulo: "Registrar internação",
                          acao: "Registrar internação", enviando: envio.enviando, erro: envio.erro,
                          enviar: enviar) {
            Explicacao(texto: "Alta recente sobe o paciente na fila do plantão por sete dias.")
            CampoDeTextoLongo(rotulo: "Motivo da internação", texto: $motivo, dica: "Ex.: neutropenia febril", linhas: 1)
            CampoDeTextoLongo(rotulo: "Local, se souber", texto: $local, dica: "Hospital ou setor", linhas: 1)
            CampoDeData(rotulo: "Entrada", data: $entrada, intervalo: Date.distantPast...Date.now)
            CampoInterruptor(titulo: "Já teve alta",
                             explicacao: "Sem data de alta, o paciente fica como internado agora.",
                             ligado: $jaTeveAlta)
            if jaTeveAlta {
                CampoDeData(rotulo: "Alta", data: $alta, intervalo: entrada...max(entrada, Date.now))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Movimento.interface, value: jaTeveAlta)
        .onChange(of: entrada) { _, nova in if alta < nova { alta = nova } }
    }

    private func enviar() {
        guard let motivo = motivo.aparadoOuNulo, motivo.count >= 2 else {
            return envio.recusar("Escreva o motivo da internação.")
        }
        guard motivo.count <= 255 else { return envio.recusar("O motivo passa de 255 caracteres. Encurte.") }
        let lugar = local.aparadoOuNulo
        if let lugar, lugar.count > 160 { return envio.recusar("O local passa de 160 caracteres. Encurte.") }
        let entradaCivil = DataCivil.paraAPI(entrada)
        let altaCivil = jaTeveAlta ? DataCivil.paraAPI(alta) : nil
        // Comparação de texto `yyyy-MM-dd` é comparação de data.
        if let altaCivil, altaCivil < entradaCivil {
            return envio.recusar("A alta não pode ser anterior à entrada.")
        }
        let corpo = GravacaoDoRegistro.NovaInternacao(motivo: motivo, local: lugar,
                                                      iniciadaEm: entradaCivil, altaEm: altaCivil)
        envio.enviar(acao: "registrar no prontuário",
                     { try await gravacao.registrarInternacao(pacienteId: pacienteId, corpo) },
                     aoConcluir: { aoConcluir(); fechar() })
    }
}

// MARK: - Contexto social

struct FolhaDeContextoSocial: View {
    let pacienteId: String
    let gravacao: GravacaoDoRegistro
    let avaliado: Bool
    let aoConcluir: @MainActor () -> Void

    @State private var contexto: GravacaoDoRegistro.ContextoSocial
    @State private var envio = EnvioDaFolha()
    @Environment(\.dismiss) private var fechar

    init(pacienteId: String, gravacao: GravacaoDoRegistro, atual: GravacaoDoRegistro.ContextoSocial,
         avaliado: Bool, aoConcluir: @escaping @MainActor () -> Void) {
        self.pacienteId = pacienteId
        self.gravacao = gravacao
        self.avaliado = avaliado
        self.aoConcluir = aoConcluir
        _contexto = State(initialValue: atual)
    }

    var body: some View {
        FolhaDeFormulario(rotulo: "Registro do plantão", titulo: "Contexto social",
                          acao: "Gravar avaliação", enviando: envio.enviando, erro: envio.erro,
                          enviar: enviar) {
            Explicacao(texto: "Pesa no risco porque muda quem consegue chegar ao serviço quando piora, não porque muda o tratamento.")
            if !avaliado {
                Text("Nunca avaliado. Enquanto ninguém responder, o risco trata os três itens como ausentes, e não como negativos: não perguntar não é a mesma coisa que a pessoa dizer que não.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Espaco.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficie(.afundado, raio: Raio.controle)
            }
            CampoInterruptor(titulo: "Mora sozinho", ligado: $contexto.moraSozinho)
            CampoInterruptor(titulo: "Tem dificuldade de transporte", ligado: $contexto.dificuldadeDeTransporte)
            CampoInterruptor(titulo: "Tem cuidador", ligado: $contexto.temCuidador)
            Text("Gravar marca a avaliação com a data de hoje, mesmo que nada mude.")
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoFraco)
        }
    }

    private func enviar() {
        let corpo = contexto
        envio.enviar(acao: "registrar no prontuário",
                     { try await gravacao.gravarContextoSocial(pacienteId: pacienteId, corpo) },
                     aoConcluir: { aoConcluir(); fechar() })
    }
}

// MARK: - Intervenção (E3 do web)

struct FolhaDeIntervencao: View {
    let sessaoId: String
    let iniciadaEm: Date
    let gravacao: GravacaoDoRegistro
    let aoConcluir: @MainActor () -> Void

    @State private var conduta = ""
    @State private var desfecho: DesfechoDaIntervencao?
    @State private var contato = Date.now
    @State private var envio = EnvioDaFolha()
    @Environment(\.dismiss) private var fechar

    var body: some View {
        FolhaDeFormulario(rotulo: "Check-in de \(Formato.quando(iniciadaEm))", titulo: "Registrar intervenção",
                          acao: "Salvar conduta", enviando: envio.enviando, erro: envio.erro,
                          enviar: enviar) {
            Explicacao(texto: "A conduta fica anexada a este check-in, junto da classificação que a motivou.")
            CampoDeTextoLongo(rotulo: "Conduta", texto: $conduta, dica: "O que foi orientado ou feito")
            CampoDeEscolha(rotulo: "Situação do sintoma",
                           opcoes: DesfechoDaIntervencao.registraveis.map { ($0, $0.nome) },
                           selecionado: $desfecho, dica: "Escolher a situação")
            CampoDeData(rotulo: "Contato realizado em", data: $contato, comHora: true,
                        intervalo: min(iniciadaEm, Date.now)...Date.now)
        }
    }

    private func enviar() {
        let texto = conduta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texto.count >= 3 else { return envio.recusar("Escreva a conduta (pelo menos 3 caracteres).") }
        guard texto.count <= 4000 else { return envio.recusar("A conduta passa de 4.000 caracteres. Encurte.") }
        guard let desfecho else { return envio.recusar("Escolha a situação do sintoma.") }
        let corpo = GravacaoDoRegistro.NovaIntervencao(conduta: texto, situacao: desfecho.bruto,
                                                       contatoRealizadoEm: GravacaoDoRegistro.instante(min(contato, .now)))
        envio.enviar(acao: "registrar intervenção",
                     { try await gravacao.registrarIntervencao(sessaoId: sessaoId, corpo) },
                     aoConcluir: { aoConcluir(); fechar() })
    }
}
