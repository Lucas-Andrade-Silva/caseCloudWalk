# Estado do projeto

Atualizado em: 2026-11-15

## Fase atual

Ideação concluída e decisões de arquitetura fechadas. Nenhum código de produto existe ainda.
Próxima fase: construção em TDD, com **entrega até 2026-11-27** (13 dias contando 15 e 27).

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões e justificativas: `docs/decisions/0002-arquitetura-stack-e-escopo.md`.
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`. Pesquisa de origem: `docs/research/`.

## Verdades vigentes

- Plataforma de help desk AI-first, multi marca. Agente da CloudWalk é externo e será simulado.
- Núcleo: Postgres + outbox + Kafka na borda + linha do tempo. Rails (API) + React (Vite), em Docker.
- Kafka + Sidekiq; regras de fila em JSON próprio; LLM via Groq com stub, replay e live.
- IA no primeiro nível, humano por escalação; mapa vivo estilo Obsidian como diferencial visual.
- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Ambiente: Windows 11, Docker instalado (Desktop precisa ser iniciado), **sem Ruby local**.

## Estado do repositório

- Branch `docs/project-playbook` (a partir da `main` já com a fundação, PR #1 mesclado), publicada no
  remoto, com um commit de docs: ADR 0002, `PLAYBOOK.md`, `AGENTS.md`, este arquivo, o PDF do TAPI e
  `docs/research/`. PR contra `main` aguardando revisão independente em outro chat.

## Próximos passos

1. Dono revisa o playbook e o ADR, e responde as pendências abaixo.
2. Revisão independente do PR dos docs (`$review-pr` em outro chat) e merge.
3. Fundação técnica: Docker Compose (Postgres, Redis, Kafka, Rails) e teste do Karafka com o outbox.
4. Fatia ponta a ponta em TDD, depois seguir o plano do playbook (§10).

## Pendências do dono

- O dia 27 inclui a apresentação? Agrupar em cerca de 5 PRs?
- Linguagem da análise (Python assumido) e do mock (Ruby assumido).
- Política para resposta do agente com `in_reply_to_seq` defasado.
- Níveis de prioridade e SLAs por prioridade.
- Definição do cluster do mapa vivo, limites de alerta e biblioteca do grafo.

## Bloqueios e riscos

- Prazo curto para o escopo escolhido; ordem de corte no playbook (§10), aplicada só com OK do dono.
- Risco principal: integração Karafka + Kafka + Docker (teste nos dias 15 e 16).
- Desenho da arquitetura atual da CloudWalk ainda não recebido; contrato com o agente é nosso e será
  validado no onboarding.
- O gate oficial de testes ainda não existe; será definido no scaffold e registrado aqui.
