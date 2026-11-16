# Fatia 03 — Handoff e escalação

## Objetivo

Um ticket atendido pela IA passa para um analista humano, por pedido do agente, por silêncio do agente ou
por decisão do analista, com brief, fila, prioridade e prazo, sem que o bot volte a escrever depois disso.

## Decisões aplicáveis

ADR 0004 (H1 a H4), ADR 0003 (E1 a E3), ADR 0002 (D3, D5, D12), playbook §3.4 e §3.5.

## Contratos

### Dados

- `queues`: `id`, `brand_id`, `slug`, `name`, `default` (uma padrão por marca).
- `queue_memberships`: `user_id` + `queue_id`. Um analista pode servir filas de mais de uma marca.
- `priority_levels`: `code` (`p1`…`p4`), `name`, `first_response_minutes`. Editável.
- `tickets` ganha: `queue_id`, `priority` (padrão `p3`), `assignee_id`, `lock_version`, `escalated_at`,
  `first_response_due_at`, `first_human_response_at`, `handoff_brief` (jsonb).
- Os seeds criam as filas padrão, os níveis de prioridade e dois analistas sintéticos com tokens de
  desenvolvimento.

### Máquina de estados

`ai → pending_human → human → closed` e `ai → human` (takeover). Toda troca de dono incrementa
`handoff_epoch`. Transição inválida levanta erro e não grava nada.

### Pedido de escalação do agente (H1)

`POST /api/agent/replies` com `action: "escalate"`, `reason` (obrigatório, `[a-z0-9_]{1,64}`) e `text`
(opcional). Com o ticket em `ai` e o `handoff_epoch` certo, numa transação:
1. grava a mensagem de despedida do bot, se houver;
2. muda para `pending_human`, incrementa `handoff_epoch`, define fila padrão da marca, prioridade `p3`,
   `escalated_at` e `first_response_due_at`;
3. gera o brief e registra `ticket.escalated` (`trigger: agent_requested`, `reason`);
4. avisa o agente pelo outbox (`type: "ticket.escalated"`), para ele parar de atender.

Resposta `201` com `escalated: true`. Repetida: `200`, sem efeito. Fora do modo `ai` ou com epoch errado:
`409`, descartada e auditada (igual à resposta comum).

### Escalação forçada pela plataforma

O **vigia do agente** procura tickets em `ai` cuja última mensagem é do cliente há mais de **30 s**
(configurável) e os escala com `trigger: agent_timeout`. Roda a cada 5 s. É idempotente: um ticket já
escalado não muda.

### Analista (token de usuário `analyst`)

| Rota | Efeito |
|---|---|
| `POST /api/work/next` | Pega o ticket `pending_human` de prazo mais próximo nas filas do analista: vira `human`, com dono. `204` se não há nada |
| `POST /api/tickets/:id/takeover` | Assume um ticket em `ai` de uma fila sua: vira `human`, `trigger: analyst_takeover` |
| `POST /api/tickets/:id/messages` | Só o dono escreve. A primeira registra `first_human_response_at` e se o SLA foi cumprido |
| `POST /api/tickets/:id/close` | Só o dono fecha |
| `GET /api/tickets/:id` | Ticket, brief, mensagens e linha do tempo (para o painel) |

Atribuição com lock: `SELECT … FOR UPDATE SKIP LOCKED` para escolher e `UPDATE … WHERE assignee_id IS NULL`
para confirmar. Perdeu a disputa: tenta o próximo.

### Brief (sem LLM nesta fatia)

Template preenchido pela plataforma: motivo e gatilho, marca, canal, cliente, tempo com a IA, número de
mensagens, último pedido do cliente e as últimas 6 mensagens. Guardado em `handoff_brief` e na linha do tempo.
O resumo por LLM substitui o template na fatia de LLM, mantendo o template como fallback.

### Mock do agente

Escala de forma determinística uma fração das mensagens, configurada por `MOCK_ESCALATION_RATE` (padrão
`0.3`), decidida pelo hash do `event_id`. Ignora eventos `ticket.escalated`. As marcas `[escalar]` e
`[responder]` no texto do cliente forçam a decisão, para demos e testes de fumaça (proposta, a confirmar).

## Testes de aceite (escritos primeiro)

1. Pedido de escalação: ticket vai a `pending_human`, epoch +1, fila padrão da marca, `p3`, prazo de 1 h,
   brief preenchido, evento `ticket.escalated`, aviso ao agente no outbox.
2. Depois da escalação, resposta do bot com o epoch antigo é descartada (`409`); mensagem do cliente não
   gera evento para o agente.
3. Pedido de escalação repetido não repete efeito.
4. Vigia: ticket com o cliente sem resposta há 31 s escala com `agent_timeout`; há 29 s não escala;
   rodar duas vezes não escala duas vezes.
5. `work/next` entrega o ticket de prazo mais próximo, só das filas do analista; `204` quando vazio.
6. Dois analistas pedem o próximo ao mesmo tempo: cada um recebe um ticket diferente, nenhum fica com dois
   donos.
7. Takeover em `ai`: vira `human`, epoch +1; resposta do bot em seguida é descartada.
8. Só o dono escreve e fecha; a primeira mensagem marca o SLA como cumprido ou estourado.
9. Transições inválidas (`closed → ai`, `human → pending_human`) são recusadas.
10. Mock: com taxa 0 nunca escala, com taxa 1 sempre escala, e a mesma mensagem decide sempre igual.
11. Ponta a ponta: com taxa 1, uma mensagem de canal termina em `pending_human` com brief.

## Fora de escopo

Regras e filas configuráveis (fatia 04); gatilhos por fatos (cliente pediu humano, frustração, valor);
painel em React e ActionCable; envio ao canal; resumo por LLM; devolução à IA; modo caos do mock;
redistribuição quando o analista some; alerta de SLA estourado além do registro.

## Definição de pronto

Os três gates passam e `smoke:round_trip` continua verde; um novo `smoke:escalation` mostra um ticket indo
de `ai` a `human` com brief, com a pilha no ar.

## Riscos e perguntas ao dono

- Mecanismo do vigia: `sidekiq-cron`, decidido (ADR 0004, H5).
- Prazos do SLA e janela de 30 s são números nossos; o piloto de carga pode pedir ajuste.
- **Medido na pilha real:** com limite de 30 s, o vigia escalou em 37,4 s (limite + ciclo de 5 s + atraso do
  agendador). O dono manteve os 30 s e a meta passou a ser ≤ 40 s (ADR 0004, H6).
- Os tokens de analista são de desenvolvimento; a autenticação real está fora do escopo (ADR 0002, D13).
