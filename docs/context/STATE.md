# Estado do projeto

Atualizado em: 2026-11-15

## Fase atual

Construção iniciada. A **fundação técnica (fatia 01) está implementada, verde e commitada localmente**.
Entrega até **2026-11-27**. Próxima fatia: ingestão ponta a ponta (dias 17–18 do playbook §10).

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões e justificativas: `docs/decisions/0002-arquitetura-stack-e-escopo.md`.
- Especificações de fatia: `docs/specs/` (a 01 descreve o que existe hoje).
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`. Pesquisa de origem: `docs/research/`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build`
- **Gate do backend:** `docker compose run --rm test` (18 exemplos, 0 falhas em 2026-11-15)
- Um arquivo só: `docker compose run --rm test bundle exec rspec caminho/do_spec.rb`
- Lint: `docker compose run --rm test bundle exec rubocop`
- Gate do frontend: ainda não existe (não há frontend).

## O que existe no código

- `compose.yaml`: Postgres 17, Redis 8.6, Apache Kafka 4.3 (KRaft, um nó), API Rails, relay, serviço `test`.
- `backend/`: Rails 8.1 em modo API, Ruby 3.4, Karafka 2.6, RSpec. Schema em `db/structure.sql`.
- `OutboxEvent` + `Outbox::Relay` (publica por `id`, at-least-once) + `Outbox::RelayProcess` (laço com
  advisory lock de instância única e backoff com jitter).
- `Inbox.process` + `ProcessedEvent` (efeito e registro na mesma transação) e `ApplicationConsumer`
  (base dos consumidores Karafka; a subclasse implementa `#handle`).
- Ainda **não** existem: tópicos e consumidores de produto, modelo de domínio, ingestão, frontend, Sidekiq.
  O Redis sobe no Compose, mas nada o usa ainda.

## Verdades vigentes

- Plataforma de help desk AI-first, multi marca. Agente da CloudWalk é externo e será simulado.
- Núcleo: Postgres + outbox + Kafka na borda + linha do tempo. Rails (API) + React (Vite), em Docker.
- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers. Cache de boot e gems ficam em volumes
  do Docker (no disco do Windows o boot do Rails leva cerca de 5 vezes mais).
- Tópicos do Kafka são criados de forma explícita (`auto.create.topics` desligado).

## Estado do repositório

- `docs/project-playbook`: publicada no remoto, **sem PR aberto** (o dono preferiu não abrir ainda).
- `chore/platform-foundation`: criada a partir de `docs/project-playbook`, com a fatia 01 num commit
  local. Ainda não foi publicada (sem push) nem tem PR.

## Próximos passos

1. Dono confirma as escolhas da fatia 01 (abaixo).
2. PRs dos docs e da fundação, com revisão independente em outro chat.
3. Fatia 02: ingestão por webhook (HMAC, dedupe), modelo de domínio mínimo, tópicos de produto, mock do
   agente, consumidor de `agent.replies`, linha do tempo, chat em React.

## Pendências do dono

- **Confirmar escolhas da fatia 01:** versões fixadas (Ruby 3.4, Rails 8.1, Postgres 17, Kafka 4.3,
  Redis 8.6); tabela `outbox_events` e colunas (ver spec 01); `structure.sql` em vez de `schema.rb`;
  `event_id` em UUID v7 no header da mensagem; Kafka sem criação automática de tópicos.
- O dia 27 inclui a apresentação? Agrupar em cerca de 5 PRs?
- Linguagem da análise (Python assumido) e do mock (Ruby assumido).
- Política para resposta do agente com `in_reply_to_seq` defasado.
- Níveis de prioridade e SLAs por prioridade.
- Definição do cluster do mapa vivo, limites de alerta e biblioteca do grafo.

## Bloqueios e riscos

- Prazo curto para o escopo escolhido; ordem de corte no playbook (§10), aplicada só com OK do dono.
- O risco de integração Karafka + Kafka + Docker caiu: a ida e volta roda nos testes e num clone limpo.
  Não testado: máquina sem cache de imagens Docker, macOS e Linux.
- Poison message ainda trava a partição: retry topics e DLQ entram com o primeiro consumidor de produto.
- Desenho da arquitetura atual da CloudWalk ainda não recebido; contrato com o agente é nosso e será
  validado no onboarding.
