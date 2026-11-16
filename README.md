# caseCloudWalk

Plataforma de help desk AI-first, multi marca, feita como projeto acadêmico (Inteli) para a CloudWalk.
Recebe mensagens de canais simulados, tria em filas configuráveis, integra um agente de IA simulado por
webhook, broker e Kafka, e escala para analistas humanos com resumo e contexto. Só dados sintéticos.

O projeto está **em construção**. Hoje existe a fundação técnica: o caminho Postgres (outbox) → relay →
Kafka → consumidor idempotente, coberto por testes. As funcionalidades de produto ainda não existem.

## Como rodar

Requisito único: Docker (Desktop no Windows e no macOS) em execução. Não é preciso instalar Ruby.

```bash
docker compose up -d --build
```

Sobe Postgres, Redis, Kafka (KRaft, um nó), a API Rails e o relay do outbox. A API responde em
`http://localhost:3000/up`. Para trocar a porta ou as credenciais locais, copie `.env.example` para `.env`.

## Como testar

```bash
docker compose run --rm test
```

Este é o gate oficial do backend. Os testes usam o Postgres e o Kafka reais do Compose; nenhum chama rede
externa nem LLM.

## Onde está cada coisa

- Estado atual e próximos passos: [`docs/context/STATE.md`](docs/context/STATE.md)
- Como trabalhamos, arquitetura e plano: [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md)
- Decisões e justificativas: [`docs/decisions/`](docs/decisions/)
- Especificações de cada fatia: [`docs/specs/`](docs/specs/)
- Brief do parceiro: [`docs/TAPI_cloudwalk.pdf`](docs/TAPI_cloudwalk.pdf)
- Regras para agentes de IA: [`AGENTS.md`](AGENTS.md)

Toda alteração é feita em branch e chega à `main` por pull request com verificação e revisão independente.
