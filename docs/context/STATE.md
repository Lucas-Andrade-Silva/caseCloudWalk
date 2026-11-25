# Estado do projeto

Atualizado em: 2026-11-23

## Fase atual

Reta final (entrega **2026-11-27**). Tudo o que o ADR 0009 pediu está **commitado** na pilha de branches
`feat/observability` → `feat/llm` → `feat/incident-mode-and-redesign`:

- observabilidade e LLM;
- Modo Incidente e "Por que a IA decidiu";
- fechamento automático e reset de demo;
- tema claro com Painel;
- roteiro de resiliência e experimento oficial enxuto.


## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002` (arquitetura e escopo), `0003` (integração com o agente), `0004` (escalação,
  P1–P4, `sidekiq-cron`, agente mudo em ≤ 40 s), `0005` (equipes, regras, auditoria), `0006` (memória), `0007`
  (interface), `0008` (observabilidade e LLM) e `0009` (Modo Incidente, "Por que a IA decidiu", resiliência,
  fechamento automático, tema claro com Painel, experimento enxuto).
- Produto e design: `PRODUCT.md`. Especificações de fatia: `docs/specs/01` a `06`.
- Pesquisa: piloto (`docs/research/2026-11-16-piloto-de-carga.md`) e experimento oficial
  (`docs/research/2026-11-23-experimento-oficial.md`, rodadas em `docs/research/experimento-2026-11-23/`).
- Roteiro da demo: `docs/demo/roteiro-resiliencia.md`. Brief do parceiro: `docs/TAPI_cloudwalk.pdf`.

## Comandos oficiais

- **Subir tudo:** `docker compose up -d --build`.
  - Se só o código mudou, `docker compose up -d --force-recreate api` aplica as migrações.
  - Recrie `relay`, `sidekiq` e os consumidores quando o código deles mudar.
  - Recrie o `web` quando mudar o `package-lock.json`.
- **Gates** (`docker compose run --rm <serviço>`), 2026-11-23, zero falhas:

  | Serviço | Resultado |
  |---|---|
  | `test` (plataforma) | 248 exemplos, rubocop limpo |
  | `broker-test` | 25 |
  | `mock-agent-test` | 22 |
  | `web-test` | 61 testes, tipos e lint |

  Com o Docker fora, rode `npm run gate` em `frontend/`. **Ponta a ponta:** `./scripts/e2e/run.ps1` (Playwright 1.65.0; 2 jornadas, verdes 2 vezes).
- **Interface:** `http://127.0.0.1:5173` (nunca `localhost`): `#/painel`, `#/fila`, `#/mapa`, `#/operacao`, `#/cliente`.
- **Observabilidade:** `OTEL_TRACES_EXPORTER=otlp docker compose --profile obs up -d`. Grafana em `:3030`,
  Jaeger em `:16686` e Prometheus em `:9090`.
- **Banco de demo:** `docker compose exec api bundle exec rails demo:reset`. Só em desenvolvimento; cria a
  cliente `demo-marina` com histórico.
- **Resiliência ao vivo:** `./scripts/demo/resiliencia.ps1 -Cenario kafka|agente`.
- **Experimento oficial:** `./scripts/experiment/run.ps1 -Cenarios S1,S2,S3 -Rodadas 3`.
  Pilha em modo de produção (`helpdesk-pilot`) com k6; para a de desenvolvimento e a religa; `-Curto` ensaia.
- **Rajada e invariantes:** `load:burst[n,taxa,reentrega,seed]` e `invariants:check[ledger,espera_s]`.
- **Fumaça e falhas:** `smoke:round_trip|escalation|routing|agent_silence`; `outbox:dead|retry_dead|discard_dead` e `broker bin/dlq`.

## O que existe no código

Caminho de uma mensagem (ADR 0003):
`canal → api → outbox → relay → webhook → broker → Kafka → mock-agent → Kafka → broker-replies → api`

