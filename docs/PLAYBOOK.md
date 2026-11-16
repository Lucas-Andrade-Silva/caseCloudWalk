# Playbook do projeto: help desk AI-first da CloudWalk

Manual de operação para qualquer sessão (Codex, Claude ou outro agente). Responde a: o que estamos
construindo, como, com quais regras e o que fazer quando algo dá errado.

- O **porquê** e as alternativas descartadas estão em `docs/decisions/0002-arquitetura-stack-e-escopo.md` e
  em `docs/decisions/0003-integracao-com-o-agente.md` (este corrige a ordem da integração com o agente) e
  em `docs/decisions/0004-handoff-prioridade-e-atribuicao.md` (escalação, prioridades e atribuição).
- O **estado mutável** (onde estamos hoje) está em `docs/context/STATE.md`.
- A pesquisa de origem está em `docs/research/2026-11-08-ideacao-arquitetura.md` (consulta, não leitura obrigatória).
- Se este arquivo, o ADR, o `STATE.md` e o código divergirem: **pare e relate o conflito** ao dono.

---

## 0. Resumo de bolso (leia sempre)

**O que é.** Plataforma de help desk própria, AI-first, multi equipes e multi marcas (InfinitePay BR e
JIM US) para a CloudWalk. Canais simulados (app, WhatsApp, e-mail) entram, são triados em filas
configuráveis, vão a um agente de IA **simulado** por webhook → broker → Kafka, e escalam para analistas
humanos com resumo e contexto. Tudo auditado. Um experimento técnico prova robustez e escala.

**Prazo.** Entrega até **2026-11-27**. Projeto individual, feito com IA em TDD. Dados só sintéticos.

**Regras inegociáveis**

1. **TDD:** nenhum código de produção sem um teste vermelho antes (§1.2).
2. **Decisões passam pelo dono primeiro.** Tudo que não esteja registrado, ou que contradiga o
   registrado, exige parar e perguntar com opções, recomendação e custo (§1.4).
3. **Nunca enfraquecer, apagar ou pular teste para fazê-lo passar** (§1.3).
4. **Honestidade:** relatar falhas com a saída real do comando. Nunca dizer que algo passou sem ter rodado.
5. **Só dados sintéticos.** Sem segredos no repositório. PII redigida antes de qualquer chamada de LLM.
6. **Git:** nunca na `main`; branch focada; PR; revisão independente em outro chat; commit e push só
   quando o dono pedir (§1.6).
7. **LLM nunca no caminho crítico.** Sem LLM real em testes automatizados nem em teste de carga.
8. **Postgres é a verdade.** Sem escrita dupla. Entrega at-least-once + efeitos idempotentes.
9. **Tudo roda em containers.** Não existe Ruby local no Windows do dono.
10. **Responder em português**, de forma explicativa, clara, objetiva e **sincera** (inclui dizer que
    algo é arriscado, que o prazo não cabe ou que o dono está errado).

**Decisões em uma linha** (detalhe e porquê no ADR 0002)

| Tema | Escolha |
|---|---|
| Núcleo | Postgres + outbox transacional + Kafka na borda do agente + linha do tempo de eventos |
| Stack | Rails (API) + React (Vite), em Docker Compose |
| Mensageria/jobs | Apache Kafka (KRaft, 1 nó) + Karafka; Sidekiq/Redis só para jobs |
| Regras de fila | JSON próprio, ordenado por marca, primeira que bate vence, versionado, com dry-run |
| Operação | IA no primeiro nível; humano por escalação (3 gatilhos); sem devolução à IA na v1 |
| Integração | Plataforma → webhook assinado → broker (nosso, sem estado) → Kafka → agente; volta pelo inverso (ADR 0003) |
| Mock do agente | Determinístico com modo caos, em Ruby |
| LLM | Groq; adaptador com modos stub, replay e live; fatos de LLM nas regras, atrás de chave |
| Multi-marca | `brand_id` em tudo + escopo na aplicação + RLS nas tabelas centrais |
| Memória | Histórico estruturado + resumos de encerramento (expiram, excluíveis) |
| Extras | Regras em linguagem natural, estimativa honesta de espera, **mapa vivo** estilo Obsidian |
| Experimento | Carga + falhas + invariantes verificados (1× = 20 mil tickets/dia) |
| Observabilidade | OpenTelemetry + Prometheus + Grafana (+ Jaeger), amostragem baixa em carga |

