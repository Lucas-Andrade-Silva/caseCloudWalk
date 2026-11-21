# caseCloudWalk

Plataforma de help desk AI-first, multi marca, feita como projeto acadêmico (Inteli) para a CloudWalk.
Recebe mensagens de canais simulados, tria em filas configuráveis, integra um agente de IA simulado por
webhook, broker e Kafka, e escala para analistas humanos com resumo e contexto. Só dados sintéticos.

O projeto está **em construção**. Uma mensagem entra por um canal (webhook ou o chat do cliente simulado),
vira ticket, chega ao agente simulado e a resposta volta; o agente pode escalar, a plataforma escala sozinha
se ele ficar em silêncio, e um analista puxa o ticket mais urgente no painel, conversa, vê o brief e a
memória do cliente e fecha com a resolução. A operação configura equipes, filas e regras versionadas (com
dry-run) pela tela da operação, e o mapa vivo (`#/mapa`) mostra os tickets abertos agrupados, entrando e
saindo em tempo real.

```
canal -> api (Postgres + outbox) -> relay -> webhook assinado -> broker -> Kafka -> agente simulado
agente simulado -> Kafka -> broker -> api (como usuário bot)
```

## Como rodar

Requisito único: Docker (Desktop no Windows e no macOS) em execução. Não é preciso instalar Ruby.

```bash
docker compose up -d --build
```

Sobe Postgres, Redis, Kafka (KRaft, um nó), a API Rails, o relay do outbox, o broker e o agente simulado.
A API responde em `http://localhost:3000/up` e a interface em `http://127.0.0.1:5173` (em desenvolvimento,
a tela de entrada oferece as pessoas de teste). O cliente simulado conversa em `http://127.0.0.1:5173/#/cliente`,
sem login: abra numa janela e o painel da analista em outra. Prefira `127.0.0.1` a `localhost`: se outro programa da
máquina ocupar a mesma porta em IPv6, `localhost` cai nele. Para trocar portas, segredos ou credenciais
locais, copie `.env.example` para `.env`.

Para ver os caminhos principais funcionando, com a pilha no ar:

```bash
docker compose exec api bundle exec rails smoke:round_trip
```

```bash
docker compose exec api bundle exec rails smoke:escalation
```

```bash
docker compose exec api bundle exec rails smoke:routing
```

O primeiro mostra o agente respondendo. O segundo mostra o agente escalando, um analista puxando o ticket,
respondendo dentro do prazo e fechando. O terceiro mostra uma regra publicada mandando um pedido de crédito
de valor alto para a fila de Crédito com prioridade P1.

## Como testar

Um gate por componente:

```bash
docker compose run --rm test
```

```bash
docker compose run --rm broker-test
```

```bash
docker compose run --rm web-test
```

```bash
docker compose run --rm mock-agent-test
```

Os testes usam o Postgres e o Kafka reais do Compose; nenhum chama rede externa nem LLM.

## Como provar a robustez

Uma rajada de mensagens com reentregas grava um ledger; o verificador espera o fluxo esvaziar e confere os
quatro invariantes (zero perda, zero duplicata, ordem e nenhum ticket esquecido):

```bash
docker compose exec api bundle exec rails "load:burst[300,5,0.2,42]"
```

```bash
docker compose exec api bundle exec rails "invariants:check[tmp/ledgers/<arquivo>.jsonl,180]"
```

Para fazer o agente simulado se comportar mal (atraso, duplicata, JSON quebrado, silêncio, queda), suba o
mock com `MOCK_CHAOS` (exemplos em `.env.example`).

Tempos medidos no ambiente de desenvolvimento não valem. Para medir, suba uma cópia em modo de produção, com
banco próprio (resultados do piloto em [`docs/research/2026-11-16-piloto-de-carga.md`](docs/research/2026-11-16-piloto-de-carga.md)):

```bash
API_PORT=3002 docker compose -p helpdesk-pilot -f compose.yaml -f compose.pilot.yaml up -d --build
```

## Como observar

Traces e métricas sobem com o perfil `obs` (ADR 0008):

```bash
OTEL_TRACES_EXPORTER=otlp docker compose --profile obs up -d
```

- **Grafana** (http://127.0.0.1:3030, leitura sem login): painel "Help Desk — plataforma" com requisições e
  latência da API e do broker, outbox pendente e estacionado, tickets por modo, espera por humano e pelo
  agente e lag dos consumidores do Kafka.
- **Jaeger** (http://127.0.0.1:16686): cada mensagem vira um trace só, da entrada na API ao outbox, relay,
  broker, Kafka, agente simulado e de volta à API.
- **Prometheus** (http://127.0.0.1:9090): as métricas cruas (`/metrics` da API e do broker).

Sem o perfil, a aplicação roda igual e não exporta traces. A amostragem é ajustável com
`OTEL_TRACES_SAMPLER_ARG` (1.0 = tudo; use 0.01 a 0.1 em teste de carga).

## LLM

A LLM dá fatos (categoria, idioma, frustração) que as regras podem usar, e melhora o brief do handoff e o
resumo de encerramento; quem decide fila e prioridade continua sendo a regra (ADR 0008). Modo em `LLM_MODE`:

- `stub` (padrão): sem rede, respostas previsíveis. É o que roda nos testes e na carga.
- `replay`: respostas gravadas em `backend/llm_replay`, para reproduzir uma demonstração sem chamar ninguém.
- `live`: Groq (`openai/gpt-oss-120b`). Crie a chave no console do Groq e coloque `GROQ_API_KEY` no seu `.env`
  (nunca no repositório). Com `LLM_RECORD=true`, as respostas ao vivo são gravadas para o `replay`.
- `off`: sem LLM; tudo funciona só com regras e templates.

Antes de qualquer chamada, CPF, cartão, e-mail e telefone são trocados por marcadores. Se a LLM falhar ou
demorar, o atendimento segue sem ela.

## Onde está cada coisa

- Estado atual e próximos passos: [`docs/context/STATE.md`](docs/context/STATE.md)
- Como trabalhamos, arquitetura e plano: [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md)
- Decisões e justificativas: [`docs/decisions/`](docs/decisions/)
- Especificações de cada fatia: [`docs/specs/`](docs/specs/)
- Brief do parceiro: [`docs/TAPI_cloudwalk.pdf`](docs/TAPI_cloudwalk.pdf)
- Regras para agentes de IA: [`AGENTS.md`](AGENTS.md)

Toda alteração é feita em branch e chega à `main` por pull request com verificação e revisão independente.
