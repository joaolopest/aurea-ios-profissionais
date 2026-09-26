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
