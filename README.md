# caseCloudWalk

Help desk AI-first e multimarca (InfinitePay e JIM), feito como projeto acadêmico (Inteli) para a CloudWalk. Só
dados sintéticos.

Um agente de IA, simulado, atende primeiro. A plataforma recebe as mensagens dos canais, tria e prioriza por
regras versionadas, entrega ao agente por webhook, broker e Kafka, e escala para analistas humanos com resumo e
contexto. Ela também lembra o cliente entre contatos e audita cada decisão.

```
canal -> api (Postgres + outbox) -> relay -> webhook assinado -> broker -> Kafka -> agente simulado
agente simulado -> Kafka -> broker -> api (como usuário bot)
```

## O que dá para ver

| Tela | O que mostra |
|---|---|
| **Painel** (`#/painel`) | Números reais do banco: abertos agora, criados e resolvidos hoje contra ontem, tickets por dia, primeira resposta humana, SLA, quem resolveu (IA ou humano) e canais. Exporta CSV. |
| **Fila** (`#/fila`) | A analista pega o ticket mais urgente, conversa e fecha com resolução. O painel lateral traz o brief da IA, a memória do cliente e a aba **Por que a IA decidiu**: o texto que a LLM viu (dados pessoais redigidos), a regra que casou e sua versão, a confiança da LLM, os fallbacks e o link para o trace. |
| **Modo Incidente** | Um pico de tickets parecidos (5 em 10 min, mesma marca e categoria) vira um incidente. A LLM escreve o título e o rascunho, e a analista responde e fecha todos de uma vez. |
| **Mapa vivo** (`#/mapa`) | Os tickets abertos agrupados, entrando e saindo em tempo real. Os tickets de um incidente formam um grupo laranja. |
| **Operação** (`#/operacao`) | Equipes, filas e regras versionadas, com simulação antes de publicar. |
| **Cliente** (`#/cliente`) | Chat do cliente simulado, sem login, com o botão "Simular pico". |

Tickets que a IA resolveu fecham sozinhos depois de 30 minutos sem mensagem do cliente.

## Como rodar

Requisito: Docker em execução (Desktop no Windows e no macOS). Não é preciso instalar Ruby.

```bash
docker compose up -d --build
```

- **Interface:** `http://127.0.0.1:5173`. Em desenvolvimento, a entrada oferece as pessoas de teste: Ana, Bruno e
  Carla (analistas) e Olivia (operação).
- **Use `127.0.0.1`**, não `localhost`: se outro programa ocupar a porta em IPv6, `localhost` cai nele.
- **Portas, segredos e credenciais locais:** copie `.env.example` para `.env`.

Para deixar o banco pronto para uma demonstração (apaga as conversas, mantém a configuração e cria uma cliente
com histórico):

```bash
docker compose exec api bundle exec rails demo:reset
```

## Como apresentar

O roteiro de 8 a 10 minutos está em [`docs/demo/roteiro-resiliencia.md`](docs/demo/roteiro-resiliencia.md):

1. Painel;
2. memória do cliente;
3. "Por que a IA decidiu";
4. Modo Incidente;
5. resiliência ao vivo.

Para provar a resiliência na frente da banca, este script derruba o Kafka no meio de uma rajada e confere que
nada se perdeu:

```powershell
./scripts/demo/resiliencia.ps1 -Cenario kafka
```

## Como testar

Um gate por componente. Os testes usam o Postgres e o Kafka do Compose; nenhum chama rede externa nem LLM.

```bash
docker compose run --rm test
```

```bash
docker compose run --rm broker-test
```

```bash
docker compose run --rm mock-agent-test
```

```bash
docker compose run --rm web-test
```

Com a pilha no ar, as fumaças mostram os caminhos principais: `smoke:round_trip`, `smoke:escalation` e
`smoke:routing` (via `docker compose exec api bundle exec rails <tarefa>`).

## Robustez e experimento

Quatro invariantes valem sempre: zero perda, zero duplicata, ordem e nenhum ticket esquecido. Uma rajada com
reentregas grava um ledger, e o verificador espera o fluxo esvaziar e confere os quatro:

```bash
docker compose exec api bundle exec rails "load:burst[300,5,0.2,42]"
```

```bash
docker compose exec api bundle exec rails "invariants:check[tmp/ledgers/<arquivo>.jsonl,180]"
```

O **experimento oficial** roda em modo de produção, com o k6 em taxa de chegada e 30% de reentregas fora de
ordem. São 3 cenários, com 3 rodadas cada:

```powershell
./scripts/experiment/run.ps1 -Cenarios S1,S2,S3 -Rodadas 3
```

Resultados em [`docs/research/2026-11-23-experimento-oficial.md`](docs/research/2026-11-23-experimento-oficial.md):

- **Invariantes:** OK nas 9 rodadas, com a rampa até 50×, o Kafka parado 60 s e o agente em caos.
- **10×:** ponta a ponta p99 de 1,18 a 1,25 s, então a meta de 1 s foi perdida por pouco.
- **Kafka:** o atraso esvaziou em menos de 1 min depois de o Kafka voltar.
- **Ruptura:** entre 10× e cerca de 37× nesta máquina.

Os resultados valem como comparação entre cenários, não como capacidade de produção: um host só, Kafka de 1 nó
e agente simulado.

## Como observar

```bash
OTEL_TRACES_EXPORTER=otlp docker compose --profile obs up -d
```

- **Grafana** (http://127.0.0.1:3030): requisições, latência, outbox, tickets por modo, espera e lag do Kafka.
- **Jaeger** (http://127.0.0.1:16686): cada mensagem vira um trace só, da entrada na API até a resposta do
  agente.
- **Prometheus** (http://127.0.0.1:9090): as métricas cruas.

## LLM

A LLM fornece fatos (categoria, idioma e frustração) e escreve o brief, o resumo de encerramento e o título e o
rascunho do incidente. Quem decide fila e prioridade continua sendo a regra (ADR 0008). Antes de qualquer
chamada, CPF, cartão, e-mail e telefone são trocados por marcadores. Se a LLM falhar ou demorar, tudo segue com
regras e templates.

O modo vem de `LLM_MODE`:

- `stub` (padrão): sem rede.
- `replay`: respostas gravadas.
- `live`: Groq, com `GROQ_API_KEY` no `.env`, nunca no repositório.
- `off`: sem LLM.

## Limitações declaradas

- Canais e agente são simulados.
- Não há isolamento por linha no banco (RLS), regras em linguagem natural nem estimativa de espera.
- Ninguém é avisado quando o SLA humano estoura (o Painel e o mapa mostram).
- Não foi testado em macOS e Linux.

## Onde está cada coisa

- Estado atual e próximos passos: [`docs/context/STATE.md`](docs/context/STATE.md)
- Como trabalhamos, arquitetura e plano: [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md)
- Decisões e justificativas: [`docs/decisions/`](docs/decisions/)
- Especificações de cada fatia: [`docs/specs/`](docs/specs/)
- Pesquisa (piloto e experimento): [`docs/research/`](docs/research/)
- Brief do parceiro: [`docs/TAPI_cloudwalk.pdf`](docs/TAPI_cloudwalk.pdf)

Toda alteração é feita em branch e chega à `main` por pull request, com verificação e revisão independente.
