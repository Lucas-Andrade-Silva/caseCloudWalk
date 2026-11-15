# Ideação de arquitetura: help desk AI-first da CloudWalk

Data: 2026-11-08 · Fase: ideação (nenhuma decisão tomada) · Fonte do problema: `docs/TAPI_cloudwalk.pdf`

Este relatório junta o trabalho de cinco frentes de pesquisa que rodaram em paralelo:

1. arquitetura de backend;
2. fóruns (Reddit e Hacker News);
3. uso de LLM na plataforma;
4. testes de pressão e caos;
5. biblioteca da Liga.

Ele apresenta caminhos possíveis e não escolhe nenhum. A decisão final é sua.

---

## 1. O que o TAPI realmente cobra

A rubrica (seção 9 do TAPI) dá peso a seis pontos:

- **Coerência com a arquitetura de referência.** O agente de IA entra como atendente, pelo caminho webhook → broker → Kafka.
- **Filas que a operação configura sem precisar de desenvolvedor.**
- **Robustez diante de falhas, reentregas e picos.** O texto cita as três explicitamente.
- **Handoff que preserva o resumo e o contexto.**
- **Evidência de escala e um experimento honesto**, com hipótese, método e limitações.
- **Reprodutibilidade e qualidade da demo.**

Os números de carga que derivamos ficam baixos. Com "milhares por dia", meta de projeto de 20 mil tickets/dia, 12% do volume na hora de pico e cerca de 8 mensagens por conversa, chegamos a **~0,7 ticket/s, ~5 msg/s e ~20 eventos/s** já contando os webhooks de status. Um pico de 50x leva a cerca de 1.000 eventos/s. **Um Kafka num notebook aguenta isso com folga.** Os gargalos reais tendem a ser o banco, o handler de webhook e o agente mockado.

> **Conclusão-chave:** o desafio aqui é corretude sob falha (duplicata, ordem, handoff), não throughput. É nisso que o projeto pode se destacar.

O mesmo cálculo de Erlang C mostra outra coisa. Com 30% de escalação e 8 minutos de atendimento humano, o pico exige uns 100 analistas. **A taxa de escalação pesa muito mais no custo e no SLA do que o broker.** Isso dá uma narrativa forte para justificar o "AI-first".

---

## 2. Princípios que apareceram em todas as frentes

1. **Separar a decisão da redação.** A decisão (fila, prioridade, escalar sim ou não, ação permitida) sai como dado tipado, determinístico e auditável. O LLM só escreve texto e produz fatos que alimentam regras. Esse princípio apareceu ao mesmo tempo nos fóruns (um relato de que um ajuste de prompt "mais simpático" aumentou os reembolsos aprovados), na Anthropic e na lição 6.1 da Liga.
2. **O LLM nunca fica no caminho crítico.** Ingestão, persistência e atribuição funcionam sem LLM. Quando o LLM cai, o sistema passa para o "modo só regras", e isso pode virar uma feature da demo.
3. **"Exactly-once" de ponta a ponta não existe.** O que existe é entrega *at-least-once* somada a efeitos idempotentes (outbox na saída, inbox/dedupe na entrada). Dizer isso explicitamente no relatório conta pontos.
4. **O handoff é uma máquina de estados, não uma mensagem.** A falha mais relatada em produção é o "handoff fantasma": o bot diz "vou te transferir" e ninguém assume. A segunda mais relatada é bot e humano respondendo ao mesmo tempo.
5. **Toda decisão vira um evento auditável**, com quem decidiu (regra, LLM, humano ou agente), versão do modelo e do prompt, hash da entrada, confiança e fallback usado.

---

## 3. Arquiteturas candidatas

### A. Postgres como fonte da verdade, outbox transacional e Kafka na borda do agente

```
Canais (mock) ──HMAC──▶ Ingest API ──1 transação──▶ Postgres
                                         │  inbound_events (UNIQUE provider_msg_id)
                                         │  messages / tickets / outbox
                                         ▼
                              Relay do outbox ──▶ Kafka "helpdesk.messages" (key = conversation_id)
                                                           ▼
                                                 Broker ──▶ Agente IA (mock)
                                                           ▼
                              Consumer idempotente ◀── Kafka "agent.replies"
                                         ▼
                           Postgres (processed_events) ──▶ envio ao canal / painel do analista
```

