# ADR 0008 — Observabilidade e LLM: decisões de implementação

- Status: aceito (O1, L1 a L3 pelo dono em 2026-11-18; O2 a O5 propostas pelo agente, aguardam o dono)
- Contexto: ADR 0002 já decidiu OpenTelemetry + Prometheus + Grafana + Jaeger (D13), Groq com adaptador
  stub/replay/live (D9) e o LLM como fonte de fatos, não de decisões (D4 e playbook §5). Faltavam escolhas de
  implementação.

## Decisões do dono

**O1. Observabilidade antes do LLM.** Traces e métricas servem ao experimento e depois mostram o LLM
funcionando.

**L1. Enriquecimento depois da entrada, num job do Sidekiq.** A mensagem entra e o canal recebe o 2xx como
hoje; o job enriquece e o ticket é reroteado se os fatos novos mudarem a regra. LLM lento ou fora do ar não
atrasa o ACK (meta p99 < 500 ms).

**L2. Modelo: `openai/gpt-oss-120b` no Groq**, com saída em JSON Schema estrito. Os modelos Llama do Groq só
têm modo JSON, sem garantia de schema. Limites do plano gratuito conferidos só na documentação (~30
req/min, ~1.000/dia, a confirmar no console): servem para gravar o replay e para a demo; carga e testes
nunca chamam o Groq.

**L3. Categorias fechadas:** `credito`, `maquininha`, `pagamentos_pix`, `repasse`, `conta_cadastro`,
`falar_com_humano`, `outro`. Viram o fato `category` nas regras, com origem `llm`.

## Propostas do agente (aguardam o dono)

**O2. Traces ponta a ponta pelo caminho real.** Contexto W3C (`traceparent`) da requisição de entrada vai
para o outbox junto com o evento; o relay continua o trace ao entregar o webhook; o broker e o agente simulado
propagam pelos headers do Kafka (injeção e extração explícitas: a instrumentação automática do `rdkafka` não
reconhece a variante `karafka-rdkafka`); a resposta volta à API no mesmo trace. Os serviços mandam OTLP
direto ao Jaeger 2, que já é um coletor OpenTelemetry; a amostragem fica no SDK
(`OTEL_TRACES_SAMPLER=parentbased_traceidratio`): total em desenvolvimento, 1% a 10% na carga.

**O3. Métricas com `prometheus-client`** (Ruby, mantida pelo projeto Prometheus): RED por rota na API e no
broker via middleware Rack, e medidas do domínio calculadas do banco a cada coleta (outbox pendente e idade
do mais antigo, estacionados, tickets esperando humano e idade do mais antigo, por marca). Lag do consumidor
do Kafka pelo `kafka-exporter`. As métricas OpenTelemetry do Ruby ainda são experimentais.

**O4. A pilha de observabilidade sobe com o perfil `obs`** (`docker compose --profile obs up -d`): Jaeger
2.22, Prometheus 3.15, Grafana 12.4 e `kafka-exporter` 1.11. Sem o perfil, a aplicação roda igual e só não exporta.

**O5. `/metrics` sem autenticação, só na rede do Compose.** Em produção ficaria atrás da rede interna.

## Consequências

- Mais containers e dependências; versões fixadas, cada uma publicada há pelo menos 14 dias.
- Amostragem baixa na carga é limitação a declarar no experimento.
