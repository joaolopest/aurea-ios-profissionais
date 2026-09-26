# AUREA Plantão — app iOS da enfermagem

App nativo (SwiftUI, iOS 26, Swift 6) do profissional do AUREA — monitoramento remoto de
toxicidade em quimioterapia. Responde, em um segundo, a pergunta do plantão: **quem precisa
de mim agora?**

> 🔴 **Só dado sintético até a aprovação do Comitê de Ética** (decisão do João, 25/09/2026 —
> opção A). O app nasce com Face ID, Keychain, sem cache em disco e prontuário protegido de
> captura, mas não vai para aparelho de equipe antes do parecer.

## Rodar
```bash
cd ../aurea && pnpm dev     # API em :3333
./run.sh                    # gera o projeto (xcodegen), builda e abre no simulador
```
Conta de demonstração: `enfermagem@aurea.local` / `aurea-demo-2026`. A troca de senha do
primeiro acesso tem um "Pular" que só existe em DEBUG — a senha de demo é compartilhada.

## Onde está cada coisa
| Pasta | O quê |
|---|---|
| `Sistema/` | Design system: `Cores` (marca × faixa clínica), `Tipografia`, `Material` (ADR-006), `Movimento` (mola única + vocabulário de haptics) |
| `Dados/` | `ClienteAPI` (REST, token opaco, sem cache), modelos conferidos com **curl real** |
| `Seguranca/` | `Sessao` (entrar → trocar senha → trancado ⇄ dentro), Keychain, proteção de captura |
| `Funcoes/` | Plantão · Prontuário · Contatos · Pacientes · Conta · Entrada |
| `maestro/` | Fluxos de navegação usados na revisão |

## Leis que o código carrega
1. Verde/amarelo/vermelho só chegam por `Faixa.tons(SituacaoClinica)`. Nada mais usa essas cores.
2. Toda classificação aparece com a regra que a produziu, por extenso (prontuário).
3. Silêncio não é verde: quem não respondeu é cinza, e o sintoma antigo aparece rotulado como passado.
4. Modelos nascem da resposta real da API, nunca do tipo do web.

Briefing e DCM: `docs/BRIEFING-E-DCM.md`.
