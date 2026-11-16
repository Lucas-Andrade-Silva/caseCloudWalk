# Fatia 05 — Resiliência e verificação

## Objetivo

Uma mensagem com defeito não trava o fluxo de ninguém, uma queda temporária não perde nada, o agente
simulado consegue se comportar mal de propósito, e um verificador prova os quatro invariantes depois de uma
rajada de carga.

## Decisões aplicáveis

ADR 0002 (D1, D3, D6, D12), ADR 0003 (E1, E3), playbook §3.5, §3.6, §3.7, §6 e §9.

## Contratos

### Outbox: evento envenenado (plataforma → broker)

- O broker responde `4xx` definitivo (`400`, `404`, `413`, `422`): o evento fica **estacionado**
  (`dead_at`, `last_error`, `attempts`) e o relay segue com os outros. Os eventos seguintes **do mesmo ticket**
  ficam retidos até o estacionado ser reenviado ou descartado (playbook §3.5: estacionar a conversa).
- Falha temporária (rede, `5xx`, `401`, `403`, `408`, `429`): o relay para e tenta de novo com backoff, como
  hoje, e conta a tentativa.
- Rotinas: `outbox:dead` (lista), `outbox:retry_dead[id]` (volta para a fila, na ordem) e
  `outbox:discard_dead[id]` (descarta e libera o ticket).

### Broker: respostas do agente com retry e DLQ

Tópicos novos: `agent.replies.retry-1` (espera 10 s), `agent.replies.retry-2` (espera 60 s) e
`agent.replies.dlq`. Para cada resposta:

| Resultado da plataforma | O que o broker faz |
|---|---|
| `2xx` | Confirma |
| `404`, `409`, `422` | Confirma e registra a recusa (repetir não muda nada) |
| Plataforma fora (rede, `401`, `403`, `429`, `502`, `503`, `504`) | Pausa a partição e tenta a **mesma** mensagem de novo, sem gastar tentativa |
| Outro erro (`500` etc.) | Manda para o próximo estágio: principal → retry-1 → retry-2 → DLQ |

Mensagens dos estágios levam os headers originais mais `x-attempt`, `x-error` e `x-original-topic`. O
consumidor de retry só processa a mensagem depois do tempo de espera do estágio.

Rotina da DLQ no broker (`bin/dlq`): `list`, `replay` (republica em `agent.replies` o que ainda não foi
tratado) e `purge` (marca como tratado sem republicar).

### Agente simulado: modo caos

Configuração em `MOCK_CHAOS` (lista `chave=valor`), decidida pelo hash do `event_id` (determinística):

| Chave | Efeito |
|---|---|
| `latency_ms=200..2000` | Atraso uniforme da resposta, sem bloquear a partição (respostas podem chegar fora de ordem) |
| `duplicate=0.1` | Publica a mesma resposta duas vezes |
| `malformed=0.02` | Publica texto que não é JSON |
| `silence=0.05` | Não responde |
| `invented_tool=0.02` | Responde com uma ação que não existe |
| `crash=0.01` | Encerra o processo depois de publicar (o Docker reinicia) |
| `never_escalate=true` | Nunca escala |

### Verificador de invariantes (plataforma)

`invariants:check[ledger]` lê um ledger JSONL (`{"channel", "provider_message_id"}` por linha) e confere, no
banco, os invariantes do playbook §3.7:

1. **Zero perda:** toda mensagem do ledger entrou e está respondida (há resposta do bot com
   `in_reply_to_seq` igual ou maior) ou com o ticket fora da IA.
2. **Zero duplicata visível:** no máximo uma resposta do bot por `(ticket, in_reply_to_seq)`.
3. **Ordem:** `seq` contínuo por ticket e horário de gravação crescente com o `seq`.
4. **Sem órfãos:** nenhum ticket na IA com cliente esperando há mais de `T` (padrão 60 s) e nenhum ticket
   escalado sem fila.

Imprime o relatório e termina com código 1 se houver violação. `load:burst[n,rate,redeliver]` manda uma rajada
de webhooks (com reentregas) e grava o ledger, para testar antes do k6.

## Testes de aceite (escritos primeiro)

1. Relay: evento recusado com `422` fica estacionado e o seguinte de outro ticket sai; os seguintes do mesmo
   ticket ficam retidos; reenviar devolve a ordem; descartar libera o ticket; falha temporária conta tentativa
   e não estaciona.
2. Broker: cada linha da tabela acima, incluindo a espera do estágio de retry e os headers.
3. Mock: cada chave de caos, determinística e na fração configurada; sem caos, comportamento igual ao de hoje.
4. Verificador: passa num banco limpo; acusa perda, duplicata, buraco de `seq` e órfão plantados.

## Fora de escopo

k6 e o experimento oficial; tela da DLQ; alerta de SLA; circuit breaker do agente; cota por marca.

## Definição de pronto

Gates verdes; com o mock em caos e uma rajada de 300 mensagens com 20% de reentrega, o verificador passa sem
violações depois que o fluxo esvazia.

## Resultado da verificação (2026-11-16, ambiente de desenvolvimento)

| Rodada | Mensagens | Reentregas | Respondidas | Escaladas | Violações |
|---|---|---|---|---|---|
| Sem caos | 100 | 16 | 82 | 18 | 0 |
| Mock em caos (2 quedas, 12 silêncios, 16 respostas recusadas, 18 atrasadas) | 300 | 58 | 215 | 85 | 0 |
| Postgres parado por 20 s no meio | 89 confirmadas (1 recebeu 503) | 16 | 61 | 28 | 0 |

Na queda do Postgres, a API não respondeu 500 nenhuma vez e o broker só pausou; a DLQ ficou vazia. Os tempos
de ACK do ambiente de desenvolvimento não valem como medida.

## Riscos e perguntas ao dono

- Tempos de espera dos estágios (10 s e 60 s) e `T` de 60 s são números nossos.
- Retry de resposta quebra a ordem das respostas de um ticket; a plataforma já trata resposta atrasada
  (ADR 0003, E3).