- **Como funciona:**
  - O roteamento roda dentro da transação de ingestão, com regras versionadas guardadas em tabelas.
  - A ordem dentro de cada conversa vem da partição do Kafka.
  - O relay publica pelo `id` serial do outbox, e não por `created_at`.
  - Jobs internos (SLA, notificações) rodam em Sidekiq, Celery ou pgmq.
- **Por que dá certo:** é simples de entender e de testar, é o mais fiel ao desenho de referência, e a auditoria sai de graça (tabelas append-only). É viável para uma pessoa em um mês.
- **Por que pode dar errado:**
  - Escrita dupla sem outbox ("salva e depois publica").
  - Poison message travando uma partição.
  - Resposta atrasada do bot postando depois que o humano já assumiu.
  - Esses três riscos são justamente os alvos do experimento.
- **Inovação:** baixa por si só. Ela vem das camadas da seção 5.

### B. Conversa como log: Kafka como fonte da verdade (event sourcing / CQRS)

- **Como funciona:** todo comando e todo evento vai para o Kafka, e o Postgres guarda só projeções de leitura. A linha do tempo da conversa pode ser reproduzida ("time-travel").
- **Por que dá certo:** a auditoria e o replay são muito elegantes, e o modelo conversa bem com o seu estudo de Kafka.
- **Por que pode dar errado:**
  - Atribuir um ticket exige compare-and-set ("ainda está livre?"), o que é difícil sobre um log.
  - O painel deixa de ler as próprias escritas.
  - Evoluir o schema e reconstruir projeções dá trabalho.
  - O direito ao esquecimento da LGPD fica difícil num log imutável.
- **Veredito da pesquisa:** "Kafka como banco" é hype para este escopo. **Dá para capturar 80% do valor com um `conversation_events` append-only no Postgres dentro da opção A.**

### C. Workflow durável por conversa (Temporal ou Restate)

- **Como funciona:** cada conversa é um workflow (`workflow_id = conversation_id`), cada mensagem chega como um signal, e timers duráveis cuidam do SLA e do "espera a resposta do bot por N segundos; se não vier, escala".
- **Por que dá certo:** a lógica de SLA, timeout e handoff fica explícita e resistente a crash.
- **Por que pode dar errado:**
  - O histórico do workflow tem limite de 51.200 eventos ou 50 MB, o que obriga a usar Continue-As-New, e há pegadinhas com signals durante esse processo.
  - É um segundo sistema com estado para operar.
  - A curva de aprendizado é alta para um mês.
- **Veredito:** pode entrar como camada opcional sobre A. É arriscado como núcleo.

### D. Só Postgres (fila com `SKIP LOCKED` ou pgmq, sem Kafka)

- **Como funciona:** o banco faz o papel de fila.
- **Por que dá certo:** é o mais simples, e o volume de referência cabe nele. O processamento é exatamente uma vez dentro de cada transação.
- **Por que pode dar errado:**
  - **Foge da aderência ao desenho de referência**, que pede Kafka.
  - Há relatos de throughput desabando com mais de 128 workers.
  - Vacuum bloqueado por transações longas.
- **Veredito:** só faz sentido como fila interna. Na fronteira com o agente o Kafka continua sendo necessário.

### E. Actor por conversa (Elixir, Orleans, Akka)

- **Por que dá certo:** cada conversa tem um único escritor, então a ordem e o dedupe ficam triviais.
- **Por que pode dar errado:** stack nova, gerenciamento de cluster e risco alto.
- **Alternativa:** a mesma garantia sai de partição do Kafka por `conversation_id` mais lock de linha no Postgres.

### Comparativo

| | A. Outbox + Kafka na borda | B. Kafka como log | C. Workflow durável | D. Só Postgres |
|---|---|---|---|---|
| Aderência ao TAPI | Alta | Alta | Média | Baixa |
| Robustez demonstrável | Alta | Alta | Muito alta (timers) | Média |
| Auditoria e replay | Boa (tabela de eventos) | Excelente | Boa | Boa |
| Risco em 1 mês (solo) | Baixo/médio | Alto | Médio/alto | Baixo |
| Potencial de inovação | Depende das camadas | Alto | Médio | Baixo |

Variações híbridas que fazem sentido: **A + timeline de eventos (o melhor de B)** e **A + Temporal só para SLA e handoff (o melhor de C)**.

---

## 4. Padrões concretos e anti-padrões

**Faça:**

- **Na ingestão de webhook:**
  - Validar HMAC-SHA256 sobre `id.timestamp.body`, com tolerância de 5 minutos.
  - Responder 2xx só depois do insert durável.
  - Deduplicar por `(canal, provider_message_id)`.
