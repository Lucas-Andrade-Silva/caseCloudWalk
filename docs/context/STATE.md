# Estado do projeto

Atualizado em: 2026-11-16

## Fase atual

Construção em andamento. Fatias 01 (fundação), 02 (integração com o agente) e 03 (handoff) commitadas
localmente. **Fatia 04 (equipes, filas e regras configuráveis, sem telas) implementada e verde, ainda sem
commit.** Entrega até **2026-11-27**. Próxima: resiliência (retry topics, DLQ, modo caos do mock e verificador
de invariantes), conforme o playbook §10.

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002` (arquitetura e escopo), `0003` (integração com o agente, ticket único,
  resposta atrasada), `0004` (escalação, P1–P4, atribuição, `sidekiq-cron`, agente mudo: limite de 30 s e
  meta de ≤ 40 s) e `0005` (equipes, regras em dois momentos, fatos, versões, auditoria).
- Especificações de fatia: `docs/specs/01` a `04`.
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`. Pesquisa de origem: `docs/research/`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build` (se só o código mudou, `docker compose up -d --force-recreate
  api` aplica migrações; reinicie `relay`, `sidekiq` e consumidores, que são processos longos).
- **Gates** (resultado em 2026-11-16): `docker compose run --rm test` (plataforma, 135 exemplos),
  `docker compose run --rm broker-test` (14) e `docker compose run --rm mock-agent-test` (12). Zero falhas.
- **Fumaça com a pilha no ar** (`docker compose exec api bundle exec rails <tarefa>`): `smoke:round_trip`,
  `smoke:escalation`, `smoke:routing` e `smoke:agent_silence` (pare o `mock-agent` antes).
- Um arquivo só: `docker compose run --rm test bundle exec rspec caminho/do_spec.rb`
- Lint da plataforma: `docker compose run --rm test bundle exec rubocop`
- Gate do frontend: ainda não existe (não há frontend).

## O que existe no código

Caminho de uma mensagem (ADR 0003):
`canal → api → outbox → relay → webhook → broker → Kafka → mock-agent → Kafka → broker-replies → api`

- `backend/` (Rails 8.1 API, Ruby 3.4, Postgres 17; **não fala com o Kafka**):
  - Ingestão com HMAC e dedupe; na abertura, `Rules::Router` aplica prioridade, tags e fila prevista.
  - `POST /api/agent/replies` (bot): `reply` e `escalate`, idempotente pelo `agent_turn_id`.
  - Handoff: máquina de estados com `handoff_epoch`; `Handoff::Escalate` reavalia as regras com fatos de
    escalação (fila da regra, senão prevista, senão padrão); brief por template; vigia do agente mudo.
  - Analista (token `analyst`): `work/next` pelo prazo mais próximo, ver, assumir, responder, fechar.
  - Operação (token `ops`): `/api/ops/teams`, `/api/ops/queues`, `/api/ops/brands/:brand/rule_sets`,
    `/api/ops/rule_sets/:id` (+ `publish`, `dry_run`). Erros de regra vêm com caminho.
  - Motor de regras em `app/services/rules/`: catálogo de fatos, avaliador puro, validador, fatos, roteador,
    dry-run. Toda decisão vai para `decisions` (versão, regra, fatos sem o texto, resultado).
  - Tabelas: marcas, usuários, equipes e membros, filas, níveis de prioridade, clientes, tickets, mensagens,
    entrada de webhooks, linha do tempo, decisões, conjuntos de regras, outbox, eventos processados.
- `broker/` (Ruby puro, sem banco): webhook → Kafka e Kafka → API. Dono dos tópicos da borda do agente.
- `mock_agent/` (Ruby puro): responde ou escala (30%, `MOCK_ESCALATION_RATE`), determinístico pelo
  `event_id`; `[escalar]` e `[responder]` no texto forçam a decisão.
- Seeds de desenvolvimento: equipes Atendimento InfinitePay, Atendimento JIM, Crédito e Dispositivo; filas
  padrão, de crédito e de maquininha; regras v1 publicadas nas duas marcas; analistas Ana, Bruno e Carla
  (`dev-analyst-<nome>`) e operação Olivia (`dev-ops-olivia`). Seeds não sobrescrevem o que já existe.
- Ainda **não** existem: gatilhos por fatos de LLM (cliente pediu humano, frustração), modo caos do mock,
  retry topics e DLQ, verificador de invariantes, envio da resposta ao canal, ActionCable, frontend, RLS,
  LLM, observabilidade.

## Verdades vigentes

- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers. Gems e cache de boot em volumes.
- Tópicos do Kafka são criados de forma explícita (`auto.create.topics` desligado).
- Segredos e tokens do Compose são padrões de desenvolvimento (`.env.example`), só para dados sintéticos.
- O banco de teste fica vazio: seeds não rodam em teste e a suíte limpa o banco ao começar. Por isso
  migrações são testadas também contra o banco de desenvolvimento, que tem dados.

## Estado do repositório

- Branches empilhadas: `docs/project-playbook` → `chore/platform-foundation` → `feat/agent-integration` →
  `feat/handoff-escalation` → `feat/rules-and-queues` (esta com a fatia 04 **sem commit**).
- Só `docs/project-playbook` está no remoto. Nenhum PR aberto (a CLI `gh` não está autenticada).

## Próximos passos

1. Commit da fatia 04.
2. PRs das cinco branches, com revisão independente em outro chat.
3. Fatia 05: resiliência e verificação (retry topics e DLQ no broker, modo caos do mock, verificador de
   invariantes), base do experimento.

## Pendências do dono

- Confirmar R2 a R5 do ADR 0005 (regras em dois momentos, lista de fatos, versão como documento único,
  auditoria sem o texto) e os contratos das fatias 02 a 04.
- Confirmar as marcas `[escalar]`/`[responder]` do mock e as escolhas da fatia 01.
- Desenho do enriquecimento por LLM agora que a plataforma não usa Kafka (ADR 0003, consequência de E1).
- O dia 27 inclui a apresentação? Agrupar em cerca de 5 PRs? Linguagem da análise (Python assumido).
- Definição do cluster do mapa vivo, limites de alerta e biblioteca do grafo.

## Bloqueios e riscos

- Prazo curto para o escopo escolhido; ordem de corte no playbook (§10), aplicada só com OK do dono.
- **Latência em desenvolvimento não vale como medida** (~0,45 s por chamada fora do controller, recarga de
  código sobre o disco do Windows). O experimento precisa rodar em modo de produção.
- O relay entrega um webhook por vez (mantém a ordem, limita a vazão). Medir no piloto de carga.
- Poison message ainda trava a partição do consumidor de respostas: falta retry topics e DLQ.
- As respostas do bot e do analista são gravadas, mas ainda não chegam ao canal nem a uma tela.
- Ninguém é avisado quando o prazo de SLA humano estoura; só fica registrado na primeira resposta.
- A extração de valor por expressão regular é limitada (não entende "cinco mil reais").
- Não testado: máquina sem cache de imagens Docker, macOS e Linux.
- Desenho da arquitetura atual da CloudWalk ainda não recebido; os contratos são nossos.
