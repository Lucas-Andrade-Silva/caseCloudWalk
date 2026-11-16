# ADR 0002 — Arquitetura, stack e escopo da plataforma de help desk

- Status: aceito. Itens ainda pendentes estão em "Pendências" e **não** fazem parte da decisão.
- Data: 2026-11-15
- Fontes: `docs/TAPI_cloudwalk.pdf`, `docs/research/2026-11-08-ideacao-arquitetura.md` e a conversa
  de decisão entre 2026-11-14 e 2026-11-15, em que cada escolha abaixo foi confirmada pelo dono do
  projeto.

## Contexto

O TAPI pede uma plataforma de help desk própria, AI-first, multi equipes e multi marcas, self-hosted.
O agente de IA da CloudWalk já existe, fica fora do escopo e será simulado. A plataforma recebe
mensagens de canais simulados, tria em filas configuráveis, integra o agente por webhook, broker e
Kafka, escala para analistas humanos com resumo e contexto, audita tudo e prova robustez com um
experimento técnico.

Restrições: projeto individual, entrega até **2026-11-27**, desenvolvimento com IA e TDD, apenas dados
sintéticos (LGPD), sem acesso a sistemas da CloudWalk. O desenho da arquitetura atual prometido na
seção 5 do TAPI ainda não foi recebido.

A pesquisa mostrou que o volume de referência é pequeno para um broker (~20 eventos/s no volume
base). O risco do projeto é a **corretude sob falha** (duplicata, ordem, handoff), não o throughput.

## Decisões

**D1. Núcleo: Postgres como fonte da verdade + outbox transacional + Kafka na borda do agente +
linha do tempo de eventos.**
- Mensagem, ticket, evento e linha do outbox são gravados numa única transação. Um relay publica no
  Kafka. O consumo é idempotente (`processed_events` na mesma transação do efeito).
- `conversation_events` é append-only e alimenta auditoria, verificador de invariantes e a tela de
  histórico.
- Por quê: é o mais fiel ao desenho de referência, testável e viável para uma pessoa. Dá ~80% do valor
  do event sourcing sem o custo.
- Descartado: Kafka como banco (atribuição precisa de compare-and-set, leitura-do-que-escreveu,
  LGPD em log imutável); Temporal como núcleo (segundo sistema com estado, curva de aprendizado);
  só Postgres como fila (foge da referência); actors (stack nova).

**D2. Stack: Rails (modo API) + React (Vite).**
- Sem Next.js (não precisa de SSR) e sem Hotwire (o dono só opera com React).
- Rails roda **somente em containers** (Ruby não está instalado no Windows do dono; `rdkafka` compila
  extensão nativa).
- Telas: chat do cliente, painel do analista, editor de filas, mapa vivo.

**D3. Kafka + Sidekiq.**
- Apache Kafka em modo KRaft, um nó. Karafka para produtores e consumidores. Relay do outbox e
  consumidores são **processos de longa duração**, não jobs.
- Sidekiq (Redis) só para jobs: vigia de SLA e limpeza do outbox. Jobs precisam ser idempotentes.
- Nada que precise ser exato vive no Redis (dedupe, estado de handoff e IDs processados ficam no
  Postgres). Motivo: relato real de dedupe por TTL no Redis falhando quando o lag passou do TTL.
- Por quê: o dono já usou Kafka com Sidekiq. Descartado: RabbitMQ (sem log particionado por chave);
  Solid Queue (menos peças, mas o dono conhece o Sidekiq).

**D4. Regras de fila: JSON próprio em árvore.**
- Lista ordenada por marca, primeira regra que bate vence. Fatos de uma lista fechada e tipada.
  Ações: definir fila, prioridade e tags. Conjuntos publicados são imutáveis e versionados; cada
  decisão registra `rule_set_version` e `matched_rule_id`. Há dry-run sobre os últimos N tickets.