---

## 1. Como trabalhar

### 1.1 Início de sessão

1. Leia este §0 e `docs/context/STATE.md`.
2. Rode `git status` e confira a branch. Nunca escreva na `main`.
3. Descubra o ponto do plano (§10) e a fatia em andamento.
4. Rode a suíte de testes para conhecer o ponto de partida. Código e saída de comando valem mais que prosa.
5. Leia as seções deste arquivo que a tarefa exige. Não pré-carregue histórico.

### 1.2 TDD (obrigatório)

**Ciclo:** vermelho (escreva o teste, rode e **veja falhar pelo motivo certo**) → verde (menor código que
passa) → refatorar (com a suíte verde). Ao corrigir bug, primeiro um teste que reproduz o bug.

**Camadas de teste e o que cada uma cobre**

| Camada | Exemplos obrigatórios |
|---|---|
| Unitário | Avaliador de regras (tabela de casos); transições da máquina de estados; cálculo de prioridade/SLA; estimativa de espera; redação de PII |
| Contrato | JSON Schema das mensagens Kafka e dos payloads de webhook; schema das regras; schema das saídas de LLM |
| Integração (Postgres e Kafka reais em Docker) | Atomicidade do outbox; relay publica em ordem de `id`; reentrega não duplica efeito; DLQ recebe poison message |
| Concorrência/idempotência | Duas atribuições simultâneas: uma vence; o mesmo evento processado N vezes dá o mesmo estado; webhook duplicado cria um ticket |
| Isolamento | Consulta sem contexto de marca devolve zero linhas; ler dados de outra marca falha |
| Adaptador de LLM | Stub e replay; saída inválida, timeout e erro caem para regras; o payload ao provedor não contém CPF nem cartão |
| Mock caos | Cada modo produz o comportamento configurado, determinístico por seed |
| Verificador de invariantes | Detecta perda e duplicata plantadas num ledger sintético; passa num ledger limpo |
| Frontend | Lógica do mapa como funções puras (eventos → estado, clusters, batching); componentes com Testing Library. Não testar pixels de canvas |
| Smoke E2E | `docker compose up`; uma mensagem entra, o mock responde, aparece na linha do tempo |

**Regras dos testes**

- Núcleo **offline e determinístico**: sem rede, sem relógio solto, sem aleatoriedade sem seed.
- **O teste é a especificação.** Mudar o que um teste espera é uma decisão: pergunte ao dono (§1.4).
- Dependência ou fixture externa só quando houver necessidade demonstrada.
- Testes de carga (k6) têm limiares como asserções, mas não seguem TDD estrito.
- O comando oficial do gate (backend, frontend, tudo) é definido no scaffold e **registrado no `STATE.md`**.
  Até lá, não invente comando: descubra e confirme.

### 1.3 Quando algo falha

**Protocolo:** reproduzir → ler a mensagem inteira → diagnosticar a causa raiz (skill
`systematic-debugging`) → menor correção na camada responsável → teste de regressão → suíte completa →
relatar o que foi rodado e o resultado.

**Proibido**

- Apagar, comentar, afrouxar, marcar como esperado-falha ou pular teste para passar.
- Aumentar timeout ou adicionar retry para esconder condição de corrida.
- Silenciar erro, capturar exceção sem tratar ou desligar a RLS para "destravar".
- Declarar sucesso sem ter rodado.

**Teste instável (flaky):** investigue a causa (ordem, relógio, estado compartilhado). Quarentena só com
aprovação do dono.

**Falha de infraestrutura** (Kafka fora, Docker parado, porta ocupada): diagnostique e corrija; registre a
causa. Docker Desktop precisa estar iniciado.

**Limite de tentativas:** se **três hipóteses seguidas** falharem, pare e reporte ao dono o que foi testado,
o que se sabe e as opções. Não gire em círculos.

