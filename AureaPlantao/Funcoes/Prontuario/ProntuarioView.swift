import SwiftUI

@MainActor
@Observable
final class ProntuarioStore {
    private(set) var carga: Carga<Prontuario> = .carregando
    let pacienteId: String
    private let api: ClienteAPI

    init(pacienteId: String, api: ClienteAPI = .compartilhado) {
        self.pacienteId = pacienteId
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            carga = .pronto(try await api.obter("/painel/pacientes/\(pacienteId)/historico"))
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }
}

/// O prontuário, na ordem em que a enfermeira ao telefone precisa:
/// quem é → por que está aqui (a regra, por extenso) → como falar com ele → o que ele toma
/// e ao que é alérgico → o contexto de casa → o histórico.
///
/// Todo o conteúdo fica protegido de captura de tela: sai em branco num screenshot.
struct ProntuarioView: View {
    let nome: String
    let situacao: SituacaoClinica?
    @State private var store: ProntuarioStore

    init(pacienteId: String, nome: String, situacao: SituacaoClinica?) {
        self.nome = nome
        self.situacao = situacao
        _store = State(initialValue: ProntuarioStore(pacienteId: pacienteId))
    }

    var body: some View {
        Group {
            if Self.protecaoLigada {
                ProtegidoDeCaptura { conteudo }
            } else {
                conteudo
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .containerBackground(.clear, for: .navigation)
        .task { await store.carregar() }
        .encerraSessaoNo401(store.carga.erro)
    }

    private var conteudo: some View {
        ConteudoDoProntuario(nome: nome, situacao: situacao, carga: store.carga) {
            Task { await store.carregar() }
        }
    }

    /// Só em DEBUG dá para desligar, com o argumento `-revisaoDeDesign` — senão nenhuma
    /// captura de revisão de layout (Maestro, screenshot) consegue ver o prontuário.
    private static var protecaoLigada: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-revisaoDeDesign")
        #else
        true
        #endif
    }
}

/// Separado da view de cima porque vive dentro de um `UIHostingController` (a proteção de
/// captura): ali o `Environment` não chega, então tudo entra por parâmetro.
private struct ConteudoDoProntuario: View {
    let nome: String
    let situacao: SituacaoClinica?
    let carga: Carga<Prontuario>
    let recarregar: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espaco.xl) {
                cabecalho

                if let erro = carga.erro, carga.valor == nil {
                    CartaoDeErro(erro: erro, tentarDeNovo: recarregar)
                }

                if let p = carga.valor {
                    UltimoCheckin(prontuario: p)
                    Contatos(contatos: p.contatos)
                    SaudeDoPaciente(prontuario: p)
                    ContextoDeCasa(prontuario: p)
                    HistoricoDeCheckins(prontuario: p)
                    Agenda(eventos: p.eventosDeAgenda)
                } else if carga.erro == nil {
                    VStack(alignment: .leading, spacing: Espaco.m) {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                Esqueleto(largura: 120, altura: 10)
                                Esqueleto(altura: 12)
                                Esqueleto(largura: 220, altura: 12)
                            }
                            .padding(Espaco.l)
                            .superficie()
                        }
                    }
                }
            }
            .padding(.horizontal, Espaco.margem)
            .padding(.top, Espaco.s)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    /// A ficha do BT: avatar grande, nome, e as etiquetas logo abaixo.
    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Iniciais(nome: nome, tamanho: 60)
                VStack(alignment: .leading, spacing: 6) {
                    Text(nome)
                        .font(Tipo.titulo)
                        .foregroundStyle(Cor.texto)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let situacao { SeloClinico(situacao: situacao) }
                }
            }
            if let p = carga.valor {
                Text(p.diagnostico)
                    .font(Tipo.corpo)
                    .foregroundStyle(Cor.textoSuave)
                HStack(spacing: 10) {
                    Metrica(valor: "\(Formato.idade(nascimento: p.dataNascimento))", rotulo: "anos")
                    if let c = p.numeroDoCiclo { Metrica(valor: "C\(c)", rotulo: "ciclo") }
                    if let d = p.diaDoCiclo { Metrica(valor: "D\(d)", rotulo: "hoje") }
                    if p.ecog != "NAO_AVALIADO" { Metrica(valor: p.ecog.replacingOccurrences(of: "ECOG_", with: ""), rotulo: "ECOG") }
                }
                .padding(.top, 4)
                if let protocolo = p.protocolo {
                    Text(protocolo)
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                }
            }
        }
    }
}