- Fatos duros (marca, canal, recorrência, palavras-chave) e fatos do LLM (categoria, frustração,
  multi-assunto) são implementados **juntos**. Fato do LLM tem `source=llm` e confiança mínima por
  regra. O LLM fica atrás de uma chave; sem ele, as regras funcionam sozinhas.
- Por quê: a operação edita por formulário, a validação é trivial e o LLM preenche um schema.
- Descartado: CEL (suporte fraco em Ruby, exige sintaxe textual); scripting livre.

**D5. Operação: IA como primeiro nível, humano entra por escalação.**
- Gatilhos: (a) o agente pede; (b) a plataforma força por regra (cliente pediu humano, frustração alta,
  valor acima do limite, agente falhou ou estourou o tempo); (c) o analista assume.
- O caso escalado passa de novo pelo motor de regras com fatos extras (motivo, confiança do agente,
  tempo na fila da IA).
- Copiloto: apenas o **brief** do handoff. Sem sugestão de resposta. Sem devolução para a IA na
  primeira versão (fluxo de mão única). `handoff_epoch` permite adicionar isso depois.
- A plataforma não depende do agente para o handoff ser bom (gera e valida o brief por conta própria,
  com template de fallback).

**D6. Agente simulado: mock determinístico com modo caos.**
- Comportamentos configuráveis: latência, resposta duplicada, fora de ordem, JSON malformado, silêncio,
  queda, tool inventada, nunca escalar. Age na plataforma como usuário `bot` com identidade e
  permissões próprias. Consome do Kafka via broker.
- Ollama só como modo opcional de demo, nunca medido. Linguagem: Ruby (assumida).
- Por quê: o experimento exige controle e reprodutibilidade; um LLM local competiria por CPU.
- Limitação a declarar: taxas de escalação e de falha são parâmetros nossos, não do agente real.

**D7. Camadas extras: regras em linguagem natural, estimativa honesta de espera, mapa vivo.**
- Regras em linguagem natural: o LLM gera o JSON, o schema valida, o dry-run mostra o diff, um humano
  aprova. Estimativa de espera: calculada pela idade e profundidade da fila e mostrada no chat.
- **Mapa vivo** (visualização estilo Obsidian, clusters de tickets em tempo real) substitui o detector
  estatístico de incidentes como feature separada: um cluster que cresce acima de um limite dispara
  destaque. Detalhes de configuração ainda serão definidos com o dono.
- Descartado: suporte proativo por eventos de transação (fora de escopo); sinal de motivos de
  escalação (dados sintéticos só refletiriam o mock); memória vetorial (hype para o ganho).

**D8. Experimentos.**
- Principal: carga com falhas e invariantes verificados (ver `docs/PLAYBOOK.md`). Apoio: avaliação do
  mapa/detector se construído. Avaliação mínima de qualidade do LLM (50 a 100 tickets) aceita, mas de
  baixa prioridade.
- **Descartado pelo dono:** comparar "só regras" contra "regras + LLM". O modo só-regras continua
  exercitado como cenário de falha (LLM indisponível) dentro do experimento principal.
- Consequência assumida: sem baseline, o projeto não afirma que o LLM melhora o roteamento; afirma que
  ele funciona e degrada com segurança.

**D9. LLM: Groq como provedor principal.**
- Adaptador único com três modos: **stub** (carga e CI), **replay** (respostas gravadas e versionadas no
  repositório) e **live** (Groq). Modelo e temperatura fixados e registrados (modelo, versão,
  configuração). Redação de PII antes de qualquer chamada. Saída estruturada com schema; falha cai
  para regras. O LLM de enriquecimento não tem tools e trata texto do cliente como dado delimitado.
- Gemini só entra se a avaliação mostrar que o Groq não basta. OpenRouter gratuito está descartado
  (~50 requisições/dia sem créditos). Limites citados vêm de fontes de terceiros; conferir no console.
- Sem chamada de LLM real em teste de carga nem em testes automatizados.