**Bloqueio externo** (limite do Groq, rede): use o modo replay/stub e relate o impacto.

**Pressão de tempo:** proponha corte seguindo §10, com evidência, e **espere o OK do dono**. Não corte sozinho.

### 1.4 Decisões

**Pode decidir sozinho** (dentro dos contratos já registrados): nomes internos, organização de arquivos,
refatoração com testes verdes, testes adicionais, detalhes de implementação sem efeito em contrato ou escopo.

**Deve perguntar antes**

- Qualquer escolha de arquitetura, contrato (API, tópico, schema), modelo de dados ou escopo não registrada.
- Mudar ou contradizer uma decisão do ADR 0002, ou mudar o que um teste espera.
- Adicionar dependência relevante (registrar em ADR), trocar provedor ou modelo de LLM.
- Cortar escopo, atrasar entrega, pular uma regra de processo.
- Qualquer ação externa ou irreversível.
- Em dúvida: perguntar.

**Formato da pergunta:** contexto em 2 linhas, 2 a 3 opções com custo e risco, **uma recomendação** e o que
o dono perde com ela. Depois de decidido, atualize o ADR (ou crie um novo) e o `STATE.md`.

### 1.5 Comunicação

Português. Explicativo, mas direto. Sincero: aponte riscos, prazos que não cabem e o que não foi
verificado. Sem bajulação. Sem anunciar resultado que não foi medido. Quando citar números de
terceiros, diga que são de terceiros.

### 1.6 Git e PR

- Branch focada: `feat/`, `fix/`, `refactor/`, `docs/`, `test/` ou `chore/` + kebab-case.
- Commits convencionais, pequenos e revisáveis. Só arquivos da tarefa. **Commit e push só quando o dono pedir**
  (skill `$ship-change`).
- Todo conteúdo chega à `main` por PR. O chat autor **não** aprova o próprio PR: use `$review-pr` em outro
  chat. Merge só com checks passando e veredito `APPROVE`.
- Proposta (não confirmada): agrupar em cerca de **5 PRs** (um por bloco do §10) para caber no prazo,
  mantendo a revisão independente.
- Nunca force-push, nunca pular hooks ou checks, nunca commitar segredos.

### 1.7 Fim de sessão

1. Suíte rodada e resultado relatado.
2. `git diff` revisado (escopo, segredos, ruído gerado).
3. `STATE.md` atualizado se algo material mudou (substitua o obsoleto; sem diário).
4. Decisões novas registradas no ADR.
5. Relatório: comandos rodados, resultados, riscos residuais, o que **não** foi verificado.

---

## 2. Escopo

### 2.1 O que o TAPI pede

Plataforma funcional com: (1) recebimento de chat, WhatsApp e e-mail **simulados**; (2) múltiplas filas
configuráveis e editáveis pela operação (marca, equipe, categoria, prioridade); (3) interface de conversa
cliente ↔ atendente; (4) painel do analista com fila de escalas, contexto e histórico; (5) integração com o
atendente por webhooks e broker, como a atual; (6) triagem, priorização e distribuição entre IA e analistas;
(7) handoff com resumo e contexto; (8) rastreabilidade e auditoria; (9) memória e contexto entre interações.
Mais: agente simulado, **experimento técnico** (hipótese, método, limitações), dados sintéticos e README.

**O que a banca pesa:** aderência ao desenho de referência; filas de fato configuráveis; robustez diante de
falhas, reentregas e picos; handoff que preserva resumo e contexto; evidência de escala; clareza e
honestidade do experimento; reprodutibilidade e documentação; qualidade da demo.

**Fora de escopo:** desenvolver o agente real, dados reais, integrações de produção, apps móveis.
Restrições: LGPD, nada de acesso a sistemas da CloudWalk, não tentar identificar clientes reais.

### 2.2 Fronteira agente × plataforma

| É da CloudWalk (simulado por nós) | É nosso (construímos) |
|---|---|
| Interpretar o pedido; consultar sistemas internos por tools; decidir responder, agir ou escalar | Canais simulados, ingestão, filas, triagem, prioridade, distribuição |
| Agir na plataforma como usuário humano (`bot`) | API para o agente, identidade e permissões do `bot` |
| Memória própria do agente | Painel do analista, handoff com brief, auditoria, memória do cliente |
| | Broker mínimo, Kafka, relay, consumidores, mock do agente, dados sintéticos, experimento |

