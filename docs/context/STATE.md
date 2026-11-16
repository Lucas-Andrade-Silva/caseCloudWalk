# Estado do projeto

Atualizado em: 2026-11-15

## Fase atual

Construção em andamento. Fatias 01 (fundação) e 02 (ingestão e integração com o agente) commitadas
localmente. **Fatia 03 (handoff e escalação, sem telas) implementada e verde, ainda sem commit.**
Entrega até **2026-11-27**. Próxima fatia: regras e filas configuráveis (playbook §10).

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002-arquitetura-stack-e-escopo.md`,
  `docs/decisions/0003-integracao-com-o-agente.md` (ordem da integração, ticket único, resposta atrasada) e
  `docs/decisions/0004-handoff-prioridade-e-atribuicao.md` (escalação, filas iniciais, P1–P4, atribuição,
  `sidekiq-cron`, agente mudo escala com 30 s de limite e meta de ≤ 40 s).
- Especificações de fatia: `docs/specs/` (01 fundação, 02 ingestão e integração, 03 handoff).
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`. Pesquisa de origem: `docs/research/`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build`
- **Gates** (resultado em 2026-11-15): `docker compose run --rm test` (plataforma, 104 exemplos),
  `docker compose run --rm broker-test` (14) e `docker compose run --rm mock-agent-test` (12). Zero falhas.
- **Fumaça com a pilha no ar** (`docker compose exec api bundle exec rails <tarefa>`):
  `smoke:round_trip` (agente responde), `smoke:escalation` (agente escala, analista puxa, responde e fecha)
  e `smoke:agent_silence` (pare o `mock-agent` antes; o vigia escala).
- Um arquivo só: `docker compose run --rm test bundle exec rspec caminho/do_spec.rb`
- Lint da plataforma: `docker compose run --rm test bundle exec rubocop`
- Gate do frontend: ainda não existe (não há frontend).

## O que existe no código

Caminho de uma mensagem (ADR 0003):
`canal → api → outbox → relay → webhook → broker → Kafka → mock-agent → Kafka → broker-replies → api`

- `backend/` (Rails 8.1 API, Ruby 3.4, Postgres 17; **não fala com o Kafka**):
  - Entrada de canal com HMAC e dedupe; `Ingestion::ReceiveMessage` grava tudo numa transação.
  - `POST /api/agent/replies` (token do bot): `reply` e `escalate`, idempotente pelo `agent_turn_id`.
  - Handoff: `Ticket#transition_to!` (máquina de estados, `handoff_epoch` sobe a cada troca de dono),
    `Handoff::Escalate` (fila padrão da marca, prazo pela prioridade, brief por template, aviso ao agente),
    `Handoff::AssignNext` (prazo mais próximo, `FOR UPDATE SKIP LOCKED`), `Handoff::AgentSilenceWatchdog`.
  - Rotas do analista (token `analyst`): `POST /api/work/next`, `GET /api/tickets/:id`,
    `POST /api/tickets/:id/takeover|messages|close`. Marca que ele não atende responde 404.
  - Sidekiq + `sidekiq-cron`: `AgentSilenceWatchdogJob` a cada 5 s (`config/schedule.yml`).
  - Tabelas novas: `priority_levels`, `queues`, `queue_memberships`; `tickets` ganhou fila, prioridade,
    dono, prazos, brief e `awaiting_agent_since`.
- `broker/` (Ruby puro, sem banco): webhook → Kafka e Kafka → API. Dono dos tópicos da borda do agente.
- `mock_agent/` (Ruby puro): responde ou escala (30% por padrão, `MOCK_ESCALATION_RATE`), de forma
  determinística pelo `event_id`. As marcas `[escalar]` e `[responder]` no texto forçam a decisão.
- Seeds de desenvolvimento: filas `infinitepay-atendimento` e `jim-atendimento`; analistas Ana
  (InfinitePay), Bruno (JIM) e Carla (as duas), com tokens `dev-analyst-<nome>`.
- Ainda **não** existem: regras e filas configuráveis, gatilhos por fatos (cliente pediu humano,
  frustração, valor), modo caos do mock, retry topics e DLQ, envio da resposta ao canal, ActionCable,
  frontend, RLS, LLM, observabilidade.

## Verdades vigentes

- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers. Gems e cache de boot em volumes.
- Tópicos do Kafka são criados de forma explícita (`auto.create.topics` desligado).
- Segredos e tokens do Compose são padrões de desenvolvimento (`.env.example`), só para dados sintéticos.
- O banco de teste fica vazio: seeds não rodam em teste e a suíte limpa o banco ao começar. Por isso
  migrações precisam ser testadas também contra o banco de desenvolvimento, que tem dados.

## Estado do repositório

- `docs/project-playbook` → `chore/platform-foundation` → `feat/agent-integration` →
  `feat/handoff-escalation` (empilhadas). A última tem a fatia 03 **sem commit**.
- Só `docs/project-playbook` está no remoto. Nenhum PR aberto (a CLI `gh` não está autenticada).

## Próximos passos

1. Dono pede o commit da fatia 03.
2. PRs das quatro branches, com revisão independente em outro chat.
3. Fatia 04: regras e filas configuráveis (JSON, versões, dry-run), que passam a escolher fila e prioridade.

## Pendências do dono

- Confirmar contratos das fatias 02 e 03 e as marcas `[escalar]`/`[responder]` do mock.
- Confirmar escolhas da fatia 01 (versões, `structure.sql`, tópicos explícitos).
- Desenho do enriquecimento por LLM agora que a plataforma não usa Kafka (ADR 0003, consequência de E1).
- O dia 27 inclui a apresentação? Agrupar em cerca de 5 PRs? Linguagem da análise (Python assumido).
- Definição do cluster do mapa vivo, limites de alerta e biblioteca do grafo.

## Bloqueios e riscos

- Prazo curto para o escopo escolhido; ordem de corte no playbook (§10), aplicada só com OK do dono.
- **Latência em desenvolvimento não vale como medida:** cada chamada à API gasta ~0,45 s fora do
  controller. Causa provável: recarga de código do Rails sobre o disco do Windows. O experimento precisa
  rodar em modo de produção.
- O relay entrega um webhook por vez (mantém a ordem, limita a vazão). Medir no piloto de carga.
- Poison message ainda trava a partição do consumidor de respostas: falta retry topics e DLQ.
- As respostas do bot e do analista são gravadas, mas ainda não chegam ao canal nem a uma tela.
- Ninguém é avisado quando o prazo de SLA humano estoura; só fica registrado na primeira resposta.
- Não testado: máquina sem cache de imagens Docker, macOS e Linux.
- Desenho da arquitetura atual da CloudWalk ainda não recebido; os contratos são nossos.
