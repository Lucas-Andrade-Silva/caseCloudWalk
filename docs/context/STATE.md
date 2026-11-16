# Estado do projeto

Atualizado em: 2026-11-15

## Fase atual

Construção em andamento. **Fatias 01 (fundação) e 02 (ingestão e integração com o agente, sem telas)
implementadas, verdes e commitadas localmente.** Entrega até **2026-11-27**.
Próxima fatia: handoff e escalação (playbook §10, dias 19–20).

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002-arquitetura-stack-e-escopo.md` e
  `docs/decisions/0003-integracao-com-o-agente.md` (ordem da integração, ticket único, resposta atrasada).
- Especificações de fatia: `docs/specs/` (01 fundação, 02 ingestão e integração).
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`. Pesquisa de origem: `docs/research/`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build`
- **Gates** (resultado em 2026-11-15): `docker compose run --rm test` (plataforma, 59 exemplos),
  `docker compose run --rm broker-test` (14) e `docker compose run --rm mock-agent-test` (6). Zero falhas.
- **Ponta a ponta com a pilha no ar:** `docker compose exec api bundle exec rails smoke:round_trip`
- Um arquivo só: `docker compose run --rm test bundle exec rspec caminho/do_spec.rb`
- Lint da plataforma: `docker compose run --rm test bundle exec rubocop`
- Gate do frontend: ainda não existe (não há frontend).

## O que existe no código

Caminho de uma mensagem (ADR 0003):
`canal → api → outbox → relay → webhook → broker → Kafka → mock-agent → Kafka → broker-replies → api`

- `backend/` (Rails 8.1 API, Ruby 3.4, Postgres 17; **não fala com o Kafka**):
  - `POST /webhooks/channels/:channel` com HMAC e dedupe; `Ingestion::ReceiveMessage` grava webhook,
    cliente, ticket, mensagem, linha do tempo e outbox numa transação.
  - `POST /api/agent/replies` (token do bot); `Agent::RecordReply` é idempotente pelo `agent_turn_id`,
    marca resposta atrasada (`stale`) e descarta com auditoria por modo ou `handoff_epoch`.
  - `Outbox::Relay` + `Outbox::WebhookPublisher` + `Outbox::RelayProcess`; `Inbox` + `ProcessedEvent`.
  - Tabelas: `brands`, `users`, `customers`, `tickets`, `messages`, `inbound_events`,
    `conversation_events`, `outbox_events`, `processed_events`. Schema em `db/structure.sql`.
- `broker/` (Ruby puro, sem banco): `WebhookApp` (webhook → Kafka) e `RepliesConsumer` (Kafka → API).
  É o dono dos tópicos `helpdesk.messages` e `agent.replies` (12 partições, criados na subida).
- `mock_agent/` (Ruby puro): responde de forma determinística; `agent_turn_id` derivado do `event_id`.
- Ainda **não** existem: regras e filas, prioridade, handoff e painel, modo caos do mock, retry topics e
  DLQ, envio da resposta ao canal, ActionCable, frontend, RLS, LLM, Sidekiq, observabilidade.
  O Redis sobe no Compose, mas nada o usa ainda.

## Verdades vigentes

- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers. Gems e cache de boot em volumes.
- Tópicos do Kafka são criados de forma explícita (`auto.create.topics` desligado).
- Segredos e tokens do Compose são padrões de desenvolvimento (`.env.example`), só para dados sintéticos.
- O banco de teste fica vazio: seeds não rodam em teste e a suíte limpa o banco ao começar.

## Estado do repositório

- `docs/project-playbook` → `chore/platform-foundation` → `feat/agent-integration` (branches empilhadas).
- Só `docs/project-playbook` está no remoto. Nenhum PR aberto (a CLI `gh` não está autenticada).
- `feat/agent-integration` tem a fatia 02 num commit local, sem push e sem PR.

## Próximos passos

1. Dono confirma os contratos da fatia 02.
2. PRs das três branches, com revisão independente em outro chat.
3. Fatia 03: handoff (máquina de estados, três gatilhos, atribuição, brief), vigia de SLA (Sidekiq).

## Pendências do dono

- **Confirmar contratos da fatia 02** (rotas, campos e envelope em `docs/specs/02-...md`).
- Confirmar escolhas da fatia 01 (versões, `structure.sql`, tópicos explícitos).
- Desenho do enriquecimento por LLM agora que a plataforma não usa Kafka (ADR 0003, consequência de E1).
- O dia 27 inclui a apresentação? Agrupar em cerca de 5 PRs? Linguagem da análise (Python assumido).
- Níveis de prioridade e SLAs por prioridade.
- Definição do cluster do mapa vivo, limites de alerta e biblioteca do grafo.

## Bloqueios e riscos

- Prazo curto para o escopo escolhido; ordem de corte no playbook (§10), aplicada só com OK do dono.
- **Latência em desenvolvimento não vale como medida:** a ida e volta leva cerca de 0,6 s, e cada chamada
  à API gasta ~0,45 s fora do controller (`GET /up` leva 0,5 s). Causa provável: recarga de código do
  Rails sobre o disco do Windows. O experimento precisa rodar em modo de produção.
- O relay entrega um webhook por vez (mantém a ordem, limita a vazão). Medir no piloto de carga.
- Poison message ainda trava a partição do consumidor de respostas: falta retry topics e DLQ.
- A resposta do bot é gravada, mas ainda não é enviada de volta ao canal nem à tela.
- Não testado: máquina sem cache de imagens Docker, macOS e Linux.
- Desenho da arquitetura atual da CloudWalk ainda não recebido; os contratos são nossos e serão
  validados no onboarding.