**Zonas cinzentas e como as tratamos (confirmar no onboarding)**

- **Broker:** o TAPI o lista como parte da integração do estudante, não como mock. Tratado como **nosso**, mínimo.
- **Resumo do handoff:** o agente manda o **motivo**; a plataforma gera e valida o brief, com template de
  fallback. O handoff nunca depende do agente.
- **Memória:** a plataforma guarda e envia no payload; não replica a memória interna do agente.
- **Triagem × interpretação do agente:** são leituras independentes, com objetivos diferentes.
- A plataforma **não** acessa sistemas internos, não executa ação financeira e não decide o conteúdo da
  resposta. Só audita o que o agente diz que fez.

### 2.3 Perfis

Cliente final (lojista, por marca), agente de IA (usuário `bot`), analista humano, operação (edita filas).

### 2.4 Princípio de produto

A plataforma deve ser **super intuitiva**. O diferencial visual é o **mapa vivo** (§7).

---

## 3. Arquitetura

### 3.1 Fluxo (12 passos, ordem do ADR 0003)

1. Canal simulado → **Ingestão** (HMAC, dedupe por `(canal, provider_msg_id)`).
2. Uma transação grava `inbound_events`, mensagem, ticket, linha do tempo e **outbox**; só então responde 2xx.
3. **Motor de regras** lê os fatos, atribui fila, prioridade e tags, e registra a decisão.
4. **Relay** lê o outbox por `id` serial e entrega cada evento ao broker como **webhook assinado**.
5. **Broker** (sem estado) valida a assinatura e publica em `helpdesk.messages`; só então responde 2xx.
6. O agente (mock) consome e responde em `agent.replies` com `in_reply_to_seq`, `agent_turn_id` e `handoff_epoch`.
7. O **broker** consome `agent.replies` e chama a **API da plataforma como usuário `bot`**. A plataforma confere
   `processed_events` (pelo `agent_turn_id`), `seq` e `epoch`, e grava a resposta se válida.
8. A resposta sai pelo outbox para o adaptador do canal e chega ao cliente.
9. Caminho lateral do enriquecimento por LLM: **redesenhar na fatia de LLM** (o ADR 0003 tirou o Kafka da
   plataforma; perguntar ao dono).
10. Na escalação: `pending_human` → item de trabalho com dono → analista vê brief e histórico via ActionCable.
11. **Vigia de SLA** (Sidekiq) escala ticket silencioso ou sem dono.
12. Operação edita regras (versão nova, dry-run, publicação). Falhas seguem retry-1 → retry-2 → DLQ.

### 3.2 Entidades (núcleo)

`brands`, `teams`, `queues`, `users` (papéis: customer, analyst, ops, bot), `customers`,
`tickets` (ticket e conversa são a mesma entidade; `mode`: ai | pending_human | human | closed;
`handoff_epoch`; contador de `seq`; no máximo um aberto por cliente, marca e canal),
`messages` (`seq`, direção, `provider_msg_id`), `inbound_events` (UNIQUE `(channel, provider_message_id)`),
`outbox`, `processed_events`, `conversation_events` (append-only), `decisions` (auditoria),
`rule_sets` e `rules` (versões imutáveis), `customer_memories` (resumo, tickets de origem, `expires_at`).

**Registro de decisão (auditoria):** `decision_id, ticket_id, step, actor (rule|llm|human|agent), model,
model_version, prompt_version, params, input_hash, redacted_input_ref, output, confidence, latency_ms,
cost, fallback_used, overridden_by`. Guardar hash e referência redigida, nunca PII crua.

### 3.3 Kafka

Tópicos: `helpdesk.messages` (chave `ticket_id`, header `brand_id`), `agent.replies`,
`ticket.created`, `ticket.enriched`, `*.retry-1`, `*.retry-2`, `*.dlq` (nomes ajustáveis).
12 partições por padrão (parametrizável; partições ≥ réplicas de consumidor). Sem tópico por marca.
A DLQ tem listar, purgar e reprocessar.