private struct Metrica: View {
    let valor: String
    let rotulo: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor).font(Tipo.colunaForte).foregroundStyle(Cor.texto)
            Text(rotulo).font(Tipo.rotulo).tracking(0.4).foregroundStyle(Cor.textoFraco)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .superficie(.plano, raio: 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Bloco

private struct Bloco<Conteudo: View>: View {
    let titulo: String
    var contagem: Int?
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CabecalhoDeSecao(titulo: titulo, contagem: contagem)
            VStack(alignment: .leading, spacing: 0) { conteudo }
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficie()
        }
    }
}

private struct LinhaDeBloco<Conteudo: View>: View {
    var ultima = false
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            conteudo
                .padding(.horizontal, Espaco.l)
                .padding(.vertical, 14)
            if !ultima {
                Rectangle().fill(Cor.filete).frame(height: 0.75).padding(.leading, Espaco.l)
            }
        }
    }
}

// MARK: - Último check-in (a regra, por extenso)

/// Lei 2 do produto: toda classificação vem com a regra que a produziu, por extenso.
/// Sem isso o painel vira caixa-preta. Aqui ela não se esconde atrás de toque.
private struct UltimoCheckin: View {
    let prontuario: Prontuario

    var body: some View {
        let ultimo = prontuario.checkins.first

        Bloco(titulo: "Último check-in") {
            if let ultimo {
                let classificacao = ultimo.classificacao
                LinhaDeBloco(ultima: regras(classificacao).isEmpty && classificacao?.motivoDeNaoClassificar == nil) {
                    HStack {
                        if let r = classificacao?.resultado {
                            SeloClinico(situacao: r.situacao)
                        } else {
                            SeloClinico(situacao: .silencio)
                        }
                        Spacer()
                        Text(Formato.quando(ultimo.sessao.iniciadaEm))
                            .font(Tipo.apoio)
                            .monospacedDigit()
                            .foregroundStyle(Cor.textoFraco)
                    }
                }

                if let motivo = classificacao?.motivoDeNaoClassificar {
                    // Lei 3: silêncio não é verde. Questionário não terminado não vira resultado.
                    LinhaDeBloco(ultima: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Não classificado").font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                            Text(motivo).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        }
                    }
                }

                let lista = regras(classificacao)
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, regra in
                    LinhaDeBloco(ultima: i == lista.count - 1) {
                        LinhaDeRegra(regra: regra)
                    }
                }

                if let conjunto = classificacao?.conjunto, !conjunto.validadoClinicamente {
                    AvisoNaoValidado(versao: conjunto.versao)
                        .padding(.horizontal, Espaco.l)
                        .padding(.bottom, 14)
                }
            } else {
                LinhaDeBloco(ultima: true) {
                    Text("Nunca respondeu o questionário.")
                        .font(Tipo.apoio)
                        .foregroundStyle(Cor.textoSuave)
                }
            }
        }
    }

    private func regras(_ c: Prontuario.ClassificacaoDaSessao?) -> [RegraDisparada] {
        (c?.explicacao.porSintoma ?? []).flatMap(\.regrasDisparadas)
    }
}

private struct LinhaDeRegra: View {
    let regra: RegraDisparada

    var body: some View {
        let tons = Faixa.tons(regra.classificacao.situacao)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(tons.tinta).frame(width: 8, height: 8)
                Text(regra.sintoma.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                Spacer()
                Text(Formato.observado(regra))
                    .font(Tipo.apoioForte)
                    .monospacedDigit()
                    .foregroundStyle(tons.tinta)
            }
            Text(regra.justificativa)
                .font(Tipo.apoio)
                .foregroundStyle(Cor.textoSuave)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(regra.classificacao.situacao.nome): \(regra.sintoma.nome), \(Formato.observado(regra)). \(regra.justificativa)")
    }
}