- **Inbox e outbox** com uma tabela `processed_events` gravada na mesma transação do efeito. **Não use dedupe com TTL no Redis**: há relato de cobrança duplicada quando o lag passou do TTL.
- **Números de sequência por conversa.**
  - A resposta do agente carrega `in_reply_to_seq`.
  - A conversa carrega um `handoff_epoch` que muda a cada troca de dono.
  - Uma resposta velha ou chegada depois do handoff é descartada e auditada.
  - **Esse é o bug mais provável do projeto, então teste-o.**
- **Atribuição com lock otimista:** `UPDATE ... WHERE version=? AND assignee IS NULL`.
- **Agente como usuário:**
  - O agente é um `User` com papel `bot`, com presença, capacidade e skills, e passa pelo mesmo roteamento dos humanos. O Chatwoot funciona assim.
  - Ele age por um conjunto pequeno de ferramentas (`reply`, `tag`, `escalate(reason, brief)`).
  - Pode ser exposto por um **servidor MCP** com permissões por marca.
- **Retry e DLQ no padrão do Uber:** `retry-1` → `retry-2` → DLQ, com replay. Cuidado: mandar uma mensagem para retry quebra a ordem. A saída é bloquear a conversa ou se apoiar no `seq`.
- **Backpressure:** circuit breaker no agente. Quando ele cai, as conversas vão para a fila humana. Meça a **idade** da fila, não só o tamanho.
- **Multi-marca:** schema compartilhado com `brand_id` e RLS no Postgres. Uma célula por marca (BR com LGPD vs. US) fica como evolução.

**Evite:**

- Escrita dupla.
- Ordenar por `created_at`.
- DLQ que ninguém olha.
- Retry sem jitter.
- Microserviços: para quem desenvolve sozinho, um monólito modular com workers basta.
- Triggers que alteram as entradas de outras regras (o caos do Zendesk).
- Scripting livre nas regras.
- "O LLM roteia tudo".

### Motor de filas configurável (o requisito central da rubrica)

Três etapas separadas: **classificação → atribuição de fila → seleção de atendente.**

- **Regras:**
  - Lista ordenada por marca em que vale a primeira que bater.
  - As condições são escritas em uma linguagem restrita (CEL ou JSON-AST), sem possibilidade de loop, sobre fatos tipados do ticket.
  - As ações se limitam a fila, prioridade e tags.
- **Versões imutáveis:** cada decisão grava `rule_set_version` e `matched_rule_id`.
- **Simulação:** um endpoint de **dry-run sobre os últimos N tickets** mostra o diff antes de publicar. É barato e é a melhor prova de que as filas são realmente configuráveis.
- **Seleção de atendente:**
  - `score = peso da prioridade + envelhecimento do SLA (espera / alvo) + match de skill`.
  - Filtra por presença e capacidade.
  - É calculado na hora do pull, não com antecedência.

---

## 5. Camadas de inovação (para além de uma plataforma de filas)

Estas camadas se encaixam sobre qualquer uma das arquiteturas, de preferência a A. **V** = prática relatada em fóruns; **S** = hipótese própria que ainda precisa de eval.

1. **Timeline de conversa auditável com "por que o agente fez isso?"** (S, sustentada por V)
   - Toda mensagem, chamada de ferramenta, decisão, versão de prompt e ação humana vira um evento imutável.
   - Esse log serve de base para auditoria, depuração, replay e evals, e barateia as ideias 2, 3 e 7.
2. **Shadow mode e replay de versões do agente** (V)
   - Reproduz conversas reais do log contra um prompt ou modelo candidato.
   - Compara **decisões** (escalou? qual ação?), não o texto.
   - Um golden set de 20 a 100 casos funciona como gate de deploy.
3. **Handoff como máquina de estados com reconciliador** (V)
   - Os estados são `AI → pending_human → human`, com um único escritor por vez.
   - Um vigia escala automaticamente conversas silenciosas ou sem dono.
4. **Warm transfer brief** (V)
   - É um cartão estruturado, não a transcrição: objetivo, fatos confirmados, o que foi tentado, motivo da escalação, confiança e nível de frustração.
   - Um praticante relata que o analista se situa em cerca de 10 segundos.
