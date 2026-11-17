# ADR 0006 — Memória entre interações sem LLM

- Status: aceito (M1 a M4 pelo dono em 2026-11-16; os detalhes marcados como proposta aguardam confirmação)
- Contexto: ADR 0002, D11 (histórico estruturado + resumos de encerramento que citam a origem, expiram, podem
  ser excluídos e são regenerados); TAPI exige memória e contexto entre interações.

## Decisões

**M1. Alcance: mesma marca, 5 últimos, 90 dias.** A memória de um ticket são os 5 tickets mais recentes do
mesmo cliente na mesma marca, de qualquer canal, abertos dentro da janela (90 dias, `MEMORY_WINDOW_DAYS`),
sem contar o próprio ticket. Marcas nunca se misturam (residência de dados BR/US).

**M2. Resolução no fechamento: código obrigatório + nota opcional.** Códigos: `resolved`,
`no_customer_response`, `duplicate`, `forwarded`. Nota livre de até 2.000 caracteres. Fechar sem código
responde 422. *Muda o contrato de `POST /api/tickets/:id/close`.*

**M3. Resumo de encerramento por template.** No fechamento, a plataforma gera um resumo (fonte `template`,
versão 1) que cita o ticket de origem e expira no fim da janela. É uma função pura do histórico do ticket,
então pode ser regenerado; a LLM troca só o gerador, com o template como fallback.

**M4. Prazo e exclusão agora.** A janela vale para o histórico e para os resumos. A operação apaga a memória
de um cliente por uma rota própria, com registro na auditoria.

## Proposta (detalhes preenchidos pelo agente, aguardam o dono)

- A memória vai no payload `message.created` do agente (`memory`) e em `GET /api/tickets/:id`.
- Cada item: ticket, canal, modo, abertura, fechamento, prioridade, fila, tags, motivo da escalação, código
  de resolução e resumo (se existir e não tiver expirado).
- Exclusão: `DELETE /api/ops/brands/:brand/customers/:external_id/memory` apaga os resumos do cliente e marca
  `memory_erased_at`; a partir daí a memória ignora os tickets abertos antes dessa data. A auditoria
  (`memory_erasures`) guarda marca, cliente, quem pediu, quantos resumos saíram e quando — sem texto.
- Tickets e mensagens **não** são apagados: são registro operacional e de auditoria. Apagar os dados
  pessoais do cliente por inteiro é outra decisão (fora desta fatia).

## Consequências

- O payload do agente cresce, limitado a 5 itens.
- A interface do analista nasce com o campo de resolução.
- Sem LLM, o resumo é factual e previsível; a qualidade de texto vem na etapa da LLM.
