# Como construir uma tela do AUREA Plantão

Guia obrigatório para quem porta uma tela do web para o app. Leia inteiro antes de escrever
Swift. O app tem que parecer UM objeto — a mesma mão em todas as telas.

## 0. Leia primeiro (nesta ordem)
1. `README.md` e `docs/BRIEFING-E-DCM.md` — o briefing aprovado e as decisões de design.
2. `AureaPlantao/Sistema/` inteiro — `Cores`, `Tipografia`, `Material`, `Movimento`, `FundoVivo`,
   `Componentes/Componentes.swift`, `Componentes/Tela.swift`, `Componentes/Formulario.swift`.
3. Telas de referência já prontas (copie o padrão, não reinvente):
   `Funcoes/Plantao/PlantaoView.swift`, `Funcoes/Contatos/ContatosView.swift`,
   `Funcoes/Prontuario/ProntuarioView.swift`, `Funcoes/Mais/MaisView.swift`.
4. A tela do web que você está portando (`/Users/joaolopes/Projetos-Zenix/aurea/apps/web/src/app/...`)
   e as rotas da API que ela usa (`/Users/joaolopes/Projetos-Zenix/aurea/apps/api/src/rotas/*.ts`).
   Porte o CONTEÚDO, o COMPORTAMENTO e o TEXTO (microcopy em PT-BR) — não o layout de desktop.
   Sidebar, tabela larga e modal de desktop viram lista, cartão, folha (`.sheet`) no iPhone.

## 1. Leis clínicas — quebrar qualquer uma é defeito grave
1. **Verde, amarelo, vermelho e cinza-silêncio são SÓ classificação de paciente.** A única
   porta para essas cores é `Faixa.tons(SituacaoClinica)`. Botão, ícone, gráfico, badge de
   status administrativo, NADA disso usa essas cores.
2. **Nada de lima** (`Cor.lima` está deprecated): no app ele é lido como verde.
3. **Acento é azul**: `Cor.azulProfundo` (ação/seleção), `Cor.azulGelo` (número que acende
   sobre azul), `Cor.auroraCeu/Aco/Indigo` (brilhos). Gráfico de dado não-clínico usa a paleta
   de dado do ADR-005 **sem o petróleo-teal**: `#35597f` azul-aço, `#4c4a86` índigo,
   `#74477a` ameixa, `#8a4668` vinho-rosa, `#6f6f72` neutro. Máximo 5 séries + "Outras".
4. **Toda classificação mostra a regra que a produziu, por extenso.**
5. **Silêncio não é verde.** Quem não respondeu é cinza, nunca verde por omissão.
6. **Sem validação clínica assinada, a interface diz "não validado clinicamente"** onde houver
   conjunto de regras (use `AvisoNaoValidado`).

## 2. Contrato com a API — a lição que custou seis bugs
- **Modele o `Decodable` a partir da RESPOSTA REAL**, nunca do tipo TypeScript do web. Para
  CADA endpoint: faça `curl` com o token certo, rode sobre a resposta inteira e anote o
  formato. Campo que pode vir `null` em algum item é opcional; campo que sempre vem não é.
- Armadilhas já encontradas: `valorObservado` vem em 4 tipos; `respostas.valorNumerico` vem
  como STRING; `medicoAssistente` é texto em `/painel/pacientes` e objeto no `/historico`;
  `solicitadaEm` (não `criadaEm`); alergia é `descricao` (não `substancia`);
  `motivoDeNaoClassificar` (não `motivo`); `CONSULTA_MEDICA` (não `CONSULTA`).
- Enum da API vira enum Swift **com caso `.desconhecido(String)`** — valor novo não pode
  derrubar a tela.
- **Todo POST/PATCH que a tela faz: confira que o servidor GRAVA** (leia de volta depois).
  O web tinha um campo obrigatório que a API aceitava com 200 e jogava fora. Se encontrar um
  assim, NÃO construa a UI dele: registre no relatório.