5. **Escalação por sinais de frustração e loop, não só por baixa confiança** (V)
   - Gatilhos: pedido explícito de humano, reformulações repetidas, valores em dinheiro, palavras como "procon" ou "chargeback".
   - Um relato fala em CSAT subindo de cerca de 60% para 85%.
6. **Promessas honestas** (V)
   - O bot só promete o tempo que a fila real consegue cumprir, calculado pela profundidade e pelo SLA da fila.
   - Renomear a tool `connect_to_human` → `request_human_followup` zerou as promessas falsas.
7. **Detector de incidente pelos próprios tickets** (S)
   - EWMA ou z-score sobre a contagem por categoria em janelas de 5 minutos, mais clustering por embeddings.
   - Um pico de "Pix não caiu" agrupa automaticamente os tickets, avisa a operação e sobe a prioridade.
8. **Suporte proativo a partir de eventos de transação** (S)
   - Como já existe um Kafka, um consumer de eventos sintéticos de repasse ou falha abre o ticket ou avisa o lojista antes que ele reclame.
9. **Regras de fila escritas em linguagem natural** (S, sem discussão em fóruns)
   - A operação escreve "tickets de crédito da JIM acima de US$ 500 vão para a fila sênior".
   - O LLM gera a regra no DSL, um validador de schema confere, um dry-run mostra o diff e um humano aprova.
   - A demo é forte. Fica como stretch goal.
10. **Os motivos de escalação viram sinal para a operação** (S)
    - Um clustering semanal mostra onde falta conhecimento ou onde a política está ambígua.

**Opiniões contrárias a considerar:**

- O teto realista de deflexão fica entre 30% e 40%. As promessas de 80% a 90% dos fornecedores são chamadas de "nonsense" por um praticante com 10 anos de contact center.
- Desenhe o caminho humano como caminho principal para casos difíceis.
- Meça abandono e recontato, não só deflexão.
- Bot com tom "fake-warm" piora a experiência.

---

## 6. LLM dentro da plataforma (não no agente)

| Ponto de contato | Modo | Fallback determinístico |
|---|---|---|
| Triagem (intenção, marca, idioma) | Assíncrono, orçamento de 1 a 2 s, modelo pequeno | Regex ou palavras-chave → fila "geral" |
| Prioridade | O LLM extrai fatos; **uma fórmula decide** | Tabela de regras (fraude, conta bloqueada = P1) |
| Roteamento | **Só regras no caminho crítico** | n/a |
| Resumo do handoff | Assíncrono, modelo forte, com eval de fidelidade | Template com os campos estruturados |
| Copiloto do analista | Sob demanda | Macros |
| Detecção de frustração | Assíncrono, modelo pequeno | Léxico + sinais de recontato |
| Redação de PII antes do LLM | **Sem LLM**: regex + dígito verificador de CPF + Luhn (Presidio) | Bloqueia a chamada |

**Padrões de arquitetura:**

- **LLM como consumer lateral** do stream: `ticket.created` → `triage-enricher` → `ticket.enriched`.
  - O roteador usa o enriquecimento se ele chegar dentro do orçamento de tempo.
  - Se não chegar, roteia só por regras e reroteia depois.
- **Saídas estruturadas com enums.**
- **Cache por `hash(input redigido + versão do prompt + modelo)`**, o que também torna as evals reproduzíveis.
- **Prompts versionados em git.**
- **Calibrar a confiança no eval set**, porque a confiança autodeclarada do LLM é mal calibrada.

**Segurança:**

- Prompt injection via mensagem do cliente é o risco OWASP LLM01. Mitigação: o LLM de enriquecimento **não tem ferramentas** e só devolve enums (padrão dual-LLM).
- Ações irreversíveis passam por checagem de política mais aprovação humana.

**Mock do agente (decisão importante):** um mock determinístico com **modo caos** configurável, capaz de:

- responder devagar;
- duplicar respostas;
- responder fora de ordem;
- mandar JSON malformado;
- inventar nomes de tool;
- nunca escalar.

Como o agente real é externo, **a robustez da plataforma contra ele é exatamente o que dá para provar.** O Ollama pode ficar como modo opcional para a demo.

**Evals:**

- **Conjunto:** 200 a 400 tickets sintéticos em `evals/v1/*.jsonl`, rotulados com categoria, prioridade, fila, `should_escalate` e fatos-chave.
- **Métricas:**
  - F1 de roteamento;
  - **recall de escalação** (o erro mais caro em fintech);
  - fidelidade do resumo;
  - custo por ticket;
  - p95.
