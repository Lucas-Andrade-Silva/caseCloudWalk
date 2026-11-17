# Piloto de carga em modo de produção (2026-11-16)

Piloto curto antes do experimento oficial, para descobrir cedo se a arquitetura aguenta o pico de 10×. Não
substitui o experimento (k6, cenários S1–S7, playbook §9).

## Como rodar

```bash
API_PORT=3002 docker compose -p helpdesk-pilot -f compose.yaml -f compose.pilot.yaml up -d --build
API_PORT=3002 docker compose -p helpdesk-pilot -f compose.yaml -f compose.pilot.yaml run --rm --no-deps -T api \
  bundle exec rails "load:burst[3000,50,0.2,6]"
API_PORT=3002 docker compose -p helpdesk-pilot -f compose.yaml -f compose.pilot.yaml exec -T api \
  bundle exec rails "invariants:check[tmp/ledgers/<run>.jsonl,300]"
```

`compose.pilot.yaml` liga `RAILS_ENV=production` (eager load, sem recarga de código), desliga o `force_ssl` só
para HTTP entre containers e expõe `WEB_CONCURRENCY` e `RAILS_MAX_THREADS` da API. O piloto usa projeto,
banco e Kafka próprios. Máquina: Windows 11, Docker Desktop com 12 CPUs e 11,5 GiB; tudo na mesma máquina,
inclusive o gerador de carga. Mock sem caos, escala 30%, sem latência própria.

## Carga

ADR 0002: 1× ≈ 5 mensagens de cliente/s (~20 eventos/s); 10× ≈ 50 mensagens/s. Cada rodada tem 20% de
reentregas de webhook. Ponta a ponta = mensagem do cliente gravada → resposta do bot gravada (inclui relay,
broker, Kafka, mock e volta). As medidas de atraso vieram de um script descartável sobre o banco; o
experimento oficial terá a sua medição com teste.

## Resultados

| Rodada | API (processos × threads) | ACK p50 / p99 | Outbox p99 | Ponta a ponta p50 / p99 | Respondidas / escaladas | Invariantes |
|---|---|---|---|---|---|---|
| 1×, 600 msgs | 1 × 3 | 37 / 168 ms | 246 ms | 276 / 474 ms | 489 / 111 | OK |
| 10×, 3.000 msgs | 1 × 3 | 654 / 1.079 ms | 373 ms | 25,2 / 37,6 s | 453 / 2.547 | OK |
| 10×, 3.000 msgs | 4 × 5 | 66 / 659 ms | — | — | — | 1 resposta 500 (deadlock) |
| 10×, com correção | 4 × 5 | 58 / 303 ms | 404 ms | 548 / 1.026 ms | 2.333 / 667 | OK, 0 deadlocks |
| 10×, com correção | 1 × 3 | 631 / 1.581 ms | 379 ms | 36,4 / 57,5 s | 681 / 2.319 | OK |

## O que aprendemos

1. **O relay não é o gargalo.** Entregou até 55 eventos/s, com atraso p99 abaixo de 410 ms em todas as
   rodadas. Cerca de 100 ms do atraso é a pausa de 0,2 s quando o outbox está vazio.
2. **O gargalo de vazão é a capacidade da API.** Com 1 processo e 3 threads, ela não acompanha 50 mensagens/s
   mais as respostas do bot: o ACK sobe, as respostas atrasam além de 30 s e o vigia escala a maioria dos
   tickets. Nenhuma mensagem se perde (invariantes OK), mas a experiência degrada. Com 4 × 5 a plataforma
   acompanha o 10×.
3. **Havia um deadlock na ingestão** (1 a cada ~3.600 envios). O `create_or_find_by!` do Rails relê o cliente
   com lock quando ele já existe. Uma mensagem segurava o cliente e esperava o ticket; outra do mesmo cliente
   segurava o ticket e, no segundo `UPDATE` do ticket, o Postgres refazia a checagem da chave estrangeira
   (`KEY SHARE` no cliente) e esperava a primeira. Prova: fotos do `pg_locks` durante uma reprodução isolada
   (16 threads, 4 clientes: 15 a 177 deadlocks por rodada antes, 0 depois em duas rodadas). Correção: a
   ingestão cria o cliente com `INSERT … ON CONFLICT DO NOTHING` e lê sem lock; teste de regressão em
   `spec/ingestion/receive_message_spec.rb`. O mesmo lock serializava as mensagens de um cliente
   (31 a 48 mil esperas em `customers` por reprodução, zero depois).

## Limitações

- Uma rodada por configuração, numa máquina só, com o gerador competindo por CPU com a pilha.
- O mock responde na hora; com um agente real, a ponta a ponta cresce pelo tempo do agente.
- Rodadas de 1 a 2 minutos; o pico de 10× do ADR dura de 5 a 15 minutos.
- 50× não foi testado.
- A meta de latência da plataforma (p99 < 1 s em 10×, sem o tempo do agente) ficou no limite (1.026 ms com o
  mock instantâneo).

## Decisão do dono (2026-11-16)

O experimento oficial usa a API com **4 processos × 5 threads**, padrão do `compose.pilot.yaml`.
