# Auditoria e refatoração do repositório (2026-11-25)

Branch `refactor/repo-audit`, criada a partir de `7cbe67a`. Esse é o último commit de `feat/home-em-cards` antes
da home em cards. Com isso, a branch já traz o e2e, o axe e a DLQ do S4. O commit `2391d30` (home em cards) e o
trabalho não commitado dessa branch ficaram de fora de propósito: eles reescrevem boa parte do frontend
(Dashboard, `format.ts`, `api.ts`, mapa), e refatorar essas telas em paralelo geraria conflito. Por isso o
frontend recebeu só a correção de build e o gate novo.

## 1. O que mudou

| Tipo | Arquivo | O quê |
|---|---|---|
| Removido | `backend/app/jobs/application_job.rb` | Base do ActiveJob gerada pelo Rails e nunca usada. Os 7 jobs usam `Sidekiq::Job`, e nenhuma referência sobrou. |
| Consolidado | `backend/app/controllers/concerns/token_authentication.rb` (novo) | O bloco "lê o Bearer, acha o usuário, 401/403" estava copiado em 7 controladores (`Agent::Replies`, `Analyst`, `Dashboard`, `Incidents`, `Map`, `Me`, `Ops::Base`). Agora cada um declara só `authenticate_roles <papéis>, forbidden: "<mensagem>"` e usa `current_user`. As mensagens e os status são os mesmos de antes. |
| Consolidado | `backend/app/controllers/concerns/json_body.rb` (novo) | O `parse_json` tolerante (vazio, inválido ou não-objeto vira `{}`) estava em `Analyst`, `Incidents`, `Ops::Base` e `Simulator`. `Agent::Replies` e `Webhooks::Channels` mantêm o parse estrito (422), que é outro contrato. |
| Consolidado | `backend/app/channels/application_cable/connection.rb` | `PEOPLE` duplicava a lista de papéis da equipe; agora usa `TokenAuthentication::STAFF_ROLES`. |
| Corrigido | `frontend/src/index.css:24` | **O build de produção estava quebrado.** O comentário continha `bg-*/10`, e esse `*/` fecha o comentário no meio. O resto da linha virava CSS, e o Tailwind falhava com `CssSyntaxError: Missing opening (`. O `vite dev` tolerava o erro, e o gate não rodava o build. |
| Gate | `frontend/package.json` | O `gate` (e com ele o `web-test`) agora termina em `vite build`, então a regressão acima volta a ser pega. |
| Testes | `backend/spec/controllers/token_authentication_spec.rb`, `json_body_spec.rb` | Testes vermelhos antes dos dois concerns (TDD): 401 sem token e fora do formato Bearer, 403 com a mensagem da rota, `current_user` e os quatro casos do corpo JSON. |

Saldo: os 10 controladores e o canal perderam 107 linhas e ganharam 42; os dois concerns têm cerca de 45 linhas.

## 2. O que foi auditado e ficou como está (com motivo)

- **Exportações do frontend sem uso externo** (`Customer`, `TicketMode`, `Message`, `MemoryItem`, `FieldError`,
  `Tone`, `RuleSetStatus`, `CustomerMessage`, `FactType`, `Leaf`, `AdvancedRule`, `ButtonProps`,
  `conditionText`, `durationText`): todas são usadas dentro do próprio módulo, e quase todas são tipos. Tirar
  o `export` não remove código e mexeria em arquivos que `2391d30` reescreve. Nenhum módulo do frontend ficou
  sem importação (o único é `main.tsx`, o ponto de entrada).
- **Constantes Ruby "sem referência"**: controladores (ligados por `routes.rb`), classes de erro levantadas no
  próprio arquivo e ganchos de framework (`connect`, `subscribed`, `readonly?`). Não são código morto.
- **Jobs de resumo** (`BriefSummaryJob`, `ClosingSummaryJob`, `EnrichTicketJob`, `IncidentSummaryJob`): têm a
  mesma forma, mas cada um tem 5 linhas. Um job genérico parametrizado esconderia qual serviço roda e qual
  agendamento o chama. Ficaram assim (KISS).
- **Assinatura HMAC em dobro** (`backend/app/messaging/webhooks/signature.rb` e `broker/lib/broker/signature.rb`):
  é duplicação aceita. O broker é um deployable à parte, sem estado e em Ruby puro (ADR 0003). Uma gem
  compartilhada custaria mais que as 15 linhas, e os dois lados têm spec do mesmo formato `v1=<hex>`.
