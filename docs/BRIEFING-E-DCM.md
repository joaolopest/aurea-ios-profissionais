# Briefing Mobile + DCM — AUREA Plantão (profissional)

Aprovado pelo João em 25/09/2026. Fonte do produto: `aurea/docs/BRIEFING-MOBILE-PROFISSIONAL.md` (MAESTRO).

## Respostas (P1–P8)
- **P1** Ferramenta clínica de triagem, B2B · enfermagem de oncologia no plantão · várias vezes/dia, sessões <30 s. Refs: **Flighty** (fila e widget), **Linear iOS** (resto do app), **Steady** (atender).
- **P2** Autoridade silenciosa. **P3** Médio / diário curto.
- **P4** Light-only (decisão autoral; `UIUserInterfaceStyle = Light`).
- **P5** Anti-refs: prontuário hospitalar legado (Tasy/MV) · tutorial SwiftUI / Settings.app.
- **P6** Clínico direto no dado + calor humano só nas bordas (saudação, vazio como boa notícia). Proibido: "Carregando…", "Algo deu errado", "Bem-vindo!", nome/diagnóstico em notificação.
- **P7 invioláveis** Cor = só faixa clínica · fila em 1 segundo após o Face ID · atender em 2 toques com 409 tratado. (Regra por extenso permanece lei do produto.)
- **P8** Patamar 1 com assinatura.
- **Comitê de Ética:** opção A — construir com dado sintético; produção só depois do parecer.

## DCM (resumo do que foi aplicado)
- **Cor:** azul `#0e2739` marca e ação; lima `#dff178` só acento (contador de contatos). Escala clínica do web, sem alteração.
- **Tipo:** Plus Jakarta Sans (Dynamic Type via `relativeTo:`); IBM Plex Mono **só em coluna**; em frase, sans com `monospacedDigit` (ADR-006 Onda 2).
- **Motion:** uma mola (`response 0.35 / damping 0.86`), saída mais rápida que chegada; zoom nativo linha → prontuário; `numericText` no número-herói; Reduce Motion congela.
- **Haptics:** seleção (aba/filtro) · sucesso (atendido) · aviso (409) · leve (puxar) · erro.
- **Material:** 5 níveis do ADR-006 como `.superficie()`: sombra em tinta, luz no topo, cantos contínuos.
- **Navegação:** 3 abas numa cápsula flutuante (Plantão · Contatos · Pacientes); conta pelo avatar.
- **Segurança:** Face ID/código ao abrir e ao voltar do fundo · capa no seletor de apps · token no Keychain `WhenUnlockedThisDeviceOnly` · `URLSession` efêmera sem cache · prontuário fora de screenshot/gravação.
- **Cortado:** Live Activity (sem evento finito no trabalho da enfermeira). **Fase 2:** widget só com número. **Fase 3:** push via APNs (depende do Prumo).

## Revisão 1 — estética do BT Professor (25/09/2026, pedido do João)

- **Mantido claro** (P4 confirmada): a receita do BT (`~/projetos/bt200/btprofessor-frontend`) traduzida para o fundo claro.
- **Fundo vivo** (`Sistema/FundoVivo.swift`): aurora de manchas borradas derivando no relógio + grão de papel; um tom por aba — céu (Plantão), aço (Contatos), índigo (Pacientes). Reduce Motion congela.
- **Lima fora do app** (decisão do João): sobre o cinza e o azul o lima é lido como verde, e verde/amarelo/vermelho são só dos pacientes. `Cor.lima` ficou marcado como `deprecated` com o motivo. Acento agora é azul: pílulas, CTA e barra em azul profundo; número-herói em azul-gelo `#A9D4FF`. Ícone do app trocado para o ponto azul-gelo.
- **Vidro**: barra de abas e faixa "Ao vivo" em `.ultraThinMaterial` sobre a aurora; pílula ativa desliza (matched geometry); ícones com `symbolEffect(.bounce)`.
- **Faixa "Ao vivo"** acima das abas (o lugar do clima no BT). Para ser verdade, a fila e os pedidos atualizam sozinhos a cada 60 s com o app na frente.
- **Cartão de destaque** com brilho no canto (resumo de Contatos); **entrada escalonada** nas listas; **pressionar com haptic** no próprio `ButtonStyle`.
- **Face ID DESLIGADO** a pedido do João: entra só com e-mail e senha, como o web. Código da tranca intacto atrás de `Sessao.trancaBiometricaLigada`. ⚠️ Volta à mesa com o parecer do Comitê de Ética.

## Revisão 2 — app completo, todos os perfis (26/09/2026, pedido do João)

- **Acesso por permissão, não por profissão** (`App/Destinos.swift`): cada destino espelha o
  `exigirPermissao` da rota. Enfermagem: Plantão · Contatos · Pacientes · Mais (Condutas,
  Cadeiras, Toxicidade, Navegação). Médico e farmacêutico (só VER_HISTORICO): Plantão ·
  Pacientes · Mais, sem Contatos/Cadeiras e sem nenhum botão de registro no prontuário.
  Administrador: Início · Algoritmo · Cadastros · Mais (Orientações, Protocolos, Medicamentos,
  Equipe, Acessos; Pesquisa para quem exporta).
- **Paridade com o web**: registro do plantão (barreira, pendência, internação, contexto
  social, conduta), condutas, giro de cadeiras, toxicidade, navegação; admin inteiro
  (algoritmo com diferença/novo/publicar/validar, cadastros de paciente, tratamento, ciclo,
  prescrição, protocolo, medicamento, equipe e permissões, registro de acessos, pesquisa).
- **Onde o app NÃO copia o web, de propósito**: não pede o texto do atendimento (a API
  descarta); orientações só leitura (a escrita vai para um rascunho que nada lê nem publica);
  sem campos de dose/via/fim na prescrição (a API não tem); datas civis lidas em UTC (o web
  mostrava um dia a menos). Defeitos 1–26 mandados ao MAESTRO com curl.
- **Farmacêutico**: função pedida ao Prumo; permissão decidida pelo João = só
  VER_HISTORICO_DE_PACIENTE. O app não precisa mudar.
- Construção: base e integração por mim; telas portadas por 6 agentes em cópias isoladas,
  seguindo `docs/COMO-CONSTRUIR-TELA.md`.