**D10. Multi-marca: schema compartilhado com `brand_id`.**
- Escopo na aplicação (toda consulta filtra pela marca do contexto) + RLS nas tabelas centrais
  (`tickets`, `messages`, `conversation_events`, `decisions`) com `FORCE ROW LEVEL SECURITY` e
  `SET LOCAL` em consumidores e jobs, + teste de isolamento. Uma equipe ou analista pode atender mais
  de uma marca.
- Kafka: chave de partição `conversation_id`, `brand_id` em header, sem tópico por marca.
- Evolução registrada: célula por marca (residência de dados BR/US).

**D11. Memória entre interações: histórico estruturado + resumos de encerramento.**
- Reaproveita o resumidor do handoff. Cada resumo cita os tickets de origem, expira (prazo
  configurável) e pode ser excluído (direito ao esquecimento). É regenerado a partir do histórico, não
  acumulado. Vai no payload do agente e aparece no painel do analista.

**D12. Carga de referência e metas.**
- 1× = 20.000 tickets/dia (4× sobre os 5.000 de "milhares"), ~8 mensagens por conversa, hora de pico
  com 12% do dia, 3 a 4 eventos por mensagem → ~0,7 ticket/s, ~5 msg/s, ~20 eventos/s.
  Picos de 10× (~200 ev/s) e 50× (~1.000 ev/s) por 5 a 15 min.
- Escalação do mock: 30% e 60% (a CloudWalk real provavelmente fica em outro ponto).
- Metas: ACK do webhook p99 < 500 ms em 1×; **latência da plataforma** (ponta a ponta menos o tempo do
  agente) p99 < 1 s em 10×; lag recupera em < 5 min; agente em falha escala em ≤ 30 s (substituído pelo ADR 0004, H6: limite de 30 s,
  escalação em ≤ 40 s); invariantes com
  **zero violações**. As metas são chutes calibrados por um piloto e a mudança é registrada.

**D13. Demais escolhas.**
- Tempo real: ActionCable com adaptador Redis e saída por polling no React.
- Empacotamento: Docker Compose. Autenticação simples por papel (cliente, analista, ops, bot) com token,
  com evolução futura.
- Observabilidade: OpenTelemetry + Prometheus + Grafana, um backend de traces (Jaeger). Amostragem de
  1% a 10% nos testes de carga, total nos funcionais.
- Dados sintéticos: templates com variações geradas por LLM; o rótulo vem do gerador, nunca de um
  modelo avaliado.
- Testes: RSpec (backend) e Vitest com Testing Library (frontend). Análise do experimento em notebook
  Python isolado (pandas e Plotly), assumido.

**D14. Processo.** TDD obrigatório. Toda decisão fora do que está registrado passa pelo dono antes.
Detalhes em `docs/PLAYBOOK.md`.

## Consequências

- Rails, Karafka e Postgres com RLS dão mais peças a integrar. O risco principal está na integração
  (Kafka, Docker, ActionCable), não na lógica. A fatia ponta a ponta vem primeiro.
- Sem baseline de LLM, parte da evidência de valor do LLM fica de fora; isso entra nas limitações.
- Resultados do experimento valem para comparar configurações da plataforma. Não prevêem a produção.
- O prazo de 13 dias força um corte (ver ordem de corte no playbook).

## Pendências (não decididas)

- Se o dia 27 inclui a apresentação.
- Agrupar o trabalho em cerca de cinco PRs, mantendo a revisão independente.
- Linguagem da análise do experimento (assumido Python).
- Política para resposta do agente com `in_reply_to_seq` defasado: descartar ou sinalizar.
- ~~Níveis de prioridade e SLAs por prioridade.~~ Decidido no ADR 0004.
- Definição final de cluster do mapa vivo, limites de alerta, interações e biblioteca do grafo.
- Dono do broker e formato real das mensagens: confirmar no onboarding com a CloudWalk.