### 3.4 Handoff como máquina de estados

`ai → pending_human → human → closed` (e `ai → closed`).
- Só um escritor por vez: o bot não escreve com `mode ≠ ai`; o humano só escreve após atribuição.
- Escalação só termina quando existe item de trabalho **com dono**. Um reconciliador alerta o contrário.
- Cada troca de dono incrementa `handoff_epoch`. Resposta do bot com `epoch` diferente ou `mode ≠ ai` é
  **descartada e auditada**. Resposta com `in_reply_to_seq` defasado é **entregue e sinalizada** como
  atrasada (ADR 0003).
- `seq` por conversa é atribuído sob lock de linha. Atribuição usa lock otimista
  (`UPDATE ... WHERE version = ? AND assignee IS NULL`; zero linhas = perdeu a disputa).
- Takeover do analista é um handoff pedido por ele, com atribuição imediata.
- A IA se identifica como IA. O bot só promete prazo que a fila real cumpre.

### 3.5 Padrões obrigatórios

- HMAC-SHA256 sobre `id.timestamp.body`, tolerância de 5 minutos, suporte a rotação de chave.
- 2xx só **depois** do insert durável. Idempotency key em toda API do agente (`agent_turn_id`).
- Outbox + inbox. Efeito e `processed_events` na mesma transação.
- Retry com limite e jitter. Retry topic quebra a ordem: estacione a conversa (marcar bloqueada e segurar as
  seguintes) ou use `seq`.
- Backpressure: concorrência limitada, circuit breaker no agente (aberto → fila humana), cota de consumo por
  marca. Meça **idade** da fila, não só tamanho.
- Prioridade: `peso da prioridade + envelhecimento (espera / alvo de SLA) + match de skill`, filtrada por
  presença e capacidade, **calculada no momento de puxar**.
- Níveis de prioridade: P1 urgente (5 min), P2 alta (15 min), P3 normal (1 h), P4 baixa (4 h), prazo da primeira
  resposta humana. O analista puxa o ticket de prazo mais próximo (ADR 0004).

### 3.6 Antipadrões proibidos

Escrita dupla; confiar que o "exactly-once" do Kafka cobre efeitos externos; ordenar por `created_at`;
poison message travando partição; DLQ sem dono; retry sem jitter; bot respondendo depois do humano;
PII ou segredo na auditoria e nos logs; transação longa ao lado de fila no Postgres; dedupe com TTL no
Redis; microserviços; "o LLM roteia tudo"; produtor idempotente tratado como consumidor idempotente.

### 3.7 Invariantes (verificados após cada rodada de carga)

1. **Zero perda:** todo `external_msg_id` chega a um estado terminal (respondido, escalado ou DLQ).
2. **Zero duplicata visível:** no máximo uma resposta por `(conversation_id, reply_seq)`.
3. **Ordem:** `seq` de saída monotônico por conversa.
4. **Sem órfãs:** nenhuma conversa fica sem dono por mais de T.

O gerador de carga grava um ledger JSONL do que enviou; um checker cruza com a auditoria quando o lag zera.

---

## 4. Motor de regras e filas

- Regras por marca, **ordenadas**, a primeira que bate vence. Condições em árvore JSON (`all`/`any`,
  `fact`, `op`, `value`). Ações: **só** fila, prioridade e tags.
- Fatos de lista fechada e tipada. Duros: marca, canal, idioma, recorrência, contatos em 24 h, palavras-chave,
  valor. Do LLM (`source=llm`, com confiança mínima por regra): categoria, frustração, múltiplos assuntos,
  urgência. De escalação: motivo, confiança do agente, tempo na fila da IA.
- Conjunto publicado é **imutável**. Mudar = nova versão. Cada decisão grava `rule_set_version` e
  `matched_rule_id`.
- **Dry-run:** aplica a versão candidata aos últimos N tickets e mostra o diff antes de publicar.
- Sem regra que altere entrada de outra regra, sem scripting livre, sem regra fixa em código por marca.
- Equipes e analistas podem atender mais de uma marca.
- **Regras em linguagem natural** (extra): o LLM gera o JSON, o schema valida, o dry-run mostra o diff, um
  humano aprova. Nunca publica sozinho.

