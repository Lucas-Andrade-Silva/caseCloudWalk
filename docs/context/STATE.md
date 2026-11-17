# Estado do projeto

Atualizado em: 2026-11-17

## Fase atual

Construção em andamento. Tudo até o editor da operação está na `main` (fatias 01 a 06, piloto de carga e as
telas: entrada, painel do analista, chat do cliente e editor da operação). **Mapa vivo pronto e verificado
ao vivo na pilha real, sem commit**, na branch `feat/live-map`. Entrega até **2026-11-27**.
Ordem combinada com o dono: mapa vivo → LLM → experimento oficial → README e limpeza para a demo. Se o prazo
apertar, a LLM sai antes do experimento (que é exigido pelo TAPI); corte só com OK do dono.

## Onde está cada coisa

- Regras de trabalho, arquitetura, plano e protocolos: `docs/PLAYBOOK.md` (leia o §0 sempre).
- Decisões: `docs/decisions/0002` (arquitetura e escopo), `0003` (integração com o agente, ticket único,
  resposta atrasada), `0004` (escalação, P1–P4, atribuição, `sidekiq-cron`, agente mudo: limite de 30 s e
  meta de ≤ 40 s), `0005` (equipes, regras em dois momentos, fatos, versões, auditoria), `0006` (memória)
  e `0007` (interface; I12–I13: cluster por primeira tag, ActionCable com Redis).
- Especificações de fatia: `docs/specs/01` a `06`. Piloto de carga: `docs/research/2026-11-16-piloto-de-carga.md`.
- Brief do parceiro: `docs/TAPI_cloudwalk.pdf`.

## Comandos oficiais

- Subir tudo: `docker compose up -d --build` (se só o código mudou, `docker compose up -d --force-recreate
  api` aplica migrações; recrie `relay`, `sidekiq` e consumidores, que são processos longos, e o `web` quando
  mudar o `vite.config.ts`).
- **Gates** (2026-11-17, zero falhas): `docker compose run --rm` + `test` (plataforma, 186), `broker-test`
  (21), `mock-agent-test` (20) e `web-test` (frontend: tipos, lint e 45 testes).
- **Interface:** `http://127.0.0.1:5173` (`localhost` cai em outro Node desta máquina, em `[::1]:5173`).
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
- `broker/` (Ruby puro): webhook → Kafka e Kafka → API, com retry-1 (10 s), retry-2 (60 s) e DLQ.
- `mock_agent/` (Ruby puro): responde ou escala (30%), determinístico; `[escalar]`/`[responder]`; modo caos.
- `frontend/` (React 19, Vite 8, TypeScript 6, Tailwind 4): entrada, painel do analista, chat do cliente
  (`/api/simulator`, só com `CHANNEL_SIMULATOR_ENABLED=true`), editor da operação e **mapa vivo** (d3-force em
  canvas; eventos agrupados a cada 250 ms; sem conexão, polling de 5 s; teto de 500 nós). Painel e chat
  ainda atualizam por polling. O Vite vigia arquivos por polling (`VITE_USE_POLLING`, Windows).
- Seeds de dev: equipes, filas e regras v1; analistas Ana, Bruno, Carla (`dev-analyst-<nome>`), ops Olivia.
- Ainda **não** existem: LLM, canais reais, alerta de incidente no mapa, RLS, k6 e observabilidade.

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

- Remoto: só a `main`. Local: `main`, `feat/live-map` (mapa vivo, sem commit) e o backup acima.
- A CLI `gh` não está autenticada: PRs são abertos pelo site, com links preparados.

## Próximos passos

1. Commit e PR do mapa vivo.
2. LLM atrás de uma chave (enriquecimento, brief, resumos de memória).
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

- Prazo curto para o escopo escolhido; ordem de corte no playbook (§10), aplicada só com OK do dono.
- **Latência em desenvolvimento não vale como medida**; o experimento roda em modo de produção.
- Ponta a ponta p99 em 10× ficou em 1.026 ms com a API em 4 × 5 e mock instantâneo (no limite da meta);
  com 1 × 3, o 10× degrada. 50× não testado. A publicação no mapa (uma por commit de ticket) entrou depois
  do piloto: medir o custo no experimento.
- Depois de uma queda do Postgres, o vigia escala os tickets atrasados (decidido); medir a fila humana.
- Outros programas desta máquina ocupam `[::1]:3000` (wslrelay) e `[::1]:5173` (Node): use `127.0.0.1`.
- Banco de dev bagunçado para demo: equipes duplicadas (seeds sem filas × as da migração 0005, donas das
  filas padrão) e dezenas de tickets atrasados com a Ana (o `smoke:escalation` esvazia a fila dela).
- Ninguém é avisado quando o prazo de SLA humano estoura; o mapa mostra o risco, mas não notifica.
- A extração de valor por expressão regular é limitada (não entende "cinco mil reais").
- Não testado: máquina sem cache de imagens Docker, macOS e Linux.
- Desenho da arquitetura atual da CloudWalk ainda não recebido; os contratos são nossos.