- **Arquivos grandes do frontend** (`Dashboard.tsx` com 383 linhas, `QueuesEditor.tsx` com 363, `RulesEditor.tsx`
  com 342, `MapCanvas.tsx` com 327): candidatos a quebrar em módulos, mas `2391d30` mexe em `Dashboard` e
  reescreve `MapCanvas`. Ficam para depois do merge da home (débito 3).
- **`broker/` e `mock_agent/`**: pequenos (o maior arquivo tem 100 linhas) e com uma responsabilidade por
  arquivo. Nada morto foi encontrado.

## 3. Conformidade com o TAPI (`docs/TAPI_cloudwalk.pdf`, §6 e §9)

| Requisito do TAPI | Estado | Evidência |
|---|---|---|
| Recebimento por chat, WhatsApp e e-mail simulados | OK | `Webhooks::ChannelsController` (HMAC + dedupe), `Api::SimulatorController`, chat `#/cliente`; e2e `01-atendimento` |
| Múltiplas filas configuráveis e editáveis pela operação (marca, equipe, categoria, prioridade) | OK | `Api::Ops::*`, regras versionadas com dry-run (ADR 0005), `#/operacao`; `ops_spec`, `RulesEditor.test` |
| Interface de conversa cliente ↔ atendente (IA ou analista) | OK | `CustomerChat`, `Conversation`; e2e `01-atendimento` |
| Painel do analista com fila de escalas, contexto e histórico | OK | `#/fila`, `ContextPanel`, memória do cliente; `analyst_work_spec` |
| Integração por webhooks e broker, como a atual | OK | `outbox → relay → webhook → broker → Kafka → mock-agent` e volta (ADR 0003); `broker-test`, `smoke:round_trip` |
| Triagem, priorização e distribuição IA × humano | OK | `Rules::Router`, P1–P4, 3 gatilhos de escalação e vigia de 40 s (ADR 0004) |
| Handoff com resumo e contexto, preservando o histórico | OK | `Handoff::Escalate`, brief por LLM com template de reserva |
| Rastreabilidade e auditoria | OK | `conversation_events` e `decisions` só de leitura, "Por que a IA decidiu" (`Tickets::Explain`), traces OTel |
| Memória e contexto entre interações | OK | resumos de encerramento, apagamento (`memory_erasure`) (ADR 0006) |
| Agente simulado (mock) | OK | `mock_agent/` determinístico com caos; `mock-agent-test` |
| Experimento com hipótese, método e limitações | OK | `docs/research/2026-11-23-experimento-oficial.md` (hipótese escrita antes, 9 rodadas, seção de limitações) |
| Dados sintéticos e LGPD | OK | seeds e `demo:reset` sintéticos; `Llm::Redactor` antes de toda chamada |
| Sustentar o volume de referência | Parcial | Invariantes OK até 50×, mas o p99 a 10× ficou em 1,18–1,25 s, acima da meta de 1 s. Declarado no README. |
| README: problema e recorte | Parcial | A introdução diz o recorte, mas não o problema (help desk de terceiros lento e sem prioridade). |
| README: arquitetura | Parcial | Há só o diagrama de uma linha; o detalhe está no PLAYBOOK §3 e nas ADRs, sem link a partir dessa seção. |
| README: instalação e execução | OK | "Como rodar" |
| README: modelos e configurações | Parcial | Os modos da LLM estão lá; o modelo e a versão de cada prompt (`backend/prompts/<tarefa>/vN.yaml`) não aparecem. |
| README: metodologia experimental | Parcial | Há link e resultados; a hipótese e o método não estão no README. |
| README: resultados e limitações | OK | "Robustez e experimento", "Limitações declaradas" |
| README: possibilidades de evolução | **Falta** | Não há essa seção. |

**Divergências entre o registrado e o código** (decisões do dono, não alteradas aqui):

1. **RLS** está na tabela do PLAYBOOK §0 ("RLS nas tabelas centrais", ADR 0002, D10), mas não existe. O README já
   a declara como limitação. A ADR ou o PLAYBOOK precisam dizer que foi adiada.
2. **Regras em linguagem natural** e **estimativa de espera** estão em "Extras" no §0 e não existem. Mesmo caso.