## 5. LLM na plataforma

- **Onde:** triagem (categoria, idioma), frustração, resumo do handoff, resumo de encerramento (memória),
  regras em linguagem natural. **Não** decide fila nem prioridade: fornece fatos.
- **Adaptador único**, três modos: `stub` (testes e carga; latência e falha injetáveis), `replay`
  (respostas gravadas, versionadas no repositório; reprodutibilidade), `live` (Groq).
- Modelo e temperatura **fixos** e registrados (modelo, versão, configuração). Temperatura zero não garante
  determinismo em modelo hospedado: por isso o replay.
- Cache por `hash(entrada redigida + versão do prompt + modelo)`. Prompts em git (`prompts/<tarefa>/vN.yaml`).
- **Redação de PII antes de qualquer chamada:** regex + dígito verificador de CPF + Luhn. Falhou: bloqueia
  a chamada. Mesmo com dados sintéticos.
- Saída estruturada com schema; inválida, timeout ou erro → **fallback para regras**. Nada de retry em
  tempestade. Circuit breaker por dependência. Orçamento de tempo de ~1 a 2 s para o enriquecimento.
- O roteador usa o enriquecimento se chegar no orçamento; senão roteia só por regras e reroteia depois.
- Segurança: texto do cliente é **dado** entre delimitadores; o LLM de enriquecimento **não tem tools** e só
  devolve enums; ações irreversíveis exigem checagem de política e humano.
- Limites do Groq (terceiros, conferir no console): ~30 req/min e ~14.400/dia na maioria dos modelos, alguns
  15/min e 500/dia. Escolha modelo do tier alto. Gemini só se a avaliação exigir. OpenRouter gratuito não serve.
- **Dados sintéticos:** templates com variações por LLM; rótulos (categoria, prioridade, `should_escalate`)
  vêm do **gerador**, nunca do modelo avaliado. Avaliação mínima de 50 a 100 tickets (baixa prioridade):
  acerto de categoria, recall de escalação (o erro mais caro), fidelidade do resumo.
- **Memória:** histórico estruturado + resumos de encerramento que citam os tickets de origem, expiram
  (prazo configurável), podem ser excluídos e são **regenerados** do histórico.

## 6. Mock do agente

Determinístico, por seed. Mapeia o pedido a uma saída (responder, agir, escalar) com probabilidades
configuráveis (escalação em **30% e 60%**). Modo caos: latência (distribuição), resposta duplicada, fora de
ordem, JSON malformado, silêncio, queda, tool inventada, nunca escalar. Age como usuário `bot`, com
identidade e permissões próprias; consome via broker. Ollama só como modo opcional de demo, nunca medido.
**Limitação:** taxas e falhas são parâmetros nossos, não do agente real.

## 7. Mapa vivo (visualização estilo Obsidian)

Grafo em tempo real dos tickets abertos, com clusters e movimento fluido. Tickets entram e saem a todo
momento.

- **Nós:** tickets abertos. Cor = cluster (categoria + marca). Tamanho = prioridade. Anel = IA ou humano.
  Pulso = risco de SLA ou escalação.
- **Cluster v1:** por categoria (fato duro ou do LLM). Similaridade por embeddings é evolução.
- **Incidente:** cluster que cresce acima de X tickets em N minutos recebe destaque (X e N a definir).
- **Tempo real:** eventos de ticket (aberto, atualizado, fechado) por ActionCable, **agrupados a cada ~250 ms**;
  carga inicial por REST; saída por polling.
- **Desempenho:** teto de nós desenhados (~500) com sobra resumida em bolha "+N". O mapa **não** entra no
  caminho do teste de carga.
- **Física:** d3-force em canvas; biblioteca final proposta ao dono na construção (dependência).
- **Testes:** lógica em funções puras (reducer de eventos, clusterização, batching).
- **Em aberto (configurar com o dono):** definição final de cluster, cores, filtros, clique no nó, tratamento
  de tickets fechados (esmaecer), limites do alerta.