- **LLM como juiz:** usar só para o resumo, de outra família de modelo, invertendo a ordem e calibrado com cerca de 50 rótulos humanos.

---

## 7. Testes de pressão: como colocar a arquitetura à prova

**Ferramentas (escala de notebook, mas crível):**

- Docker Compose;
- **k6 com executores de taxa de chegada** (`constant-` e `ramping-arrival-rate`), que evitam o *coordinated omission*;
- **Toxiproxy** (latência, timeout, reset);
- **Pumba** (derrubar ou pausar containers);
- OpenTelemetry com o contexto propagado nos headers do Kafka, Jaeger, Prometheus e Grafana, e um exporter de lag;
- **SimPy** para simular políticas de fila.

**Menu de experimentos.** Escolha 3 ou 4 e faça-os bem.

1. **Carga sustentada com spike** (1x → 10x → 50x → 1x), com 1, 2 e 4 consumers.
   - Mede o **ponto de ruptura**: "aguenta Nx a referência antes de o p99 passar de X s".
   - Mede também o tempo de drenagem do lag.
2. **Queda do broker e tempestade de reentrega.**
   - Kafka parado por 60 s, combinado com 30% dos webhooks reenviados de 1 a 5 vezes, fora de ordem.
   - Hipótese: zero perda e zero resposta duplicada visível ao cliente.
3. **Agente lento ou falhando.**
   - Hipótese: o circuit breaker abre e a conversa escala para humano em até X s, sem nenhuma conversa ficar sem dono.
4. **Poison message.**
   - Hipótese: vai para a DLQ com o motivo e não trava a partição; o p99 das outras conversas não se altera.
5. **Rebalance ou crash de consumer sob carga.**
   - Hipótese: a ordem dentro da conversa é preservada e nenhum efeito sai duplicado.
6. **Noisy neighbor.**
   - Hipótese: uma marca inunda o sistema e o p95 das outras se mantém.
7. **Simulação de política de fila (SimPy)** comparando FIFO, prioridade com envelhecimento e skills.
   - Métricas: quebras de SLA de P1 e espera máxima de P3.
   - Validar antes contra Erlang C.
   - **Separa a pergunta de política da pergunta de infraestrutura.**

**Invariantes verificados automaticamente (Jepsen em miniatura):**

- O gerador de carga grava um *ledger* (JSONL) com tudo o que enviou.
- Um checker cruza esse ledger com o log de auditoria depois que o lag zera.
- O checker confere quatro invariantes:
  - **zero perda:** todo `external_msg_id` chega a um estado terminal;
  - **zero duplicata visível:** no máximo uma resposta por `(conversation_id, reply_seq)`;
  - **ordem monotônica** por conversa;
  - **nenhuma conversa órfã** por mais de T.
- Qualquer violação reprova o experimento.

**Armadilhas:**

- Testar só a borda HTTP: um 202 não prova nada, porque o lag pode crescer sem limite.
- Usar médias em vez de p50, p95 e p99 em histograma HDR.
- Fazer uma rodada só. São no mínimo 3, com a dispersão reportada.
- Esquecer o warm-up.
- Rodar o gerador na mesma CPU sem limite.
- Usar chaves uniformes. Use uma distribuição enviesada, com algumas conversas "tagarelas".

**Limitações a declarar:**

- Um host só, broker único, dados sintéticos e LLM mockado com latência injetada.
- Por isso, afirme **resultados relativos** (política A vs. B, 1 vs. 4 réplicas, invariante mantido ou violado), não capacidade de produção.

---

## 8. Lições da biblioteca da Liga

- **TRACTIAN é o precedente mais próximo:** agente auditável com escalação. A biblioteca **não tem nada sobre Kafka, webhooks, filas ou testes de carga e caos**. Esse é o território novo deste case, e é aí que ele se diferencia.
- **Reaproveitar:**
  - "O LLM orquestra, o sistema decide", com contratos Pydantic `extra="forbid"` (lição 6.1).
  - Pirâmide de testes de agente e invariante crítico (6.6).
  - Regras de EDD: nenhum prompt muda sem benchmark, e as evals funcionam como gate de CI.
  - Hipótese escrita antes de rodar, baseline "burro" primeiro e IC por bootstrap (2.1 e 2.5).
  - README em 9 seções e demo com plano B (6.7).
- **Fallback multi-LLM e supervisores LangGraph já foram feitos por várias pessoas da turma.** Isso não diferencia o projeto.

---

