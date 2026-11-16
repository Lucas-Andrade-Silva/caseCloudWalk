# Fatia 01 — Fundação técnica e ida e volta pelo Kafka

## Objetivo

Provar, em containers e com um comando de teste oficial, que um evento gravado no outbox do Postgres é
publicado no Kafka em ordem e consumido de volta com efeito idempotente.

## Decisões aplicáveis

- ADR 0002: D1 (Postgres + outbox + Kafka + consumo idempotente), D2 (Rails API só em containers),
  D3 (Kafka KRaft de um nó, Karafka, relay como processo de longa duração), D13 (Docker Compose, RSpec).
- Playbook: §0 (regras), §1.2 (TDD), §3.5 (outbox + inbox, efeito e `processed_events` na mesma transação),
  §3.6 (antipadrões), §10 (gate dos dias 15–16), §11 (ambiente).

## Contratos

Esta fatia cria **infraestrutura**. Não define o envelope das mensagens de domínio nem cria tópicos de
produto (`helpdesk.messages`, `agent.replies`): isso pertence à fatia de ingestão.

**Tabela `outbox_events`** (a entidade `outbox` do playbook)

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | bigserial | ordem de publicação |
| `event_id` | uuid | único; gerado no banco; identidade do evento para dedupe no consumo |
| `topic` | text | obrigatório |
| `key` | text | obrigatório; chave de partição (nas mensagens de domínio, `conversation_id`) |
| `payload` | jsonb | obrigatório |
| `headers` | jsonb | padrão `{}` |
| `created_at` | timestamptz | |
| `published_at` | timestamptz | nulo até o relay confirmar a publicação |

**Tabela `processed_events`**: `consumer_name` (text) + `event_id` (uuid) como chave primária, `processed_at`.

**Mensagem no Kafka:** chave = `key`; corpo = `payload` em JSON; headers = `headers` + `event_id`.

**Relay:** lê os eventos não publicados por `id`, publica de forma síncrona e marca `published_at`. Uma única
instância ativa por vez, garantida por advisory lock de sessão no Postgres. Se cair entre publicar e marcar,
republica (at-least-once); o consumidor absorve a duplicata.

**Consumo idempotente:** `processed_events` é inserido na mesma transação do efeito. Evento já registrado
não repete o efeito. Efeito que falha desfaz o registro, e a reentrega processa de novo.

## Testes de aceite (escritos primeiro)

1. **Ordem e marcação.** Dado três eventos pendentes, quando o relay publica, então o produtor recebe os três
   em ordem de `id`, com chave, corpo, headers e `event_id`, e os três ficam com `published_at`.
2. **Sem republicação.** Dado eventos já publicados, quando o relay roda de novo, então nada é enviado.
3. **Falha no meio do lote.** Dado três eventos e um produtor que falha no segundo, quando o relay roda, então
   só o primeiro fica publicado e o erro sobe; na rodada seguinte o segundo e o terceiro saem em ordem.
4. **Efeito único.** Dado um `event_id`, quando ele é processado duas vezes pelo mesmo consumidor, então o
   efeito roda uma vez. Consumidores diferentes processam o mesmo evento de forma independente.
5. **Falha do efeito.** Dado um efeito que levanta erro, então `processed_events` não guarda o evento e uma
   nova tentativa executa o efeito.
6. **Concorrência.** Dado o mesmo evento entregue a duas threads ao mesmo tempo, então o efeito roda uma vez.
7. **Relay único.** Dado um relay segurando o lock, quando outro tenta assumir em outra conexão, então não
   consegue; ao liberar, consegue.
8. **Kafka real.** Dado três eventos da mesma chave no outbox, quando o relay publica num Kafka real, então
   um consumidor lê os três na ordem, com chave, corpo e headers corretos.
9. **Ida e volta com reentrega.** Dado um consumidor Karafka de teste e o mesmo evento publicado duas vezes,
   então o efeito acontece uma vez e `processed_events` tem uma linha.

## Fora de escopo

Ingestão por webhook e HMAC; modelo de domínio (marcas, conversas, mensagens, tickets); atomicidade do outbox
com escrita de domínio (testada quando a ingestão existir); retry topics e DLQ; limpeza do outbox; Sidekiq;
ActionCable; frontend; RLS; observabilidade; mock do agente.

## Definição de pronto

- `docker compose up -d --build` num clone limpo sobe Postgres, Redis, Kafka, API e relay saudáveis.
- `docker compose run --rm test` roda a suíte e termina com zero falhas.
- O comando do gate está registrado em `docs/context/STATE.md`.

## Riscos e perguntas ao dono

- Kafka em Docker no Windows e Karafka embutido nos testes são os pontos de maior incerteza.
- Ordem global por `id` não é garantida entre transações concorrentes (um `id` menor pode confirmar depois
  de um maior). A ordem **por conversa** será garantida pelo lock de linha da conversa na fatia de ingestão.
- Versões fixadas e nomes escolhidos nesta fatia ficam listados no relatório de entrega para confirmação.
