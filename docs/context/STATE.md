# Estado do projeto

Atualizado em: 2026-11-25

## Fase atual

Reta final (entrega **2026-11-27**). Tudo o que o ADR 0009 pediu está **commitado** na pilha de branches
`feat/observability` → `feat/llm` → `feat/incident-mode-and-redesign`:

- observabilidade e LLM;
- Modo Incidente e "Por que a IA decidiu";
- fechamento automático e reset de demo;
- tema claro com Painel;
- roteiro de resiliência e experimento oficial enxuto.

**Auditoria e refatoração de 2026-11-25** na branch `refactor/repo-audit`, a partir de `7cbe67a`. Relatório em
`docs/research/2026-11-25-auditoria-e-refatoracao.md`, com a matriz de conformidade do TAPI. A autenticação por
token virou o concern `TokenAuthentication`, o corpo JSON virou `JsonBody`, e o build de produção, que estava
quebrado por um `*/` num comentário do CSS, foi corrigido. O `web-test` agora também roda o `vite build`.


## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002` (arquitetura e escopo), `0003` (integração com o agente), `0004` (escalação,
  P1–P4, `sidekiq-cron`, agente mudo em ≤ 40 s), `0005` (equipes, regras, auditoria), `0006` (memória), `0007`
  (interface), `0008` (observabilidade e LLM) e `0009` (Modo Incidente, "Por que a IA decidiu", resiliência,
  fechamento automático, tema claro com Painel, experimento enxuto) e `0010` (home em cards, sem barra lateral,
  tema escuro; substitui o tema claro do W8) `0011` (detalhe do analista e do tempo de solução) e `0012` (mapa vivo em órbita, com zoom nos grupos).
- Produto e design: `PRODUCT.md`. Especificações de fatia: `docs/specs/01` a `06`.
- Pesquisa: piloto (`docs/research/2026-11-16-piloto-de-carga.md`) e experimento oficial
  (`docs/research/2026-11-23-experimento-oficial.md`, rodadas em `docs/research/experimento-2026-11-23/`).
- Roteiro da demo: `docs/demo/roteiro-resiliencia.md`. Brief do parceiro: `docs/TAPI_cloudwalk.pdf`.

## Comandos oficiais

- **Subir tudo:** `docker compose up -d --build`.
  - Se só o código mudou, `docker compose up -d --force-recreate api` aplica as migrações.
  - Recrie `relay`, `sidekiq` e os consumidores quando o código deles mudar.
  - Recrie o `web` quando mudar o `package-lock.json`.
- **Gates** (`docker compose run --rm <serviço>`), 2026-11-25 em `refactor/repo-audit`, zero falhas: `test` 253
  exemplos e rubocop limpo; `broker-test` 27; `mock-agent-test` 22; `web-test` 61 testes, tipos, lint e build.
  Com o Docker fora, rode `npm run gate` em `frontend/`. **Ponta a ponta:** `./scripts/e2e/run.ps1` (Playwright 1.65.0 + axe 4.14.0: 2 jornadas, axe WCAG 2.1 AA e teclado; 4 verdes com a LLM ao vivo).
- **Interface:** `http://127.0.0.1:5173` (nunca `localhost`): `#/inicio` (cards), `#/painel`, `#/fila`, `#/mapa`, `#/operacao`, `#/cliente`.
- **Observabilidade:** `OTEL_TRACES_EXPORTER=otlp docker compose --profile obs up -d`. Grafana em `:3030`,
  Jaeger em `:16686` e Prometheus em `:9090`.
- **Banco de demo:** `docker compose exec api bundle exec rails demo:reset`. Só em desenvolvimento; cria a
  cliente `demo-marina` com histórico.
- **Resiliência ao vivo:** `./scripts/demo/resiliencia.ps1 -Cenario kafka|agente` e `./scripts/demo/veneno.ps1` (S4).
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
- **`frontend/`** (React 19, Vite 8, Tailwind 4), em tema escuro com home em cards e "Voltar" (ADR 0010): Painel, fila com conversa e abas
  "Contexto" e "Por que a IA decidiu", banner de incidente, mapa vivo em órbita com zoom no grupo (ADR 0012), editor da operação e chat do cliente com
  "Simular pico". Clicar num analista abre `#/analista/:id`; os cards Tempo de solução, Desempenho do time e Operação dos
  tickets abrem `#/solucao`, `#/time` e `#/tickets` (ADR 0011).
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

Invariantes OK nas 9 rodadas; p99 a 10× de 1,18 a 1,25 s (meta de 1 s perdida por pouco); ruptura entre 10× e
~37×. Detalhe no README e em `docs/research/2026-11-23-experimento-oficial.md`.

## Próximos passos

1. Pendências do relatório de auditoria (`docs/research/2026-11-25-auditoria-e-refatoracao.md`): seção
   "Possibilidades de evolução" no README e registrar RLS, regras em linguagem natural e estimativa de espera como
   fora do escopo. Rodar `./scripts/e2e/run.ps1` com o `.env` (na pilha isolada, sem `.env`, passaram 2 de 4).
2. PRs em pilha até a `main`, com revisão independente (o chat autor não aprova o próprio PR).
3. Vídeo de reserva: `./scripts/demo/video.ps1` grava a jornada com legendas (2026-11-24). Dono: ensaiar a demo.
4. Conferir a tela da operação com dados no tema escuro.

## Pendências do dono

- `.env` está com `LLM_MODE=live` desde 2026-11-24. Resposta inválida (422) do agente vai para a DLQ (ADR 0009, W9).
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
- **API sem recarregar código (desde 2026-11-25):** o recarregamento custava ~1 s por chamada no disco do Windows. Depois de
  editar o backend: `docker compose restart api`. `RAILS_RELOAD=true` volta ao recarregamento.
- **Agente:** consumidor único; paralelizar antes de produção.
- **Métricas RED:** com `WEB_CONCURRENCY > 1`, as do `/metrics` são de um processo só.
- **Enriquecimento** chega depois de escalações imediatas (não muda a fila). **SLA humano** estourado não avisa ninguém.
- **Outros:** regex de valor limitada; não testado em macOS e Linux.