// MARK: - Contatos

private struct Contatos: View {
    let contatos: [Prontuario.Contato]

    var body: some View {
        Bloco(titulo: "Ligar") {
            if contatos.isEmpty {
                LinhaDeBloco(ultima: true) {
                    Text("Nenhum telefone cadastrado.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
            }
            ForEach(Array(contatos.enumerated()), id: \.offset) { i, contato in
                LinhaDeBloco(ultima: i == contatos.count - 1) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contato.tipo == "CONTATO_DE_EMERGENCIA" ? "Emergência · \(contato.relacao ?? "contato")" : "Paciente")
                                .estiloDeRotulo()
                            Text(contato.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                            Text(Formato.telefone(contato.telefone))
                                .font(Tipo.apoio)
                                .monospacedDigit()
                                .foregroundStyle(Cor.textoSuave)
                        }
                        Spacer()
                        if let url = URL(string: "tel:\(contato.telefone.filter(\.isNumber))") {
                            Link(destination: url) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Cor.textoInvertido)
                                    .frame(width: 44, height: 44)
                                    .background(Cor.azulProfundo, in: Circle())
                            }
                            .accessibilityLabel("Ligar para \(contato.nome)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Saúde

private struct SaudeDoPaciente: View {
    let prontuario: Prontuario

    var body: some View {
        let emVigor = prontuario.prescricoes.filter { $0.encerradaEm == nil }

        Bloco(titulo: "Alergias e medicação") {
            LinhaDeBloco {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alergias").estiloDeRotulo()
                    if prontuario.alergias.isEmpty {
                        Text("Nenhuma registrada").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    } else {
                        Text(prontuario.alergias.map(\.descricao).joined(separator: ", "))
                            .font(Tipo.corpoForte)
                            .foregroundStyle(Cor.texto)
                    }
                }
            }
            if !prontuario.comorbidades.isEmpty {
                LinhaDeBloco {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comorbidades").estiloDeRotulo()
                        Text(prontuario.comorbidades.map(\.descricao).joined(separator: ", "))
                            .font(Tipo.corpo).foregroundStyle(Cor.texto)
                    }
                }
            }
            if emVigor.isEmpty {
                LinhaDeBloco(ultima: true) {
                    Text("Nenhuma prescrição em vigor.").font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                }
            }
            ForEach(Array(emVigor.enumerated()), id: \.element.id) { i, p in
                LinhaDeBloco(ultima: i == emVigor.count - 1) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.medicamento.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                        Text(p.posologia).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                        if let quem = p.prescritaPor {
                            Text("Prescrito por \(quem.nome)").font(Tipo.apoio).foregroundStyle(Cor.textoFraco)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Contexto de casa

private struct ContextoDeCasa: View {
    let prontuario: Prontuario

    var body: some View {
        let internacaoAberta = prontuario.internacoes.first { $0.altaEm == nil }

        Bloco(titulo: "Em casa") {
            if let i = internacaoAberta {
                LinhaDeBloco {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Internado desde \(Formato.dia(i.iniciadaEm))").font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                        Text([i.motivo, i.local].compactMap { $0 }.joined(separator: " · "))
                            .font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                    }
                }
            }
            LinhaDeBloco(ultima: prontuario.barreiras.isEmpty) {
                VStack(alignment: .leading, spacing: 10) {
                    Fato(texto: prontuario.moraSozinho ? "Mora sozinho" : "Não mora sozinho", alerta: prontuario.moraSozinho)
                    Fato(texto: prontuario.temCuidador ? "Tem cuidador" : "Sem cuidador", alerta: !prontuario.temCuidador)
                    Fato(texto: prontuario.dificuldadeDeTransporte ? "Dificuldade de transporte" : "Transporte sem dificuldade",
                         alerta: prontuario.dificuldadeDeTransporte)
                }
            }
            ForEach(Array(prontuario.barreiras.enumerated()), id: \.element.id) { i, b in
                LinhaDeBloco(ultima: i == prontuario.barreiras.count - 1) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Barreira · \(Formato.dia(b.criadaEm))").estiloDeRotulo()
                        Text(nomeDaBarreira(b.tipo)).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                        if let d = b.descricao { Text(d).font(Tipo.apoio).foregroundStyle(Cor.textoSuave) }
                    }
                }
            }
        }
    }

    private func nomeDaBarreira(_ tipo: String) -> String {
        switch tipo {
        case "TRANSPORTE": "Transporte"
        case "AUTORIZACAO": "Autorização do convênio"
        case "FINANCEIRA": "Financeira"
        case "ANSIEDADE": "Ansiedade"
        case "REDE_DE_APOIO": "Rede de apoio"
        case "DISTANCIA": "Distância"
        case "TRABALHO": "Trabalho"
        default: "Outra"
        }
    }
}

/// Um fato de contexto. O ponto escuro marca o que pesa contra — sem cor clínica, porque
/// contexto social não é classificação.
private struct Fato: View {
    let texto: String
    let alerta: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(alerta ? Cor.azulProfundo : Cor.fundoFundo)
                .frame(width: 7, height: 7)
            Text(texto)
                .font(alerta ? Tipo.apoioForte : Tipo.apoio)
                .foregroundStyle(alerta ? Cor.texto : Cor.textoSuave)
        }
    }
}

// MARK: - Histórico

private struct HistoricoDeCheckins: View {
    let prontuario: Prontuario

    var body: some View {
        let lista = Array(prontuario.checkins.dropFirst().prefix(12))
        if !lista.isEmpty {
            Bloco(titulo: "Check-ins anteriores", contagem: prontuario.sessoesDeTriagem.count - 1) {
                ForEach(Array(lista.enumerated()), id: \.element.sessao.id) { i, item in
                    LinhaDeBloco(ultima: i == lista.count - 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(Formato.diaCurto(item.sessao.iniciadaEm))
                                .font(Tipo.coluna)
                                .foregroundStyle(Cor.textoSuave)
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                if let r = item.classificacao?.resultado {
                                    Text(r.situacao.nome).font(Tipo.apoioForte).foregroundStyle(Faixa.tons(r.situacao).tinta)
                                    let sintomas = (item.classificacao?.explicacao.porSintoma ?? [])
                                        .filter { $0.classificacao != .verde }.map(\.sintoma.nome)
                                    if !sintomas.isEmpty {
                                        Text(sintomas.joined(separator: ", ")).font(Tipo.apoio).foregroundStyle(Cor.textoSuave)
                                    }
                                } else {
                                    Text(item.sessao.estado == "ABANDONADA" ? "Não terminou" : "Não classificado")
                                        .font(Tipo.apoioForte).foregroundStyle(Cor.textoSuave)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Agenda

private struct Agenda: View {
    let eventos: [Prontuario.Evento]

    var body: some View {
        let proximos = eventos.filter { $0.aconteceEm >= .now }.sorted { $0.aconteceEm < $1.aconteceEm }
        let ultimo = eventos.filter { $0.aconteceEm < .now }.max { $0.aconteceEm < $1.aconteceEm }
        let lista = proximos.prefix(3) + (ultimo.map { [$0] } ?? [])

        if !lista.isEmpty {
            Bloco(titulo: "Agenda") {
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, e in
                    LinhaDeBloco(ultima: i == lista.count - 1) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.aconteceEm < .now ? "Última visita" : "Próxima").estiloDeRotulo()
                                Text(e.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto)
                                if let local = e.local { Text(local).font(Tipo.apoio).foregroundStyle(Cor.textoSuave) }
                            }
                            Spacer()
                            Text(Formato.dia(e.aconteceEm) + " · " + Formato.hora(e.aconteceEm))
                                .font(Tipo.apoio)
                                .monospacedDigit()
                                .foregroundStyle(Cor.textoSuave)
                        }
                    }
                }
            }
        }
    }
}