## 9. Decisões que ficam com você

1. **Núcleo:** A pura, A + timeline (o melhor de B) ou A + Temporal para SLA e handoff (o melhor de C)?
2. **Mensageria:** Kafka ou Redpanda na borda do agente, e o que fica para as filas internas (Sidekiq/Celery vs. pgmq)?
3. **Stack:** Ruby/Rails (alinhado à CloudWalk e ao Chatwoot) ou Python/FastAPI (mais próximo do ecossistema de LLM e de SimPy)?
4. **Linguagem das regras de fila:** CEL ou JSON-AST próprio?
5. **Mock do agente:** determinístico com modo caos (recomendado pela pesquisa), com Ollama como opcional?
6. **Desenho operacional:** IA como primeiro nível (padrão do TAPI) ou com copiloto do analista?
7. **Quais 2 ou 3 camadas de inovação da seção 5** entram no escopo do mês?
8. **Experimentos:** quais 3 ou 4 do menu da seção 7?

**Perguntas para o onboarding com a CloudWalk:**

- Volume real por canal e por marca, e o fator de pico.
- Formato das mensagens no tópico Kafka atual.
- Como o agente sinaliza a escalação hoje.
- Se existe requisito de residência de dados BR vs. US.

---

## Fontes principais

- [AWS Builders' Library: backlogs](https://aws.amazon.com/builders-library/avoiding-insurmountable-queue-backlogs/)
- [AWS Builders' Library: fairness](https://aws.amazon.com/builders-library/fairness-in-multi-tenant-systems)
- [Uber: reprocessing e DLQ](https://www.uber.com/blog/reliable-reprocessing/)
- [brandur: idempotency keys](https://brandur.org/idempotency-keys)
- [Svix: webhook signature](https://www.svix.com/resources/glossary/webhook-signature/)
- [Chatwoot: agent bots](https://www.chatwoot.com/docs/product/others/agent-bots)
- [Zendesk: skills routing](https://support.zendesk.com/hc/en-us/articles/5833468891674-About-using-skills-to-route-tickets)
- [CEL](https://opensource.google/projects/cel)
- [Temporal: entity workflow](https://docs.temporal.io/design-patterns/entity-workflow)
- [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)
- [MCP: tools spec](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [OWASP LLM Top 10](https://genai.owasp.org/llm-top-10/)
- [Dual-LLM pattern](https://simonwillison.net/2023/Apr/25/dual-llm-pattern/)
- [k6: open vs. closed model](https://grafana.com/docs/k6/latest/using-k6/scenarios/concepts/open-vs-closed/)
- [Toxiproxy](https://github.com/Shopify/toxiproxy)
- [OTel: messaging semconv](https://opentelemetry.io/docs/specs/semconv/messaging/)
- [Vanlightly: Kafka vs. Redpanda (cautela com benchmarks)](https://jack-vanlightly.com/blog/2023/5/15/kafka-vs-redpanda-performance-do-the-claims-add-up)
- Fóruns:
  - [r/AI_Agents: handoff](https://reddit.com/r/AI_Agents/comments/1te5z5x/)
  - [r/AI_Agents: warm transfer](https://reddit.com/r/AI_Agents/comments/1r6r54e/)
  - [r/LLMDevs: decisão vs. redação](https://reddit.com/r/LLMDevs/comments/1rov9xs/)
  - [r/AI_Agents: promessas honestas](https://reddit.com/r/AI_Agents/comments/1sybtn0/)
  - [HN: contact center veterans](https://news.ycombinator.com/item?id=43955374)
  - [HN: Air Canada](https://news.ycombinator.com/item?id=39378235)
  - [dev.to: cobrança dupla com Kafka](https://dev.to/shahzamandev/the-kafka-lesson-nobody-teaches-you-until-a-customer-gets-charged-twice-23jo)
- [Biblioteca da Liga](https://inteliacademyclub.github.io/library/), em especial `projetos/tractian`, `aulas/ml-preditivo-e-agentes` e `aulas/eval-driven-development`.

**Ressalvas de pesquisa:**

- A maior parte do Reddit foi acessada por um espelho, e os threads têm poucos votos. São relatos de praticantes, não consenso.
- Não há fontes oficiais da Intercom, Decagon ou Sierra sobre roteamento.
- Algumas páginas foram lidas só pelo resumo da busca.
- Nada sobre Pix, MED ou Brasil apareceu nos fóruns. Tudo o que tocar nisso é hipótese própria.
