import SwiftUI

/// As cinco entidades administrativas do AUREA, na ordem em que um cadastro depende do
/// outro: paciente e equipe não dependem de nada; tratamento depende de paciente; ciclo,
/// de tratamento; prescrição, de paciente e do catálogo de medicamentos.
///
/// A dependência vai escrita em cada cartão, como no web: quem abre "Ciclos" antes de ter
/// tratamento cadastrado entende sozinho por que a lista está vazia.
enum EntidadeDoCadastro: String, CaseIterable, Hashable, Sendable {
    case pacientes, equipe, tratamentos, ciclos, prescricoes

    var titulo: String {
        switch self {
        case .pacientes: "Pacientes"
        case .equipe: "Equipe"
        case .tratamentos: "Tratamentos"
        case .ciclos: "Ciclos"
        case .prescricoes: "Prescrições"
        }
    }

    var descricao: String {
        switch self {
        case .pacientes: "Dados da pessoa em tratamento: identificação, diagnóstico e contatos."
        case .equipe: "Profissionais e usuários do sistema, com função e permissões de acesso."
        case .tratamentos: "Liga um paciente a um protocolo e a um médico assistente."
        case .ciclos: "Registra a sessão realizada dentro de um tratamento e projeta a próxima."
        case .prescricoes: "Associa um medicamento, dose, via e posologia a um paciente."
        }
    }

    var dependeDe: String {
        switch self {
        case .pacientes, .equipe: "Não depende de nenhum outro cadastro."
        case .tratamentos: "Depende de Pacientes e do cadastro de protocolos."
        case .ciclos: "Depende de Tratamentos e da duração de ciclo do protocolo."
        case .prescricoes: "Depende de Pacientes e do cadastro de medicamentos."
        }
    }

    var icone: String {
        switch self {
        case .pacientes: "person.text.rectangle"
        case .equipe: "person.badge.key"
        case .tratamentos: "stethoscope"
        case .ciclos: "arrow.triangle.2.circlepath"
        case .prescricoes: "doc.text"
        }
    }

    /// Equipe mora em outra rota da API (`gestao-de-usuarios.ts`), guardada por
    /// `GERENCIAR_USUARIOS` — não pela permissão desta aba. Mostrar o cartão aberto para
    /// quem não tem é mandar a pessoa a uma tela que devolve 403.
    var permissaoExigida: String {
        self == .equipe ? "GERENCIAR_USUARIOS" : "GERENCIAR_CADASTROS"
    }
}

/// A aba Cadastros do administrador.
struct CadastrosView: View {
    @Environment(Sessao.self) private var sessao

    private var permissoes: Set<String> { Set(sessao.eu?.permissoes ?? []) }

    var body: some View {
        TelaDeAba {
            CabecalhoDeTela(
                rotulo: "Administração",
                titulo: "Cadastros",
                contexto: "Pacientes, equipe, tratamentos, ciclos e prescrições, as cinco entidades administrativas do AUREA.",
                mostrarConta: true
            )

            VStack(spacing: Espaco.s) {
                ForEach(Array(EntidadeDoCadastro.allCases.enumerated()), id: \.element) { i, entidade in
                    let liberada = permissoes.contains(entidade.permissaoExigida)
                    Group {
                        if liberada {
                            NavigationLink(value: entidade) {
                                CartaoDeEntidade(entidade: entidade, liberada: true)
                            }
                            .buttonStyle(.pressionavel)
                        } else {
                            CartaoDeEntidade(entidade: entidade, liberada: false)
                        }
                    }
                    .entradaEscalonada(i)
                }
            }
            // Dentro da pilha da aba — fora dela o link não teria para onde empurrar.
            .navigationDestination(for: EntidadeDoCadastro.self) { entidade in
                switch entidade {
                case .pacientes: PacientesAdminView()
                case .equipe: EquipeView()
                case .tratamentos: TratamentosAdminView()
                case .ciclos: CiclosAdminView()
                case .prescricoes: PrescricoesAdminView()
                }
            }
        }
    }
}

private struct CartaoDeEntidade: View {
    let entidade: EntidadeDoCadastro
    let liberada: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entidade.icone)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(liberada ? Cor.azulProfundo : Cor.textoFraco)
                .frame(width: 44, height: 44)
                .background(Circle().fill(liberada ? Cor.azulGelo.opacity(0.35) : Cor.fundoBaixo))

            VStack(alignment: .leading, spacing: 5) {
                Text(entidade.titulo)
                    .font(Tipo.destaque)
                    .foregroundStyle(liberada ? Cor.texto : Cor.textoSuave)
                Text(entidade.descricao)
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoSuave)
                    .fixedSize(horizontal: false, vertical: true)
                Text(liberada ? entidade.dependeDe : "Seu acesso não inclui a gestão da equipe.")
                    .font(Tipo.apoio)
                    .foregroundStyle(Cor.textoFraco)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: liberada ? "chevron.right" : "lock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Cor.textoFraco.opacity(0.7))
                .padding(.top, 14)
        }
        .padding(Espaco.l)
        .superficie(raio: Raio.linha)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entidade.titulo). \(entidade.descricao)")
        .accessibilityHint(liberada ? entidade.dependeDe : "Bloqueado: seu acesso não inclui a gestão da equipe.")
    }
}