## 8. Observabilidade

OpenTelemetry com o contexto propagado nos headers do Kafka, Prometheus + Grafana para métricas
(RED nos serviços, USE nos recursos, lag do consumidor, idade da fila), um backend de traces (Jaeger).
**Amostragem de 1% a 10% nos testes de carga**; total nos funcionais. Declare nas limitações. Se o notebook
sufocar, o rastreamento completo é o primeiro a sair (ordem de corte).

## 9. Experimento principal

**Pergunta:** a plataforma mantém as garantias sob pico combinado com falhas?

**Hipótese (rascunho, escrever antes de rodar):** sob 10× a 50× o volume base com 30% de webhooks reenviados,
Kafka parado por 60 s e agente lento, a plataforma mantém os 4 invariantes (§3.7), com latência da
plataforma p99 < 1 s em 10× e lag recuperado em < 5 min. **Refutada** se houver perda, duplicata visível,
quebra de ordem ou conversa órfã.

**Carga:** 1× = 20.000 tickets/dia, ~8 mensagens por conversa, hora de pico 12% do dia, 3 a 4 eventos por
mensagem → ~0,7 ticket/s, ~5 msg/s, ~20 eventos/s. Picos 10× (~200/s) e 50× (~1.000/s) por 5 a 15 min.

**Cenários:** (S1) rampa 1×→10×→50×→1× com 1, 2 e 4 consumidores; (S2) Kafka parado por 60 s com `docker pause`
+ reentrega de webhooks de 1 a 5 vezes fora de ordem; (S3) agente lento ou falhando → escala em ≤ 40 s (limite de silêncio de 30 s, ADR 0004, H6);
(S4) poison message → DLQ sem travar a partição; (S5) consumidor cai a cada 30 s; (S6) noisy neighbor entre
marcas; (S7) timeout do stub de LLM → modo só-regras com roteamento correto por fatos duros.

**Método:** k6 com **taxa de chegada** (modelo aberto, evita coordinated omission); aquecimento descartado;
**3 rodadas** por cenário; percentis em histograma (HDR), nunca média; escalação em 30% e 60%; ledger +
auditoria + checker. **Piloto antes** para calibrar metas, registrando o que mudou e por quê. Configuração em
YAML, seeds fixas, hash dos dados. Resultado negativo bem medido também é resultado.

**Medir:** ACK do webhook; latência ponta a ponta **e** latência da plataforma (sem o tempo do agente);
vazão; lag em mensagens e segundos; taxa de DLQ; taxa de escalação; quebras de SLA por prioridade; tempo até
humano; DB pool, CPU, partições.

**Ponto de ruptura:** maior taxa de chegada sustentada com latência da plataforma na meta e lag limitado.
Reporte como múltiplo da referência.

**Armadilhas:** testar só a borda HTTP; ignorar lag e tempo de drenagem; gerador na mesma CPU sem limite;
chaves uniformes demais (use conversas tagarelas); rodada única; deixar o mapa no caminho da carga.

**Limitações a declarar:** um host, Kafka de 1 nó, dados sintéticos, mock de agente com latência injetada,
amostragem de trace baixa, runs curtos. Afirmar **resultados relativos**, nunca capacidade de produção.
Sem baseline de LLM: não afirmar que ele melhora o roteamento.

## 10. Plano (13 dias, proposto; datas e PRs aguardam confirmação)

| Dias | Foco | Gate (fim do bloco) |
|---|---|---|
| 15–16 | ADR e `STATE.md`; Docker Compose (Postgres, Redis, Kafka, Rails); teste do Karafka + outbox | Mensagem sai do Rails, passa pelo Kafka e volta. Se travar: **decisão do dono** sobre alternativa |
| 17–18 | Fatia ponta a ponta: ingestão, outbox, Kafka, mock, consumidor idempotente, linha do tempo, chat React + ActionCable | Demo ponta a ponta; teste de webhook duplicado verde |
| 19–20 | Handoff e gatilhos, painel do analista, editor de filas com versão e dry-run, multi-marca, DLQ, vigia de SLA | Conversa com agente mudo escala sozinha |
| 21 | Mock caos, verificador de invariantes, métricas | Verificador passa em carga pequena |
| 22 | LLM (stub + replay + Groq), enricher, resumo, memória, dados sintéticos | Todo uso de LLM tem fallback e teste |
| 23 | Mapa vivo | Mapa renderiza tickets entrando e saindo |
| 24 | Piloto de carga, calibração, correções | Metas calibradas e registradas |
| 25–26 | Experimento oficial, análise, README, roteiro de demo; **congelar funcionalidades** | Resultados, limitações e instalação limpa testada |
| 27 | Margem de entrega. Nada novo | Entregue |