- Tokens (API dev em `http://localhost:3333`, senha de todas: `aurea-demo-2026`):
  ```bash
  T=$(curl -s -X POST localhost:3333/autenticacao/entrar -H 'content-type: application/json' \
    -d '{"email":"enfermagem@aurea.local","senha":"aurea-demo-2026"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
  curl -s -H "authorization: Bearer $T" localhost:3333/painel/navegacao | python3 -m json.tool
  ```
  Contas: `enfermagem@` (plantão), `medico@` (só ver histórico), `admin@` (cadastros,
  usuários, algoritmo, orientação). **Nunca** chame `/conta/senha` (a senha é compartilhada).
- Banco de dev é sintético. Pode criar registro para testar escrita; limpe o que criar quando
  houver rota de remoção; nomes de teste sempre com "(teste app)".

## 3. Arquitetura
- SwiftUI puro, iOS 26, Swift 6 com concorrência estrita. Zero dependência externa.
- Estado: `@MainActor @Observable final class XStore` por tela, com `carga: Carga<Valor>`
  (`Dados/Carga.swift`) e `ErroDaAPI(error)` no catch. Chamadas via `ClienteAPI.compartilhado`
  (`obter`, `enviar`, `atualizar` (PATCH), `remover` (DELETE)).
- 401 encerra a sessão: `.encerraSessaoNo401(store.carga.erro)` (o `ConteudoDaCarga` já faz).
- 403 vira mensagem honesta ("Seu acesso não inclui …"), nunca tela quebrada.
- Nomes de tipo, variável, função e comentário em **português**. Comentário explica o PORQUÊ
  (veja o estilo das telas prontas), não o quê.

## 4. Composição de tela
- **Aba** (Início admin, Algoritmo, Cadastros): `TelaDeAba { CabecalhoDeTela(…, mostrarConta: true) … }`.
- **Tela empurrada** (do "Mais" ou de uma lista): `TelaRolavel { CabecalhoDeTela(…) … }` —
  NÃO crie NavigationStack. Dentro de `TelaDeAba`, detalhes via `NavigationLink(value:)` +
  `.navigationDestination(for:)` colocado DENTRO do conteúdo da pilha.
- Listas: `LinhaPadrao` ou linha própria com `.superficie(raio: Raio.linha)`, `.buttonStyle(.pressionavel)`,
  `.entradaEscalonada(i)`. Carga: `ConteudoDaCarga` (esqueleto, erro, vazio com texto próprio).
- Indicadores: `CartaoDeIndicador` (um só com `destaque: true` por tela). Destaque de assunto:
  `.cartaoDestaque(tom:)` — um por tela.
- Filtros: `SeletorDePilulas`. Formulários: `FolhaDeFormulario` em `.sheet` com
  `.presentationDetents([.large])`, campos `CampoDeEntrada`, `CampoDeTextoLongo`,
  `CampoDeEscolha`, `CampoDeData`, `CampoInterruptor`, `CampoNumerico`. Ação em seção:
  `BotaoDeAcaoEmLinha`. Sucesso: `.avisoTemporario($mensagem)` + `Tato.sucesso()`.
- Gráficos: Swift Charts nativo, cores da paleta de dado (seção 1.3), `.accessibilityLabel`
  com os números por extenso — gráfico nunca depende só de cor.
- Números: `.monospacedDigit()`. Mono (`Tipo.coluna`) SÓ em coluna alinhada, nunca em frase.

## 5. Microcopy
- Direto, sem eufemismo clínico, tom do web. Proibido: "Carregando…", "Algo deu errado",
  "Nenhum item encontrado", "Sucesso!", "Bem-vindo". Vazio diz o que significa ("Ninguém
  internado agora."). Erro diz o que fazer.

## 6. Acessibilidade
- Toque mínimo 44 pt (frame no RÓTULO do botão, não no botão). Todo campo com rótulo
  acessível. Linha com `.accessibilityElement(children: .combine)` e rótulo por extenso.
  Reduce Motion respeitado (os componentes já fazem).

## 7. Verificação antes de dizer "pronto"
```bash
xcodegen generate --quiet
xcodebuild -project AureaPlantao.xcodeproj -scheme AureaPlantao -configuration Debug \
  -destination "generic/platform=iOS Simulator" -derivedDataPath build build 2>&1 \
  | grep -E "error:|warning:|BUILD" | grep -v appintents | sort -u
```
Tem que dar `BUILD SUCCEEDED` com **zero warnings** dos seus arquivos.
