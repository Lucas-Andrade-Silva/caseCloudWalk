# Estado do projeto

Atualizado em: 2026-11-22

## Fase atual

Reta final (entrega **2026-11-27**). Na `main`: fatias 01 a 06, piloto de carga, todas as telas e o mapa vivo.
Commitadas e ainda fora da `main`: `feat/observability` e `feat/llm` (LLM verificada ao vivo no Groq em
2026-11-21, prompts v2). Em andamento: `feat/incident-mode-and-redesign` (ADR 0009), com o **redesign no visual
da CloudWalk** feito no frontend e ainda sem commit. O experimento é exigido pelo TAPI; corte só com OK do dono.

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002` (arquitetura e escopo), `0003` (integração com o agente, ticket único,
  resposta atrasada), `0004` (escalação, P1–P4, atribuição, `sidekiq-cron`, agente mudo: limite de 30 s e
  meta de ≤ 40 s), `0005` (equipes, regras em dois momentos, fatos, versões, auditoria), `0006` (memória),
  `0007` (interface; I12–I13: cluster por primeira tag, ActionCable com Redis), `0008` (observabilidade e LLM)
  e `0009` (Modo Incidente, "Por que a IA decidiu", resiliência ao vivo, visual CloudWalk, experimento enxuto).
- Contexto de produto e design: `PRODUCT.md` (raiz). Especificações de fatia: `docs/specs/01` a `06`.
- Piloto de carga: `docs/research/2026-11-16-piloto-de-carga.md`. Brief do parceiro: `docs/TAPI_cloudwalk.pdf`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build` (se só o código mudou, `docker compose up -d --force-recreate
  api` aplica migrações; recrie `relay`, `sidekiq` e consumidores, que são processos longos, e o `web` quando
  mudar o `vite.config.ts` ou o `package-lock.json`).
- **Gates** (`docker compose run --rm` + `test`, `broker-test`, `mock-agent-test`, `web-test`). Últimos
  resultados: plataforma 212, broker 25, mock 22 (2026-11-21); frontend 49 testes, tipos e lint limpos
  (2026-11-22, rodado com o Node local: `npm run gate` em `frontend/`).
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

- `backend/` (Rails 8.1 API, Ruby 3.4, Postgres 17; **não fala com o Kafka**): ingestão com HMAC e dedupe;
  regras na abertura; respostas do agente idempotentes; handoff com `handoff_epoch`; analista (fila, próximo,
  responder, fechar com resolução); memória (ADR 0006); operação (equipes, filas, regras versionadas com
  dry-run); mapa vivo (`GET /api/map` e `MapChannel`); resiliência (`Invariants::Checker`); observabilidade
  (trace W3C ponta a ponta, `/metrics`); LLM (enriquecimento, brief e resumo, com fallback; ADR 0008).
- `broker/` (Ruby puro): webhook → Kafka e Kafka → API, com retry-1 (10 s), retry-2 (60 s) e DLQ.
- `mock_agent/` (Ruby puro): responde ou escala (30%), determinístico; `[escalar]`/`[responder]`; modo caos.
- `frontend/` (React 19, Vite 8, TypeScript 6, Tailwind 4): entrada, painel do analista, chat do cliente,
  editor da operação e mapa vivo (d3-force em canvas). Visual CloudWalk: tokens em `src/index.css`,
  componentes únicos em `src/ui/`, fontes por `@fontsource`, ícones Lucide.
- Seeds de dev: equipes, filas e regras v1; analistas Ana, Bruno, Carla (`dev-analyst-<nome>`), ops Olivia.
- Ainda **não** existem: Modo Incidente, "Por que a IA decidiu", fechamento automático de tickets da IA,
  roteiro de resiliência, k6, RLS e canais reais.

## Verdades vigentes

- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Commits e PRs sem crédito ao Claude (pedido do dono). Em 2026-11-17 a `main` foi reescrita para tirar a
  coautoria (exceção pontual e autorizada ao "never force-push"); a cópia antiga está só na branch local
  `backup/main-antes-sem-coautoria`.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers. Node 24 local serve para o gate do
  frontend quando o Docker está fora (`frontend/node_modules` local é ignorado pelo Git).
- Dependências novas: versão publicada há 14 dias ou mais, inclusive as transitivas.
- Tópicos do Kafka são criados de forma explícita (`auto.create.topics` desligado).
- Segredos e tokens do Compose são padrões de desenvolvimento (`.env.example`), só para dados sintéticos.

## Estado do repositório

- Remoto: só a `main`. Local: `feat/observability` → `feat/llm` → `feat/incident-mode-and-redesign` (empilhadas)
  e o backup. A CLI `gh` não está autenticada: PRs saem pelo site, com links preparados.

## Próximos passos (ordem do ADR 0009)

1. Conferir o redesign com a pilha no ar (fila, operação e mapa com dados) e commitar.
2. Modo Incidente (TDD): entidade `Incident`, detecção 5 em 10 min, título e rascunho pela LLM, destaque no
   mapa, banner do analista, responder e fechar todos, botão de rajada no simulador.
3. "Por que a IA decidiu" por ticket. 4. Fechamento automático (30 min) e dados de demo limpos.
5. Roteiro de resiliência ao vivo e vídeo de reserva. 6. Experimento enxuto (k6, produção) e README.
7. Push e PRs: observabilidade → LLM → esta branch.

## Pendências do dono

- Pôr `LLM_MODE=live` no `.env` (hoje diz stub) e gravar o replay da demo com `LLM_RECORD=true`.
- Confirmar as cores das marcas InfinitePay e JIM (provisórias).
- RLS (ADR 0002, D10), regras em linguagem natural e estimativa de espera (D7): declarar como limitações?
- O dia 27 inclui a apresentação? Linguagem da análise do experimento (Python assumido).
- Confirmações antigas: R2 a R5 do ADR 0005, contratos das fatias 02 a 04, marcas do mock, ADR 0006 e I5–I6.

## Bloqueios e riscos

- **Docker Desktop cai sozinho** nesta máquina; às vezes só volta iniciado pelo dono.
- Latência em desenvolvimento não vale como medida; o experimento roda em modo de produção.
- 10×: ponta a ponta p99 de 1.026 ms com a API em 4 × 5 (no limite da meta); 50× não testado.
- Com WEB_CONCURRENCY > 1, os contadores RED do `/metrics` são de um processo só; as medidas do domínio não.
- O enriquecimento (~1 s no Groq) chega depois de escalações imediatas; aí a categoria não muda a fila.
- Banco de dev bagunçado para demo (equipes duplicadas, dezenas de tickets atrasados com a Ana).
- Ninguém é avisado quando o prazo de SLA humano estoura (o mapa e o Grafana mostram, sem alerta).
- Regex de valor é limitada ("cinco mil reais"); não testado em macOS e Linux; contratos da CloudWalk: nossos.
