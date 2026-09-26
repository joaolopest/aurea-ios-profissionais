import SwiftUI

/// Início do administrador.
///
/// O web não tem painel geral: `/admin` redireciona direto para a lista de limiares. No app
/// a aba existe, então ela precisa ganhar o lugar — responde, em um olhar, as três perguntas
/// de quem entra aqui: qual algoritmo está classificando pacientes agora (e se alguém
/// assinou), tem rascunho esperando decisão, e o que andou acontecendo no registro de acessos.
/// O resto são as portas para as áreas que o acesso desta pessoa abre.
struct InicioAdminView: View {
    @State private var limiares = LimiaresStore()
    @State private var acessos: Carga<[RegistroDeAcesso]> = .carregando
    @Environment(Sessao.self) private var sessao

    private var acesso: Acesso {
        Acesso(perfil: sessao.eu?.perfil ?? "ADMINISTRADOR", permissoes: sessao.eu?.permissoes ?? [])
    }

    private var veAlgoritmo: Bool { Destino.limiares.permitido(acesso) }
    private var veAcessos: Bool { Destino.acessos.permitido(acesso) }

    var body: some View {
        TelaDeAba(aoAtualizar: { await carregar() }) {
            CabecalhoDeTela(rotulo: "Administração", titulo: "Início",
                            contexto: "O algoritmo em vigor, o que espera decisão e as áreas que o seu acesso abre.",
                            mostrarConta: true)
                .navigationDestination(for: RotaDoAlgoritmo.self) { telaDoAlgoritmo($0, store: limiares) }
                .navigationDestination(for: Destino.self) { telaSecundaria($0) }

            if veAlgoritmo {
                ConteudoDaCarga(carga: limiares.carga, linhasDeEsqueleto: 2,
                                tentarDeNovo: { Task { await limiares.carregar() } }) { conjuntos in
                    algoritmo(conjuntos)
                }
            }

            if veAcessos {
                registro
            }

            areas
        }
        .task { await carregar() }
    }

    private func carregar() async {
        async let a: Void = carregarAlgoritmo()
        async let b: Void = carregarAcessos()
        _ = await (a, b)
    }

    /// Cada bloco só pede o que o acesso permite: pedir e levar 403 seria mostrar erro
    /// onde a resposta certa é não mostrar o bloco.
    private func carregarAlgoritmo() async {
        guard veAlgoritmo else { return }
        await limiares.carregar()
    }

    private func carregarAcessos() async {
        guard veAcessos else { return }
        let anterior = acessos.valor
        do {
            acessos = .pronto(try await ClienteAPI.compartilhado.obter("/admin/registro-de-acessos",
                                                                     consulta: [URLQueryItem(name: "limite", value: "200")]))
        } catch {
            acessos = .falhou(ErroDaAPI(error), anterior: anterior)
        }
    }

    // MARK: Algoritmo em vigor

    @ViewBuilder
    private func algoritmo(_ conjuntos: [ConjuntoResumido]) -> some View {
        let publicado = conjuntos.first(where: \.ativo)
        let rascunhos = conjuntos.filter { $0.estado == .rascunho }

        if let publicado {
            NavigationLink(value: RotaDoAlgoritmo.conjunto(id: publicado.id)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Algoritmo em vigor").estiloDeRotulo()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Cor.textoFraco)
                    }
                    Text(publicado.versao)
                        .font(.custom("Plus Jakarta Sans", size: 34, relativeTo: .largeTitle).weight(.bold))
                        .foregroundStyle(Cor.azulProfundo)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("Classificando pacientes agora · \(publicado.regras) regras · \(publicado.classificacoesProduzidas) classificações")
                        .font(Tipo.apoio)
                        .monospacedDigit()
                        .foregroundStyle(Cor.textoSuave)
                    if let quando = publicado.publicadoEm {
                        Text("Publicado em \(DataDoAdmin.diaEHora(quando))")
                            .font(Tipo.apoio)
                            .monospacedDigit()
                            .foregroundStyle(Cor.textoFraco)
                    }
                    if publicado.validadoClinicamente {
                        Label("Validado clinicamente\(publicado.validadoPor.map { " por \($0.nome)" } ?? "")", systemImage: "checkmark.seal")
                            .font(Tipo.apoio)
                            .foregroundStyle(Cor.textoSuave)
                    } else {
                        AvisoNaoValidado(versao: publicado.versao)
                    }
                }
                .padding(Espaco.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cartaoDestaque(tom: Cor.auroraCeu)
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Abre as regras do conjunto em vigor")
            }
            .buttonStyle(.pressionavel)
        } else {
            AvisoDoAdmin(titulo: "Nenhum conjunto publicado",
                         texto: "Sem conjunto publicado, nenhum check-in está sendo classificado. Publique um na aba Algoritmo.",
                         grave: true)
        }

        if !rascunhos.isEmpty {
            CabecalhoDeSecao(titulo: "Esperando decisão", contagem: rascunhos.count)
            VStack(spacing: Espaco.s) {
                ForEach(Array(rascunhos.prefix(3).enumerated()), id: \.element.id) { i, r in
                    NavigationLink(value: RotaDoAlgoritmo.conjunto(id: r.id)) {
                        LinhaPadrao(icone: "doc.badge.clock", titulo: r.versao,
                                    apoio: "Rascunho de \(DataDoAdmin.dia(r.criadoEm)) · \(r.regras) regras\(r.validadoClinicamente ? "" : " · não validado clinicamente")")
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
        }
    }

    // MARK: Registro de acessos

    @ViewBuilder
    private var registro: some View {
        CabecalhoDeSecao(titulo: "Registro de acessos")
        if let erro = acessos.erro {
            CartaoDeErro(erro: erro) { Task { await carregarAcessos() } }
        } else if let registros = acessos.valor {
            let dia = registros.filter { $0.ocorridoEm > .now.addingTimeInterval(-86_400) }
            let leituras = dia.filter { $0.acao == "LEITURA_DE_HISTORICO" || $0.acao == "LEITURA_DE_PACIENTE" }.count
            // O pedido traz os 200 mais recentes: se todos caem nas últimas 24 h, o número
            // real pode ser maior, e a tela diz isso em vez de afirmar 200.
            let saturado = dia.count == registros.count && registros.count >= 200
            NavigationLink(value: Destino.acessos) {
                HStack(spacing: Espaco.s) {
                    CartaoDeIndicador(rotulo: "Últimas 24 h", valor: saturado ? "200+" : "\(dia.count)", apoio: "registros de acesso")
                    CartaoDeIndicador(rotulo: "Prontuários", valor: "\(leituras)", apoio: "leituras nas 24 h")
                }
            }
            .buttonStyle(.pressionavel)
            .accessibilityHint("Abre o registro de acessos")
        } else {
            HStack(spacing: Espaco.s) {
                LinhaDeEsqueleto()
                LinhaDeEsqueleto()
            }
        }
    }

    // MARK: Áreas

    @ViewBuilder
    private var areas: some View {
        let destinos = acesso.secundarios
        if !destinos.isEmpty {
            CabecalhoDeSecao(titulo: "Áreas", contagem: destinos.count)
            VStack(spacing: Espaco.s) {
                ForEach(Array(destinos.enumerated()), id: \.element) { i, destino in
                    NavigationLink(value: destino) {
                        LinhaPadrao(icone: destino.icone, titulo: destino.nome, apoio: destino.descricao)
                    }
                    .buttonStyle(.pressionavel)
                    .entradaEscalonada(i)
                }
            }
        }
    }
}
