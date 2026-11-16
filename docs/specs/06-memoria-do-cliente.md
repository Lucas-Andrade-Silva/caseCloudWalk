# Fatia 06 — Memória do cliente

## Objetivo

Quando um cliente volta, o agente e o analista sabem o que aconteceu nos últimos contatos dele na mesma
marca, sem LLM, com prazo de validade e com exclusão sob pedido.

## Decisões aplicáveis

ADR 0002 (D11), ADR 0003 (E2), ADR 0006 (M1 a M4).

## Contratos

### Fechamento (analista)

`POST /api/tickets/:id/close` com `{"resolution_code": "resolved", "resolution_note": "..."}`.

- `resolution_code` obrigatório, um de `resolved`, `no_customer_response`, `duplicate`, `forwarded`; senão 422.
- `resolution_note` opcional, até 2.000 caracteres; senão 422.
- Grava `closed_at`, o código e a nota no ticket, o evento `ticket.closed` com o código (sem a nota) e o
  resumo de encerramento em `closing_summaries`, tudo na mesma transação.

### Resumo de encerramento

`{ version: 1, source: "template", ticket_id, text }`, com `expires_at = closed_at + janela`. O texto diz
canal, quando abriu e fechou, se passou por humano (gatilho, motivo, fila, prioridade), o pedido inicial do
cliente, o código e a nota de resolução.

### Memória

```json
{ "window_days": 90, "tickets": [ { "ticket_id": "…", "channel": "whatsapp", "mode": "closed",
  "opened_at": "…", "closed_at": "…", "priority": "p2", "queue": "credito-infinitepay", "tags": [],
  "escalation_reason": "…", "resolution_code": "resolved", "summary": "…" } ] }
```

Mais recentes primeiro, no máximo 5, mesma marca e cliente, sem o próprio ticket, abertos dentro da janela e
depois de `memory_erased_at`. Resumo expirado sai como `null`. Vai em `payload.memory` do `message.created` e
em `memory` de `GET /api/tickets/:id`.

### Exclusão (operação)

`DELETE /api/ops/brands/:brand/customers/:external_id/memory` → 200 com `{ summaries_deleted }`; marca ou
cliente desconhecido → 404. Registra em `memory_erasures`.

## Testes de aceite (escritos primeiro)

1. Fechar sem código, com código inválido ou nota longa responde 422 e não fecha.
2. Fechar grava código, nota, `closed_at`, evento e resumo; o resumo cita o ticket e expira na janela.
3. A memória traz só tickets da mesma marca e cliente, no máximo 5, na janela, sem o próprio, mais recentes
   primeiro; resumo expirado vira `null`.
4. O payload do agente e o `GET` do analista trazem a memória.
5. A exclusão apaga os resumos, esconde os tickets anteriores, registra a auditoria e não toca em outra marca.

## Fora de escopo

Resumo por LLM; apagar dados pessoais do cliente por inteiro; tela.
