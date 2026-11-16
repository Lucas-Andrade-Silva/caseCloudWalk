# caseCloudWalk

Plataforma de help desk AI-first, multi marca, feita como projeto acadêmico (Inteli) para a CloudWalk.
Recebe mensagens de canais simulados, tria em filas configuráveis, integra um agente de IA simulado por
webhook, broker e Kafka, e escala para analistas humanos com resumo e contexto. Só dados sintéticos.

O projeto está **em construção**. Hoje, sem telas: uma mensagem entra por um webhook de canal, vira ticket,
chega ao agente simulado e a resposta volta ao ticket; o agente pode escalar, a plataforma escala sozinha se
ele ficar em silêncio, e um analista puxa o ticket mais urgente da fila. Regras de fila configuráveis,
painel e interface ainda não existem.

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
A API responde em `http://localhost:3000/up`. Para trocar a porta, os segredos ou as credenciais locais,
copie `.env.example` para `.env`.

Para ver os caminhos principais funcionando, com a pilha no ar:

```bash
docker compose exec api bundle exec rails smoke:round_trip
```

```bash
docker compose exec api bundle exec rails smoke:escalation
```

O primeiro mostra o agente respondendo. O segundo mostra o agente escalando, um analista puxando o ticket,
respondendo dentro do prazo e fechando.

## Como testar

Um gate por componente:

```bash
docker compose run --rm test
```

```bash
docker compose run --rm broker-test
```

```bash
docker compose run --rm mock-agent-test
```

Os testes usam o Postgres e o Kafka reais do Compose; nenhum chama rede externa nem LLM.

## Onde está cada coisa

- Estado atual e próximos passos: [`docs/context/STATE.md`](docs/context/STATE.md)
- Como trabalhamos, arquitetura e plano: [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md)
- Decisões e justificativas: [`docs/decisions/`](docs/decisions/)
- Especificações de cada fatia: [`docs/specs/`](docs/specs/)
- Brief do parceiro: [`docs/TAPI_cloudwalk.pdf`](docs/TAPI_cloudwalk.pdf)
- Regras para agentes de IA: [`AGENTS.md`](AGENTS.md)

Toda alteração é feita em branch e chega à `main` por pull request com verificação e revisão independente.
