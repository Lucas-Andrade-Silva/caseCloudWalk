# Estado do projeto

Atualizado em: 2026-11-17

## Fase atual

Construção em andamento. Na `main`: fatias 01 a 06, piloto de carga, todas as telas e o mapa vivo.
Observabilidade e LLM commitadas (`feat/observability`, `feat/llm`). **LLM verificada ao vivo no Groq em 2026-11-21**; correção
dos prompts para v2 (max_tokens) ainda sem commit (ADR 0008). Entrega até **2026-11-27**. Ordem decidida pelo dono em 2026-11-18: observabilidade → LLM
(ADR 0008, L1–L3) → experimento oficial → README e limpeza para a demo. O experimento é exigido pelo TAPI;
se o prazo apertar, corte só com OK do dono.

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002` (arquitetura e escopo), `0003` (integração com o agente, ticket único,
  resposta atrasada), `0004` (escalação, P1–P4, atribuição, `sidekiq-cron`, agente mudo: limite de 30 s e
  meta de ≤ 40 s), `0005` (equipes, regras em dois momentos, fatos, versões, auditoria), `0006` (memória)
  `0007` (interface; I12–I13: cluster por primeira tag, ActionCable com Redis) e `0008` (observabilidade e LLM).
- Especificações de fatia: `docs/specs/01` a `06`. Piloto de carga: `docs/research/2026-11-16-piloto-de-carga.md`.
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build` (se só o código mudou, `docker compose up -d --force-recreate
  api` aplica migrações; recrie `relay`, `sidekiq` e consumidores, que são processos longos, e o `web` quando
  mudar o `vite.config.ts`).
- **Gates** (2026-11-21, zero falhas): `docker compose run --rm` + `test` (plataforma, 212), `broker-test`
  (25), `mock-agent-test` (22) e `web-test` (frontend: tipos, lint e 46 testes).
- **Interface:** `http://127.0.0.1:5173` (`localhost` cai em outro Node desta máquina, em `[::1]:5173`).
- **Observabilidade:** `OTEL_TRACES_EXPORTER=otlp docker compose --profile obs up -d`; Grafana em `:3030`,
  Jaeger em `:16686` (API de consulta em `/api/v3`), Prometheus em `:9090`.
  Mapa vivo em `#/mapa`; cliente simulado em `#/cliente`.
- **Fumaça com a pilha no ar** (`docker compose exec api bundle exec rails <tarefa>`): `smoke:round_trip`,
  `smoke:escalation`, `smoke:routing` e `smoke:agent_silence` (pare o `mock-agent` antes).
- **Rajada e invariantes:** `load:burst[n,taxa,reentrega,seed]` grava `tmp/ledgers/<run>.jsonl`;
  `invariants:check[ledger,espera_s]` espera esvaziar e confere (código 1 se violar).
- **Piloto em produção:** `API_PORT=3002 docker compose -p helpdesk-pilot -f compose.yaml -f compose.pilot.yaml
  up -d --build` (projeto e banco próprios; API em 4 × 5 por padrão).
- **Caos no mock:** `MOCK_CHAOS="latency_ms=200..2000,..." docker compose up -d --force-recreate mock-agent`.
- **Falhas:** `outbox:dead`, `outbox:retry_dead[id]`, `outbox:discard_dead[id]` (plataforma) e
  `docker compose exec broker bin/dlq list|replay|purge` (respostas do agente).

## O que existe no código

Caminho de uma mensagem (ADR 0003):
`canal → api → outbox → relay → webhook → broker → Kafka → mock-agent → Kafka → broker-replies → api`

- `backend/` (Rails 8.1 API, Ruby 3.4, Postgres 17; **não fala com o Kafka**):
  - Ingestão com HMAC e dedupe; na abertura, `Rules::Router` aplica prioridade, tags e fila prevista.
  - `POST /api/agent/replies` (bot): `reply` e `escalate`, idempotente pelo `agent_turn_id`.
  - Handoff com `handoff_epoch`; `Handoff::Escalate` reavalia as regras; brief por template; vigia do agente.
  - Analista: `GET /api/work`, `work/next`, ver, assumir, responder, fechar com `resolution_code`.
  - Memória (ADR 0006): 5 últimos tickets do cliente na marca em 90 dias, com resumo de encerramento.
  - Operação: equipes, filas, membros, regras versionadas (rascunho, dry-run, publicação), catálogo de fatos.
  - **Mapa vivo:** `GET /api/map` (retrato) e `MapChannel` no `/cable`; o `Ticket` publica no canal da marca
    depois de cada commit (falha de Redis só gera aviso). Token no subprotocolo `helpdesk-token.<base64url>`.
  - Resiliência: evento recusado fica estacionado; banco fora responde 503; `Invariants::Checker`.
  - Observabilidade (ADR 0008): trace W3C viaja no outbox e segue por relay, broker, Kafka e agente até a
    resposta na API; `/metrics` com RED por rota e medidas do domínio lidas do banco a cada coleta.