- **`backend/`** (Rails 8.1, Postgres 17; não fala com o Kafka):
  - ingestão com HMAC e dedupe, regras versionadas e handoff com epoch;
  - analista, memória, operação e mapa vivo;
  - observabilidade e LLM com fallback;
  - **Modo Incidente** (`Incidents::Detect`, 5 em 10 min por marca e chave; responder a todos);
  - **cadeia de decisão** (`Tickets::Explain`);
  - **fechamento automático** (`Tickets::AutoClose`, `ai_resolved` após 30 min);
  - **Painel** (`Dashboard::Metrics`);
  - experimento (`Experiment::K6Ledger`, `Experiment::Report`).
- **`broker/`** e **`mock_agent/`** (Ruby puro): webhook ↔ Kafka com retries e DLQ; mock com caos.
- **`frontend/`** (React 19, Vite 8, Tailwind 4), em tema claro (W8): Painel, fila com conversa e abas
  "Contexto" e "Por que a IA decidiu", banner de incidente, mapa vivo, editor da operação e chat do cliente com
  "Simular pico".
- **Experimento:** `experiment/k6/webhooks.js`, `compose.experiment.yaml` e `scripts/experiment/run.ps1`.
- **Ainda não existem:** RLS, regras em linguagem natural, estimativa de espera e canais reais.

## Verdades vigentes

- Regra de ouro: TDD, e decisões novas passam pelo dono antes.
- Commits e PRs sem crédito ao Claude (pedido do dono). A cópia de antes da reescrita da `main` está na branch
  local `backup/main-antes-sem-coautoria`.
- Ambiente: Windows 11, **sem Ruby local**; tudo roda em containers.
- Dependências novas: versão publicada há 14 dias ou mais, inclusive as transitivas.
- Segredos e tokens do Compose são padrões de desenvolvimento, só para dados sintéticos.

## Resultados do experimento (2026-11-23)

- **Invariantes:** OK nas 9 rodadas (S1 rampa até 50×, S2 com o Kafka parado 60 s, S3 com o agente em caos).
- **10×:** ponta a ponta p99 de 1,18 a 1,25 s, então a meta de 1 s foi perdida por pouco.
- **Kafka:** o atraso esvaziou em 53 a 59 s depois de o Kafka voltar.
- **Ruptura:** entre 10× e cerca de 37× nesta máquina.
- **Agente lento:** de 0,2 a 2 s por mensagem, um consumidor só não acompanha 10×, e o vigia escala cerca de
  62%.

## Próximos passos

1. PRs em pilha até a `main`, com revisão independente (o chat autor não aprova o próprio PR).
2. Dono: gravar o vídeo de reserva do roteiro e ensaiar a demo (`docs/demo/roteiro-resiliencia.md`).
3. Conferir a tela da operação com dados no tema claro.

## Pendências do dono

- Pôr `LLM_MODE=live` no `.env` para a demo, ou gravar o replay com `LLM_RECORD=true`.
- Confirmar as cores das marcas InfinitePay e JIM (provisórias).
- RLS (ADR 0002, D10), regras em linguagem natural e estimativa de espera (D7): declarar como limitações?
- O dia 27 inclui a apresentação?
- Confirmações antigas: R2 a R5 do ADR 0005, contratos das fatias 02 a 04, ADR 0006 e I5–I6.

## Bloqueios e riscos

- **Docker Desktop cai e, depois, não abre:** ficam arquivos `.sock` presos em `%LOCALAPPDATA%\Docker\run` e
  `%LOCALAPPDATA%\docker-secrets-engine`.
  - Contorno: encerrar os processos, renomear as duas pastas e abrir de novo.
  - Nunca "Reset to factory defaults", que apaga os volumes.
- **Medidas:** latência em desenvolvimento não vale; só a do modo de produção.
- **Agente:** consumidor único; paralelizar antes de produção.
- **Métricas RED:** com `WEB_CONCURRENCY > 1`, as do `/metrics` são de um processo só.
- **Enriquecimento** chega depois de escalações imediatas (não muda a fila). **SLA humano** estourado não avisa ninguém.
- **Outros:** regex de valor limitada; não testado em macOS e Linux.
