# Estado do projeto

Atualizado em: 2026-11-16

## Fase atual

Construção em andamento. Fatias 01 a 05 e o piloto de carga commitados localmente (piloto:
`docs/research/2026-11-16-piloto-de-carga.md`; API em 4 × 5; deadlock da ingestão corrigido).
Memória, interface, painel do analista e chat do cliente commitados. **Editor da operação (filas, equipes
e regras com simulação e publicação) pronto e verificado na pilha real, sem commit.** Entrega até **2026-11-27**.
Ordem combinada com o dono: piloto → memória sem LLM → interface → LLM → experimento oficial e README.

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002` (arquitetura e escopo), `0003` (integração com o agente, ticket único,
  resposta atrasada), `0004` (escalação, P1–P4, atribuição, `sidekiq-cron`, agente mudo: limite de 30 s e
  meta de ≤ 40 s), `0005` (equipes, regras em dois momentos, fatos, versões, auditoria), `0006` (memória)
  e `0007` (interface: escuro e denso, Tailwind + Radix, d3-force em canvas, cluster por tags).
- Especificações de fatia: `docs/specs/01` a `06`.
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`. Pesquisa de origem: `docs/research/`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build` (se só o código mudou, `docker compose up -d --force-recreate
  api` aplica migrações; reinicie `relay`, `sidekiq` e consumidores, que são processos longos).
- **Gates** (2026-11-16, zero falhas): `docker compose run --rm` + `test` (plataforma, 177), `broker-test`
  (21), `mock-agent-test` (20) e `web-test` (frontend: tipos, lint e 29 testes).
- **Interface:** `http://127.0.0.1:5173` (`localhost` cai em outro Node desta máquina, em `[::1]:5173`).
- **Fumaça com a pilha no ar** (`docker compose exec api bundle exec rails <tarefa>`): `smoke:round_trip`,
  `smoke:escalation`, `smoke:routing` e `smoke:agent_silence` (pare o `mock-agent` antes).
- **Rajada e invariantes:** `load:burst[n,taxa,reentrega,seed]` grava `tmp/ledgers/<run>.jsonl`;
  `invariants:check[ledger,espera_s]` espera esvaziar e confere (código 1 se violar).
- **Piloto em produção:** `API_PORT=3002 docker compose -p helpdesk-pilot -f compose.yaml -f compose.pilot.yaml
  up -d --build` (projeto e banco próprios; `WEB_CONCURRENCY` e `RAILS_MAX_THREADS` configuram a API).
- **Caos no mock:** `MOCK_CHAOS="latency_ms=200..2000,..." docker compose up -d --force-recreate mock-agent`.
- **Falhas:** `outbox:dead`, `outbox:retry_dead[id]`, `outbox:discard_dead[id]` (plataforma) e
  `docker compose exec broker bin/dlq list|replay|purge` (respostas do agente).

## O que existe no código

Caminho de uma mensagem (ADR 0003):
`canal → api → outbox → relay → webhook → broker → Kafka → mock-agent → Kafka → broker-replies → api`

- `backend/` (Rails 8.1 API, Ruby 3.4, Postgres 17; **não fala com o Kafka**):
  - Ingestão com HMAC e dedupe; na abertura, `Rules::Router` aplica prioridade, tags e fila prevista.
  - `POST /api/agent/replies` (bot): `reply` e `escalate`, idempotente pelo `agent_turn_id`.
  - Handoff: máquina de estados com `handoff_epoch`; `Handoff::Escalate` reavalia as regras com fatos de
    escalação (fila da regra, senão prevista, senão padrão); brief por template; vigia do agente mudo.
  - Analista (token `analyst`): `work/next` pelo prazo mais próximo, ver, assumir, responder, fechar (com
    `resolution_code` obrigatório e nota opcional).
  - Memória (ADR 0006): 5 últimos tickets do cliente na marca em 90 dias, com resumo de encerramento, no
    payload do agente e no `GET` do ticket; `DELETE /api/ops/brands/:b/customers/:id/memory` apaga (auditado).
  - Operação (token `ops`): `/api/ops/teams`, `/api/ops/queues`, `/api/ops/brands/:brand/rule_sets`,
    `/api/ops/rule_sets/:id` (+ `publish`, `dry_run`). Erros de regra vêm com caminho.
  - Motor de regras em `app/services/rules/`: catálogo de fatos, avaliador puro, validador, fatos, roteador,
    dry-run. Toda decisão vai para `decisions` (versão, regra, fatos sem o texto, resultado).
  - Resiliência: evento recusado de vez pelo broker fica estacionado e retém só o seu ticket; banco fora
    do ar responde 503; `Invariants::Checker` confere os quatro invariantes de um ledger.
