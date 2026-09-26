# Contornos: onde o app compensa defeito do backend

Cada contorno abaixo é correto HOJE e vira dívida no dia em que a causa for corrigida.
Sem esta lista, daqui a três meses ninguém sabe se um filtro ainda é necessário ou se está
escondendo regressão. (Pedido do MAESTRO na revisão de 26/09/2026.)

**Regra de manutenção:** corrigiu a causa no backend → rode o teste da coluna "como saber
que pode remover" → remova o contorno no MESMO commit que atualiza esta tabela.

`#N` = numeração da lista de defeitos enviada ao MAESTRO em 25–26/09/2026.
`Q-N` = item do quadro do MAESTRO, quando ele atribuiu número.

## Contornos ativos

| # | Contorno no app | Onde | Causa | Como saber que pode remover |
|---|---|---|---|---|
| 1 | Atender pedido de contato **não pede texto** | `Funcoes/Contatos/ContatosView.swift` | `POST /painel/solicitacoes-de-contato/:id/atendimento` ignora o corpo; não há coluna `registro` (#5, Q-241) | A resposta do POST devolve `registro` e a leitura seguinte também. Então **acrescentar** o campo — o contorno aqui é a ausência dele |
| 2 | Filtro de condutas só manda `incluirResolvidas` quando `true` | `Funcoes/Intervencoes/IntervencoesView.swift` | `z.coerce.boolean("false") === true` (#14, Q-249…254) | `curl ".../painel/intervencoes?incluirResolvidas=false"` devolve só as abertas |
| 3 | Toxicidade só oferece janelas 7/14/30/90/365 | `Funcoes/Toxicidade/ToxicidadeView.swift` | `?dias` inválido dá 500 em vez de 400 (#6) | `curl ".../indicadores-de-toxicidade?dias=5"` → 400. (A restrição de UI pode ficar por produto; o que sai é a suposição de que o servidor quebra) |
| 4 | Giro de cadeiras **filtra janelas livres já passadas** | `Funcoes/Cadeiras/CadeirasView.swift` (`janelasLivres.filter { $0.ate > ctx.date }`) | `janelasLivres` incluiria janelas encerradas (#26 — **não reproduzido** às 00h12; testar no expediente) | Em horário de expediente, nenhuma janela de `GET /painel/cadeiras` tem `ate` no passado |
| 5 | App **avisa e bloqueia** sessão em cadeira ocupada | `Funcoes/Cadeiras/CadeirasFolhas.swift` | API aceita duas sessões na mesma cadeira e horário (#19) | Segundo `POST /painel/cadeiras/sessoes` sobreposto responde 409 |
| 6 | Sessão só oferece a **próxima etapa válida** | `Funcoes/Cadeiras/CadeirasFolhas.swift` (`acoes`) + `estado.proximo` em `CadeirasModelos.swift` | `PATCH /painel/cadeiras/sessoes/:id` aceita qualquer transição, inclusive reabrir CONCLUIDA (#20) | `PATCH` de CONCLUIDA para EM_INFUSAO responde 4xx |
| 7 | Agendamento limitado ao **expediente de hoje** | `Funcoes/Cadeiras/CadeirasFolhas.swift` | Sessão fora do expediente é gravada e nunca aparece no painel (#23, #25) | Sessão agendada às 06h aparece em `sessoesDoDia` |
| 8 | Nova cadeira avisa **número já existente** | `Funcoes/Cadeiras/CadeirasFolhas.swift` | `POST /painel/cadeiras` é upsert silencioso (#21) | Número existente responde 409 (ou a rota ganha PATCH explícito) |
| 9 | Campo "observação" da sessão **não existe** no app | `Funcoes/Cadeiras/` | Observação é gravada e nenhuma leitura a devolve (#22) | `GET /painel/cadeiras` traz `observacao` na sessão → acrescentar o campo |
| 10 | Protocolo e medicamento **bloqueiam nome repetido/curto antes de enviar** | `Funcoes/Admin/Catalogos/` | Nome repetido ou < 2 caracteres dá 500 (#7) | Os mesmos POSTs respondem 409 / 400 |
| 11 | Tratamento e prescrição **sem "médico responsável" / "prescrito por"** no formulário | `Funcoes/Admin/Tratamentos/` | Não há rota que liste profissionais com o `id` do Profissional (#8) | Existe `GET` de profissionais com `id` → acrescentar o seletor |
| 12 | Paciente novo: **história de vida só na edição**, contatos num segundo passo | `Funcoes/Admin/Cadastros/Pacientes/` | `POST /admin/pacientes` aceita e descarta tabagismo/atividade/álcool; não recebe contatos | POST com `tabagismo` volta com o valor na ficha → juntar ao formulário de criação |
| 13 | Agenda na ficha do paciente mostra **só eventos criados neste aparelho** (e diz isso) | `Funcoes/Admin/Cadastros/Pacientes/` | Não há `GET` de agenda para `GERENCIAR_CADASTROS` | Existe a rota de leitura → ler do servidor e apagar o cache local |
| 14 | Ao deixar de ser ex-fumante, o app manda `parouDeFumarEm: null` junto | `Funcoes/Admin/Cadastros/Pacientes/` | PATCH só com `tabagismo` deixa a data antiga no banco | PATCH só com `tabagismo` limpa a data sozinho |
| 15 | Orientações **só leitura** | `Funcoes/Admin/Orientacoes/` | Escrita vai para um rascunho clonado que nenhuma rota lê nem publica | Existem GET e publicação do rascunho de orientações |
| 16 | Tratamento lista "encerrado" **sem data** | `Funcoes/Admin/Tratamentos/` | `GET /admin/tratamentos` não devolve `encerradoEm` (#9) | O campo vem na lista → exibir |
| 17 | Condutas **sem** o aviso "não validado clinicamente" | `Funcoes/Intervencoes/` | `/painel/intervencoes` não diz se o conjunto foi validado (#16) — lei 2 do produto obriga o aviso | O campo vem na resposta → **acrescentar** o aviso (isto é pendência de lei, não só dívida) |

## Dívida interna (o app contornando o próprio app)

| Contorno | Onde | Causa | Como remover |
|---|---|---|---|
| Tradutores de erro por tela: `MensagemDeCadastro`, `MensagemDoGiro`, `ChamadaDoAdmin`, `ErroDoCadastro` | Admin/Tratamentos, Cadeiras, Admin/Limiares, Admin/Cadastros | Os agentes escreveram antes de o `ClienteAPI` ler a chave `erro` da API (corrigido em 26/09) | Trocar cada um por `ErroDaAPI.mensagem` e conferir que a frase do servidor aparece; apagar os tipos |
| Botão de ação próprio de 44 pt no prontuário | `Funcoes/Prontuario/ProntuarioView.swift` | O compartilhado tinha 40 pt (corrigido para 44 em 26/09) | Usar o compartilhado e apagar a cópia |

## Não são contornos (permanentes — não remover)
- **Data civil lida em UTC** (`Dados/DataCivil.swift`): é a semântica correta de `@db.Date`, não defeito.
- **Telefone para ligar buscado no `/historico`**: gera `LEITURA_DE_HISTORICO`, auditoria correta porque a enfermeira vai ler o histórico antes de ligar. O MAESTRO pediu para manter mesmo depois que a fila trouxer o telefone.
- **Data de sessão de cadeira enviada como texto ISO**: exigência do contrato; número seria aceito como outra data sem erro.
- **Enums com `.desconhecido(String)`**: resiliência a valor novo da API.