## 4. Comandos executados e resultados

Todos rodados no projeto Compose isolado `helpdesk-refactor`, para não tocar na pilha de desenvolvimento.

| Comando | Antes | Depois |
|---|---|---|
| `docker compose run --rm test` (RSpec da plataforma) | 248 exemplos, 0 falhas | **253 exemplos, 0 falhas** |
| `docker compose run --rm test bundle exec rubocop` | não rodado | **189 arquivos, 0 ofensas** |
| `docker compose run --rm broker-test` | 27 exemplos, 0 falhas | **27 exemplos, 0 falhas** |
| `docker compose run --rm mock-agent-test` | 22 exemplos, 0 falhas | **22 exemplos, 0 falhas** |
| `docker compose run --rm web-test` (tsc + eslint + vitest) | 61 testes, OK | **61 testes + `vite build`, OK** |
| `npm run build` (frontend) | **FALHA**: `CssSyntaxError: Missing opening (` | **OK** (`built in 3.12s`) |
| e2e Playwright (`compose --profile e2e run --rm e2e` após `demo:reset`) | **4 de 4 falham** | **2 passam, 2 falham** (ver §4.1) |

### 4.1 E2E

Rodado numa pilha isolada (`helpdesk-refactor`, sem portas publicadas e **sem `.env`**, ou seja, com os padrões
do Compose e `LLM_MODE=stub`). Para separar o efeito da mudança do efeito do ambiente, o mesmo roteiro rodou na
base `7cbe67a` e nesta branch:

| Teste | Base `7cbe67a` | `refactor/repo-audit` |
|---|---|---|
| `01-atendimento` (cliente → agente escala → analista responde e fecha) | falha | **falha**: a resposta da analista não aparece no chat da cliente em 30 s (`01-atendimento.spec.ts:39`) |
| `02-incidente` | falha | passa |
| `03` axe WCAG 2.1 AA | falha | passa |
| `03` jornada só pelo teclado | falha | **falha**: o ticket "Cliente teclado" não aparece em "Esperando nas suas filas" em 30 s (`03-acessibilidade.spec.ts:106`) |

Na base, a tela de entrada nem aparece (`getByLabel('Token de acesso')` não existe). É o mesmo CSS quebrado que
este PR corrige. Durante a rodada, a API não devolveu nenhum 4xx ou 5xx. As duas falhas que sobram dependem do
agente simulado escalar e do ticket chegar à fila a tempo. O `STATE.md` registra os 4 testes verdes na pilha do
dono, com `.env` e a LLM ao vivo. Esta sessão não usou o `.env` do dono, porque ele tem a chave do Groq.
**Não verificado:** `./scripts/e2e/run.ps1` na pilha de desenvolvimento com o `.env`. Esse é o passo que fecha
o e2e antes do merge.

## 5. Pendências e débitos técnicos

1. **README** (TAPI §6): falta "Possibilidades de evolução" e faltam o problema, a hipótese, o método e o modelo
   da LLM. Recomendação: o dono escreve uma seção curta de evolução (RLS, regras em linguagem natural,
   estimativa de espera, consumidores paralelos do agente, aviso de SLA) e põe a hipótese e o modelo com um
   link. Não foi escrito aqui porque é texto de entrega.
2. **RLS, regras em linguagem natural e estimativa de espera**: registrar na ADR 0002 ou no PLAYBOOK §0 que
   ficaram fora, para a documentação parar de prometer o que não existe.
3. **Modularizar o frontend** depois do merge de `feat/home-em-cards`: extrair os gráficos de `Dashboard.tsx`
   (`DailyBars`, `ChannelGauge`, `ReplyBuckets`) e os blocos de `QueuesEditor`/`RulesEditor`.
4. **Rubocop no `broker/` e no `mock_agent/`**: não está instalado (`bundle exec rubocop` falha). Só a
   plataforma tem análise estática de Ruby.
5. **`feat/home-em-cards`**: os commits `de9a0a6`..`2391d30` têm o mesmo build quebrado. A cópia não commitada
   já corrigiu o comentário. Vale confirmar com `npm run build` antes do PR dessa branch.
6. Riscos que já estavam no `STATE.md` e continuam: consumidor único do agente, métricas RED por processo, SLA
   humano sem aviso e Windows como única plataforma testada.