**Ordem de corte** (proposta, **só aplicar com OK do dono**): 1) regras em linguagem natural; 2) estimativa
de espera; 3) rastreamento do OpenTelemetry (ficam as métricas); 4) RLS (ficam escopo na aplicação e teste
de isolamento); 5) avaliação mínima do LLM; 6) detector estatístico à parte (o mapa cobre o essencial);
7) dry-run, só se esgotado o resto. **Nunca cortar:** outbox e idempotência, handoff, editor de filas,
mock caos, verificador de invariantes, experimento principal, README e demo.

Simplificações já aceitas: Kafka parado via `docker pause`; sem Toxiproxy nem Pumba.

## 11. Ambiente

Windows 11, PowerShell como shell principal (Bash também disponível). Repo em
`C:\INTELI\inteliAcademy\caseCloudWalk`. Docker 29.7 instalado (**iniciar o Docker Desktop**). Node 24,
Python 3.11 e Git instalados. **Ruby não instalado**: Rails e Karafka rodam em containers (o `rdkafka`
compila no Linux). WSL tem só a distro do Docker. Gems e `node_modules` em volumes nomeados (bind mount do
disco do Windows é lento). Segredos em `.env` (ignorado; manter `.env.example`).

## 12. Entrega

- **README** com: problema e recorte; dados sintéticos; arquitetura; instalação e execução; modelos e
  configurações; metodologia experimental; resultados; limitações; possibilidades de evolução.
- Todo número mostrado tem fonte. Instalação testada numa máquina limpa (clone limpo + `docker compose up`).
- **Demo** de 5 a 7 minutos, com **plano B** (gravação e respostas salvas).
- Referências úteis: biblioteca da Liga (`https://inteliacademyclub.github.io/library/`), em especial o case
  TRACTIAN (agente auditável com escalação), as lições de agentes e MCP (o LLM orquestra, o sistema decide;
  contratos estritos) e Eval-Driven Development (sem mudança de prompt sem benchmark; hipótese escrita antes
  de rodar). Entregas de outros alunos são **referência, não template** (copiar só com requisito e análise
  de encaixe).

## 13. Pendências e onboarding

**Pendentes (perguntar ao dono antes de assumir):** o dia 27 inclui a apresentação? agrupar em ~5 PRs?
linguagem da análise (Python assumido); desenho do caminho de enriquecimento por LLM sem Kafka na
plataforma; definição do cluster e limites do mapa; biblioteca do grafo.

**Perguntas para a CloudWalk:** volume real por canal e marca e fator de pico; formato das mensagens no tópico
Kafka; como o agente sinaliza escalação; quem é dono do broker; residência de dados BR e US; taxa real de
escalação do agente; expectativa de triagem (plataforma ou agente); o desenho da arquitetura atual (ainda não
recebido).

## 14. Template de especificação de fatia (para prompts one-shot)

Cada fatia vira `docs/specs/NN-nome.md` e segue: **Objetivo** (1 frase) · **Decisões aplicáveis** (links ao
ADR) · **Contratos** (endpoints, schemas, tópicos) · **Testes de aceite** (escritos primeiro, em
dado/quando/então) · **Fora de escopo** · **Definição de pronto** (comandos e saída esperada) · **Riscos e
perguntas ao dono**.

One-shot funciona bem para estrutura (modelos, endpoints, telas, testes) e mal para integração (Kafka,
Docker, ActionCable). Reserve ciclos de correção; a fatia só está pronta quando seus testes passam.
