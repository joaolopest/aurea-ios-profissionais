# Contratos da API conferidos pelo app iOS

Cada contrato abaixo foi modelado a partir da resposta REAL da API de dev (curl com o token
certo), não do tipo TypeScript do web. Formato: campo → tipo real. `?` = pode vir `null` em
algum item. Conferido em 25/09/2026. Os modelos Swift estão em `AureaPlantao/Dados/Modelos/`.

## Armadilhas (o que quebraria um cliente que confia no tipo)
| # | Onde | O que a API manda | O que parece |
|---|---|---|---|
| 1 | `regrasDisparadas[].valorObservado` (fila e histórico) | **4 tipos** na mesma chave: inteiro (`4`), decimal (`38.9`), booleano (`false`), texto (`"AO_CAMINHAR"`) | um `number` |
| 2 | `sessoesDeTriagem[].respostas[].valorNumerico` (`/historico`) | **string** (`"4"`) | `number` |
| 3 | `medicoAssistente` | **string** em `/painel/pacientes`, **objeto** `{nome, funcao}` em `/painel/pacientes/:id/historico` | mesmo tipo nos dois |
| 4 | `regrasDisparadas` do cartão `SEM_RESPOSTA_HOJE` | regras do ÚLTIMO check-in, que pode ter semanas | sinal de hoje |
| 5 | `POST /painel/solicitacoes-de-contato/:id/atendimento` | ignora o corpo — `registro` não é persistido | salvo |

## `POST /autenticacao/entrar`
`token: string` (opaco) · `expiraEm: ISO` · `perfil: PACIENTE|PROFISSIONAL|ADMINISTRADOR` · `precisaVerPrimeiroAcesso: bool`

## `GET /autenticacao/eu`
`id` · `perfil` · `permissoes: string[]` · `pacienteId?` · `profissionalId?` · `perfilDetalhado?: {id, nome, funcao?}`

## `GET /painel/pacientes-do-dia`
- `cards[]`: `pacienteId` · `nome` · `protocolo?` · `situacao: VERMELHO|AMARELO|VERDE|SEM_RESPOSTA_HOJE` · `respondeuHoje: bool` · `diasSemResponder: int?` · `nuncaRespondeu: bool` · `ultimaSessaoId?` · `diaDoCiclo: int?` · `regrasDisparadas[]` (ver abaixo) · `sinalizadores: {internadoAte: ISO?}` · `risco: {pontuacao, nivel: ALTO|MEDIO|BAIXO, fatores[{categoria, descricao, pontos}], versaoDosPesos, validadoClinicamente, baseSuficiente}` · `faixaDeSilencio: HOJE|UM_DIA|DOIS_DIAS|TRES_DIAS|UMA_SEMANA|NUNCA_RESPONDEU` · `nivelDePrioridade: ALTA|INTERMEDIARIA|BAIXA` · `motivos[{tipo: sintoma|silencio, texto}]`
- `regrasDisparadas[]`: `regraId` · `sintoma: FEBRE|DIARREIA|NAUSEA_VOMITO|DOR|FALTA_DE_AR` · `campo` · `valorObservado` (**4 tipos**) · `classificacao: AMARELO|VERMELHO` · `justificativa`
- `silencio`: `umDia · doisDias · tresDias · umaSemana · nuncaRespondeu · total`
- `resumo`: `total · vermelhos · amarelos · verdes · semResposta`

## `GET /painel/pacientes`
`itens[]`: `id` · `nome` · `dataNascimento` · `sexo` · `diagnostico` · `convenio?` · `protocolo?` · `emTratamento` · `diaDoCiclo?` · `numeroDoCiclo?` · `medicoAssistente?: string` (**texto**) · `responsavel?: {nome, telefone, relacao?, deEmergencia}` · `ultimaVisita?: {aconteceEm, local, tipo}` · `ultimoCheckinEm?` · `respondeuHoje` · `proximoCursor?`

## `GET /painel/pacientes/:id/historico`
Paciente + `medicoAssistente?: {nome, funcao}` (**objeto**) · `alergias[{descricao, origem, confirmadaEm?}]` · `comorbidades[…]` · `ecog` · `moraSozinho` · `dificuldadeDeTransporte` · `temCuidador` · `contextoSocialAvaliadoEm?` · `contatos[{tipo: CONTATO_DO_PACIENTE|CONTATO_DE_EMERGENCIA, nome, telefone, relacao?}]` · `barreiras[{id, tipo, descricao?, criadaEm}]` · `pendencias[…]` · `internacoes[{id, motivo, local?, iniciadaEm, altaEm?}]` · `prescricoes[{id, posologia, iniciadaEm, encerradaEm?, medicamento{nome, principioAtivo?}, prescritaPor?{nome, funcao}}]` · `eventosDeAgenda[{id, tipo: QUIMIOTERAPIA|CONSULTA_MEDICA|CONSULTA_NUTRICAO|CONSULTA_PSICOLOGIA, aconteceEm, local?}]` · `protocolo?` · `numeroDoCiclo?` · `diaDoCiclo?`
- `sessoesDeTriagem[]`: `id` · `estado: CONCLUIDA|ABANDONADA|EM_ANDAMENTO` · `iniciadaEm` · `concluidaEm?` · `respostas[{sintoma, campo, valorNumerico?: STRING, valorBooleano?, valorTexto?}]` · `classificacoes[{id, situacao: CLASSIFICADA|NAO_CLASSIFICADA, resultado?, motivoDeNaoClassificar?, calculadaEm, conjunto{versao, validadoClinicamente}, explicacao{porSintoma?[{sintoma, classificacao, regrasDisparadas[]}], sintomasNaoRespondidos?[], sintomasRespondidos?[]}}]` — `explicacao` é JSON livre: sessão abandonada vem sem `porSintoma`.

## `GET /painel/solicitacoes-de-contato`
`itens[{id, solicitadaEm, sessaoId?, paciente{id, nome}}]` · `proximoCursor?` · `aguardando: int` (extra no envelope)

## `POST /painel/solicitacoes-de-contato/:id/atendimento`
Resposta `{id, pacienteId, solicitadaEm, atendidaEm, atendidaPorId, atendidaPor{nome, funcao}}` · **409** quando outra pessoa atendeu antes · corpo ignorado.

## Painel e admin (portados na segunda onda)
Contratos de registro, condutas, cadeiras, toxicidade, navegação e de toda a área admin são
acrescentados aqui à medida que cada tela é portada.