- `broker/` (Ruby puro, sem banco): webhook → Kafka e Kafka → API, com `agent.replies.retry-1` (10 s),
  `retry-2` (60 s) e `dlq`. Plataforma fora (rede, 401/403/429/5xx de indisponibilidade) pausa sem gastar
  tentativa. Dono dos tópicos da borda do agente.
- `mock_agent/` (Ruby puro): responde ou escala (30%, `MOCK_ESCALATION_RATE`), determinístico pelo
  `event_id`; `[escalar]` e `[responder]` forçam a decisão; modo caos por `MOCK_CHAOS`.
- `frontend/` (React 19, Vite 8, TypeScript 6, Tailwind 4): entrada por token (`GET /api/me`), casca por
  papel e **painel do analista** (`GET /api/work`; pegar o próximo, conversa, brief, memória, responder,
  fechar com resolução), **chat do cliente** em `#/cliente`, sem login, via `/api/simulator` (só com
  `CHANNEL_SIMULATOR_ENABLED=true`, ADR 0007 I7–I9) e **operação** em `#/operacao` (filas, equipes,
  membros) e `#/operacao/regras` (construtor de um nível, I10). Dados por polling (sem ActionCable); o Vite
  vigia arquivos por polling (`VITE_USE_POLLING`), porque no Windows o container não recebe eventos.
- Seeds de dev: equipes, filas e regras v1; analistas Ana, Bruno, Carla (`dev-analyst-<nome>`), ops Olivia.
- Ainda **não** existem: LLM, canais reais, ActionCable, mapa vivo, RLS, k6 e observabilidade.

## Verdades vigentes

- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers. Gems e cache de boot em volumes.
- Tópicos do Kafka são criados de forma explícita (`auto.create.topics` desligado).
- Segredos e tokens do Compose são padrões de desenvolvimento (`.env.example`), só para dados sintéticos.
- O banco de teste fica vazio: seeds não rodam em teste e a suíte limpa o banco ao começar. Por isso
  migrações são testadas também contra o banco de desenvolvimento, que tem dados.

## Estado do repositório

- Branches empilhadas: `docs/project-playbook` → `chore/platform-foundation` → `feat/agent-integration` →
  `feat/handoff-escalation` → `feat/rules-and-queues` → `feat/resilience` → `test/production-pilot` →
  `feat/customer-memory` → `feat/frontend-foundation` → `feat/analyst-panel` → `feat/customer-chat` → `feat/ops-editor` (sem commit).
- Só `docs/project-playbook` está no remoto. Nenhum PR aberto (a CLI `gh` não está autenticada).

## Próximos passos

1. Commit do editor. Depois: mapa vivo (antes, o dono define sem tag e várias tags). Em seguida LLM,
   experimento oficial e README. Antes da demo: limpar os dados de desenvolvimento (ver riscos).
2. PRs das branches, com revisão independente em outro chat.

## Pendências do dono

- Confirmar R2 a R5 do ADR 0005 (regras em dois momentos, lista de fatos, versão como documento único,
  auditoria sem o texto) e os contratos das fatias 02 a 04.
- Confirmar: marcas `[escalar]`/`[responder]` do mock, fatia 01, proposta do ADR 0006 (payload; exclusão
  preserva tickets) e I5–I6 do ADR 0007 (TypeScript; frontend em container com proxy).
- Desenho do enriquecimento por LLM agora que a plataforma não usa Kafka (ADR 0003, consequência de E1).
- O dia 27 inclui a apresentação? Agrupar em cerca de 5 PRs? Linguagem da análise (Python assumido).
- Mapa vivo por tags: onde fica ticket sem tag e como desempatar várias tags; limites do alerta.

## Bloqueios e riscos

- Prazo curto para o escopo escolhido; ordem de corte no playbook (§10), aplicada só com OK do dono.
- **Latência em desenvolvimento não vale como medida**; o experimento roda em modo de produção.
- Ponta a ponta p99 em 10× ficou em 1.026 ms com a API em 4 × 5 e mock instantâneo (no limite da meta);
  com 1 × 3, o 10× degrada. 50× não testado.
- Depois de uma queda do Postgres, o vigia escala os tickets atrasados (decidido); medir a fila humana.
- Outros programas desta máquina ocupam `[::1]:3000` (wslrelay) e `[::1]:5173` (Node): use `127.0.0.1`.
- Banco de dev bagunçado para demo: equipes duplicadas (seeds sem filas × as da migração 0005, donas das
  filas padrão) e dezenas de tickets atrasados com a Ana (o `smoke:escalation` esvazia a fila dela).
- Ninguém é avisado quando o prazo de SLA humano estoura; só fica registrado na primeira resposta.
- A extração de valor por expressão regular é limitada (não entende "cinco mil reais").
- Não testado: máquina sem cache de imagens Docker, macOS e Linux.
- Desenho da arquitetura atual da CloudWalk ainda não recebido; os contratos são nossos.
