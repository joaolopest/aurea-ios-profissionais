import SwiftUI

@MainActor
@Observable
final class PacientesStore {
    private(set) var carga: Carga<[PacienteDaLista]> = .carregando
    var busca = ""
    private let api: ClienteAPI

    init(api: ClienteAPI = .compartilhado) {
        self.api = api
    }

    func carregar() async {
        let anterior = carga.valor
        do {
            let pagina: PaginaDePacientes = try await api.obter("/painel/pacientes")
            carga = .pronto(pagina.itens)
        } catch {
            carga = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    /// Busca por nome, diagnóstico ou responsável — os mesmos três campos do web.
    /// Sem acento e sem caixa: "joao" acha "João".
    var filtrados: [PacienteDaLista] {
        let todos = carga.valor ?? []
        let termo = busca.trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty else { return todos }
        return todos.filter { p in
            [p.nome, p.diagnostico, p.responsavel?.nome ?? ""].contains {
                $0.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}

struct PacientesView: View {
    @State private var store = PacientesStore()
    @Namespace private var transicao

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Espaco.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Em acompanhamento").estiloDeRotulo()
                        Text("Pacientes").font(Tipo.titulo).foregroundStyle(Cor.texto)
                            .accessibilityAddTraits(.isHeader)
                        if let n = store.carga.valor?.count {
                            Text("\(n) em acompanhamento, em ordem alfabética.")
                                .font(Tipo.apoio).foregroundStyle(Cor.textoSuave).monospacedDigit()
                        }
                    }
                    .padding(.top, Espaco.s)
                    .padding(.bottom, Espaco.s)

                    CampoDeBusca(texto: $store.busca)
                        .padding(.bottom, Espaco.s)

                    if let erro = store.carga.erro {
                        CartaoDeErro(erro: erro) { Task { await store.carregar() } }
                    }

                    if store.carga.valor == nil, store.carga.erro == nil {
                        ForEach(0..<7, id: \.self) { _ in
                            HStack(spacing: 12) {
                                Esqueleto(largura: 40, altura: 40)
                                VStack(alignment: .leading, spacing: 8) { Esqueleto(largura: 150, altura: 12); Esqueleto(largura: 200, altura: 10) }
                                Spacer()
                            }
                            .padding(12).superficie(raio: Raio.linha)
                        }
                    } else if store.filtrados.isEmpty, store.carga.valor != nil {
                        EstadoVazio(titulo: "Ninguém com “\(store.busca)”.",
                                    texto: "A busca olha nome, diagnóstico e responsável.",
                                    icone: "magnifyingglass")
                            .superficie()
                    } else {
                        ForEach(Array(store.filtrados.enumerated()), id: \.element.id) { i, p in
                            NavigationLink(value: p) {
                                LinhaDePaciente(paciente: p)
                                    .matchedTransitionSource(id: p.id, in: transicao)
                            }
                            .buttonStyle(.pressionavel)
                            .entradaEscalonada(i)
                        }
                    }
                }
                .padding(.horizontal, Espaco.margem)
                .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .containerBackground(.clear, for: .navigation)
            .refreshable { Tato.leve(); await store.carregar() }
            .task { await store.carregar() }
            .encerraSessaoNo401(store.carga.erro)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PacienteDaLista.self) { p in
                ProntuarioView(pacienteId: p.id, nome: p.nome, situacao: nil)
                    .navigationTransition(.zoom(sourceID: p.id, in: transicao))
            }
        }
    }
}

private struct CampoDeBusca: View {
    @Binding var texto: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Cor.textoFraco)
            TextField("Nome, diagnóstico ou responsável", text: $texto)
                .font(Tipo.corpo)
                .foregroundStyle(Cor.texto)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !texto.isEmpty {
                Button { texto = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Cor.textoFraco)
                }
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .superficie(.afundado, raio: Raio.controle)
    }
}

private struct LinhaDePaciente: View {
    let paciente: PacienteDaLista

    var body: some View {
        HStack(spacing: 12) {
            Iniciais(nome: paciente.nome, tamanho: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(paciente.nome).font(Tipo.corpoForte).foregroundStyle(Cor.texto).lineLimit(1)
                Text(paciente.diagnostico).font(Tipo.apoio).foregroundStyle(Cor.textoSuave).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let c = paciente.numeroDoCiclo, let d = paciente.diaDoCiclo {
                    Text("C\(c) D\(d)").font(Tipo.colunaForte).foregroundStyle(Cor.texto)
                } else {
                    Text(paciente.emTratamento ? "—" : "fora").font(Tipo.colunaForte).foregroundStyle(Cor.textoFraco)
                }
                // Respondeu hoje é fato, não classificação: sem cor clínica.
                Text(paciente.respondeuHoje ? "respondeu" : "sem resposta")
                    .font(Tipo.rotulo)
                    .tracking(0.3)
                    .foregroundStyle(paciente.respondeuHoje ? Cor.textoSuave : Cor.textoFraco)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 68)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre o prontuário")
    }
}