- `broker/` (Ruby puro): webhook → Kafka e Kafka → API, com retry-1 (10 s), retry-2 (60 s) e DLQ.
- `mock_agent/` (Ruby puro): responde ou escala (30%), determinístico; `[escalar]`/`[responder]`; modo caos.
- `frontend/` (React 19, Vite 8, TypeScript 6, Tailwind 4): entrada, painel do analista, chat do cliente
  (`/api/simulator`, só com `CHANNEL_SIMULATOR_ENABLED=true`), editor da operação e **mapa vivo** (d3-force em
  canvas; eventos agrupados a cada 250 ms; sem conexão, polling de 5 s; teto de 500 nós). Painel e chat
  ainda atualizam por polling. O Vite vigia arquivos por polling (`VITE_USE_POLLING`, Windows).
- Seeds de dev: equipes, filas e regras v1; analistas Ana, Bruno, Carla (`dev-analyst-<nome>`), ops Olivia.
- Ainda **não** existem: canais reais, alerta de incidente no mapa, RLS e k6.

## Verdades vigentes

- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Commits e PRs sem crédito ao Claude (pedido do dono). Em 2026-11-17 a `main` foi reescrita para tirar a
  coautoria (exceção pontual e autorizada ao "never force-push"); a cópia antiga está só na branch local
  `backup/main-antes-sem-coautoria`.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers. Gems e cache de boot em volumes.
- Tópicos do Kafka são criados de forma explícita (`auto.create.topics` desligado).
- Segredos e tokens do Compose são padrões de desenvolvimento (`.env.example`), só para dados sintéticos.
- O banco de teste fica vazio; migrações são testadas também contra o banco de desenvolvimento.

## Estado do repositório

- Remoto: só a `main`. Local: `main`, `feat/observability` e `feat/llm` (commitadas; ajuste v2 sem commit) e o
  backup. A CLI `gh` não está autenticada: PRs saem pelo site, com links preparados.

## Próximos passos

1. Commit do ajuste dos prompts; push e PRs da observabilidade e da LLM (nessa ordem).
2. Dono: pôr `LLM_MODE=live` no `.env` (hoje diz stub; o teste passou o modo pela linha de comando). Gravar o
   replay da demo com `LLM_RECORD=true`. Groq ao vivo: ~0,6–1,2 s por chamada; ignorou tentativa de injeção.
3. Experimento oficial (k6 em modo de produção, cenários do playbook §9, análise) e README.
4. Antes da demo: limpar os dados de desenvolvimento e ensaiar.

## Pendências do dono

- Confirmar R2 a R5 do ADR 0005 (regras em dois momentos, lista de fatos, versão como documento único,
  auditoria sem o texto) e os contratos das fatias 02 a 04.
- Confirmar: marcas `[escalar]`/`[responder]` do mock, fatia 01, proposta do ADR 0006 (payload; exclusão
  preserva tickets) e I5–I6 do ADR 0007 (TypeScript; frontend em container com proxy).
- Desenho do enriquecimento por LLM agora que a plataforma não usa Kafka (ADR 0003, consequência de E1).
- O dia 27 inclui a apresentação? Linguagem da análise do experimento (Python assumido).
- Limites do alerta de incidente no mapa (grupo que cresce X tickets em N minutos).
- **Tickets resolvidos pela IA nunca fecham** (ninguém dispara `ai → closed`): acumulam no mapa e na memória.
  Precisa de regra (por exemplo, fechar após N minutos sem mensagem do cliente).

## Bloqueios e riscos

- **Latência em desenvolvimento não vale como medida** (o trace mostra ~1 s parado no início de cada
  requisição da API em dev); o experimento roda em modo de produção.
- 10×: ponta a ponta p99 de 1.026 ms com a API em 4 × 5 (no limite da meta); 50× não testado. Entraram
  depois do piloto e precisam ser medidos no experimento: publicação no mapa e traces (amostrar 1% a 10%).
- Com WEB_CONCURRENCY > 1, os contadores RED do `/metrics` são de um processo só; as medidas do domínio não.
- O enriquecimento (~1 s no Groq) chega depois de escalações imediatas do agente; aí a categoria não muda a
  fila (só se reroteia com a IA). Avaliar com o dono: reavaliar também na escalação quando o fato chegar.
- Depois de uma queda do Postgres, o vigia escala os tickets atrasados (decidido); medir a fila humana.
- Banco de dev bagunçado para demo: equipes duplicadas (seeds sem filas × as da migração 0005, donas das
  filas padrão) e dezenas de tickets atrasados com a Ana (o `smoke:escalation` esvazia a fila dela).
- Ninguém é avisado quando o prazo de SLA humano estoura (o mapa e o Grafana mostram, sem alerta).
- Regex de valor é limitada ("cinco mil reais"); não testado em macOS e Linux; contratos da CloudWalk: nossos.
