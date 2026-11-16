# Fatia 02 — Ingestão e integração com o agente, de ponta a ponta

## Objetivo

Uma mensagem de um canal simulado entra na plataforma, vira ticket, chega ao agente simulado pelo caminho
webhook → broker → Kafka, e a resposta do agente volta e fica gravada no ticket, sem duplicar nem trocar a
ordem.

## Decisões aplicáveis

ADR 0003 (E1 a E4), ADR 0002 (D1, D3, D6, D13), playbook §3.1, §3.4, §3.5 e §3.7.

## Componentes

| Componente | Diretório | Papel |
|---|---|---|
| Plataforma | `backend/` | Ingestão, tickets, mensagens, linha do tempo, outbox, API do bot |
| Broker | `broker/` | Webhook → Kafka, e Kafka → API da plataforma. Sem banco |
| Agente simulado | `mock_agent/` | Consome `helpdesk.messages` e responde em `agent.replies` |

## Contratos

### Assinatura de webhook (canal → plataforma e plataforma → broker)

Headers: `X-Webhook-Id`, `X-Webhook-Timestamp` (segundos Unix) e `X-Webhook-Signature: v1=<hex>`, onde o hex é
o HMAC-SHA256 de `id.timestamp.corpo` com o segredo compartilhado. Tolerância de 5 minutos. O receptor aceita
uma lista de segredos (rotação); o emissor assina com o primeiro.

### Entrada de canal

`POST /webhooks/channels/:channel`, com `:channel` em `app_chat`, `whatsapp` ou `email`.

```json
{
  "provider_message_id": "wamid.123",
  "brand": "infinitepay",
  "customer": { "external_id": "cust-42", "name": "Maria" },
  "text": "minha maquininha não liga"
}
```

- `201` com `ticket_id`, `message_id`, `seq` e `duplicate: false`.
- `200` com os mesmos dados e `duplicate: true` quando `(channel, provider_message_id)` já foi recebido.
- `401` para assinatura inválida ou fora da tolerância. `422` para corpo inválido, canal ou marca desconhecidos.

### Evento para o agente (outbox → webhook → `helpdesk.messages`)

Chave: `ticket_id`. Headers: `brand_id` (slug da marca) e `event_id`. Só é emitido com o ticket em modo `ai`.

```json
{
  "type": "message.created",
  "ticket_id": "…", "brand": "infinitepay", "channel": "whatsapp",
  "mode": "ai", "handoff_epoch": 0,
  "customer": { "id": "…", "external_id": "cust-42" },
  "message": { "id": "…", "seq": 1, "sender": "customer", "text": "…", "created_at": "…" }
}
```

O relay entrega em `POST {BROKER_URL}/webhooks/helpdesk` o corpo `{ "topic", "key", "headers", "payload" }`,
assinado. O broker só aceita os tópicos da sua lista (`helpdesk.messages`).

### Resposta do agente (`agent.replies` → broker → plataforma)

Mensagem no Kafka (chave `ticket_id`) e corpo de `POST /api/agent/replies` com `Authorization: Bearer <token do bot>`:

```json
{
  "agent_turn_id": "uuid", "ticket_id": "uuid",
  "in_reply_to_seq": 1, "handoff_epoch": 0,
  "action": "reply", "text": "…"
}
```

- `201` com `message_id`, `seq`, `stale` e `duplicate: false`. `200` com `duplicate: true` para `agent_turn_id` repetido.
- `409` quando a resposta é descartada (ticket fora do modo `ai` ou `handoff_epoch` diferente). Fica auditada.
- `401`/`403` sem token válido de bot. `404` ticket inexistente. `422` corpo inválido.
- O broker confirma o offset em `2xx`, `404`, `409` e `422`; repete em `5xx`, `401`/`403` e erro de rede.

## Testes de aceite (escritos primeiro)

Plataforma
1. Mensagem válida cria cliente, ticket em modo `ai`, mensagem com `seq` 1, eventos `ticket.opened` e
   `message.received`, e um evento no outbox, tudo na mesma transação.
2. Segunda mensagem do mesmo cliente, marca e canal entra no mesmo ticket com `seq` 2.
3. Webhook repetido (mesmo `provider_message_id`) responde `200`, `duplicate: true`, e não cria nada.
4. Dois webhooks idênticos simultâneos criam uma mensagem. Duas primeiras mensagens simultâneas do mesmo
   cliente criam um ticket só, com `seq` 1 e 2.
5. Assinatura errada, timestamp velho ou segredo desconhecido: `401` e nada gravado. Segredo antigo da lista: aceito.
6. Se a gravação do outbox falha, nada fica gravado (atomicidade).
7. Resposta do bot vira mensagem com o próximo `seq` e evento `message.sent`. Repetida: `200`, sem efeito novo.
8. Resposta a uma mensagem que já não é a última do cliente: gravada com `stale: true`.
9. Resposta com `handoff_epoch` diferente ou ticket fora do modo `ai`: `409`, sem mensagem, evento `reply.discarded`.
10. Sem token, token errado ou usuário que não é bot: `401`/`403`.
11. O relay entrega o evento como webhook assinado; resposta diferente de `2xx` levanta erro e o evento continua pendente.
12. A linha do tempo não aceita alteração nem exclusão pelo modelo.

Broker
13. Webhook assinado e de tópico permitido é publicado no Kafka com chave, headers e corpo; responde `204`.
14. Assinatura inválida: `401`. Tópico fora da lista: `422`. Falha do Kafka: `503`. Em nenhum caso publica.
15. Resposta do agente é enviada à plataforma com o token do bot. `2xx`, `404`, `409` e `422` encerram;
    `5xx`, `401` e erro de rede levantam erro para o Kafka reentregar.

Agente simulado
16. Para cada mensagem, produz uma resposta com `in_reply_to_seq`, `handoff_epoch` e `ticket_id` corretos.
17. O `agent_turn_id` é derivado do `event_id`: a mesma mensagem entregue duas vezes gera o mesmo `agent_turn_id`.

Ponta a ponta
18. Com tudo no ar, um webhook de canal resulta numa mensagem do bot no ticket.

## Fora de escopo

Regras e filas; prioridade; handoff e painel; modo caos do mock; retry topics e DLQ; envio da resposta ao
canal; ActionCable e telas; RLS; LLM; observabilidade. Os fatos de roteamento entram na fatia de regras.

## Definição de pronto

- `docker compose up -d --build` sobe plataforma, relay, broker e mock saudáveis.
- Os três gates passam: `docker compose run --rm test`, `... broker-test` e `... mock-agent-test`.
- O teste ponta a ponta do item 18 passa contra a pilha em execução.

## Riscos e perguntas ao dono

- O relay entrega um webhook por vez. É simples e mantém a ordem, mas limita a vazão; medir no piloto de carga.
- Se o broker cair, a entrega para e o outbox acumula no Postgres (comportamento desejado, a medir).
- Nomes de campos e rotas acima são propostas nossas; o formato real da CloudWalk é desconhecido.
