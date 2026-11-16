# Fatia 04 — Equipes, filas e regras configuráveis

## Objetivo

A operação cria equipes e filas e escreve regras que escolhem fila, prioridade e tags de cada ticket, com
versões imutáveis, dry-run antes de publicar e auditoria de cada decisão, sem depender de desenvolvimento.

## Decisões aplicáveis

ADR 0005 (R1 a R5), ADR 0002 (D4, D5, D10), ADR 0004 (H2, H3), playbook §4.

## Contratos

### Regra (JSON)

```json
{
  "id": "credito-alto-valor",
  "name": "Crédito acima de R$ 5 mil",
  "when": { "all": [
    { "fact": "message_text", "op": "contains_any", "value": ["crédito", "empréstimo"] },
    { "fact": "amount", "op": "gte", "value": 5000 }
  ] },
  "then": { "queue": "credito-infinitepay", "priority": "p1", "tags": ["alto_valor"] }
}
```

- `when`: árvore de `all` / `any` com folhas `{fact, op, value}`. `{}` ou `{"all": []}` bate sempre.
- Operadores por tipo: texto `eq`, `neq`, `in`; palavras-chave `contains_any` (sem diferenciar maiúsculas
  nem acentos); número `eq`, `gt`, `gte`, `lt`, `lte`; booleano `eq`.
- `then`: ao menos um de `queue` (slug de fila da mesma marca), `priority` (`p1`…`p4`) e `tags`
  (`[a-z0-9_-]`).
- Validação recusa: fato ou operador desconhecido, valor do tipo errado, fila de outra marca ou inexistente,
  prioridade inexistente, `id` repetido ou fora de `[a-z0-9-]{1,64}`, mais de 100 regras, árvore com mais de
  5 níveis.

### API de operação (token de usuário `ops`)

| Rota | Efeito |
|---|---|
| `GET/POST /api/ops/teams` | Lista e cria equipes |
| `POST /api/ops/teams/:id/members`, `DELETE /api/ops/teams/:id/members/:user_id` | Põe e tira analistas |
| `GET/POST /api/ops/queues`, `PATCH /api/ops/queues/:id` | Lista, cria e edita filas (marca, equipe, nome) |
| `GET/POST /api/ops/brands/:brand/rule_sets` | Lista versões e cria um rascunho (próxima versão) |
| `GET/PATCH /api/ops/rule_sets/:id` | Lê e edita (só rascunho) |
| `POST /api/ops/rule_sets/:id/dry_run` | Aplica o rascunho aos últimos N tickets e mostra o que muda |
| `POST /api/ops/rule_sets/:id/publish` | Publica; o publicado anterior vira arquivado |

Erros de validação respondem `422` com a lista `errors` (caminho e mensagem).

### Efeito no ticket

- Abertura: aplica prioridade, tags e fila prevista; grava `decisions` (`step: routing.opening`).
- Escalação: reavalia com fatos de escalação; fila da regra, senão a prevista, senão a padrão; prioridade da
  regra, senão a atual; grava `decisions` (`step: routing.escalation`). O prazo de SLA usa a prioridade final.

## Testes de aceite (escritos primeiro)

1. Avaliador: cada operador, `all`/`any` aninhados, fato ausente é falso, primeira regra que bate vence,
   palavras-chave sem acento e sem caixa.
2. Fatos: valor em "R$ 5.000,00", "R$5000", "US$ 1,200.50"; recorrência e contatos em 24 h contados até o
   momento do ticket.
3. Validação: cada erro da lista acima, com caminho.
4. Abertura: regra publicada define prioridade, tags e fila prevista, e a decisão registra versão e regra.
   Sem conjunto publicado: `p3`, sem fila prevista, decisão sem regra.
5. Escalação: regra de escalação escolhe a fila; sem ela, fila prevista; sem ela, padrão. Prazo pela
   prioridade final.
6. Versões: rascunho editável; publicado imutável; publicar arquiva o anterior; um publicado por marca.
7. Dry-run: conta avaliados e mudados e lista antes e depois por ticket, sem gravar nada.
8. API: só `ops`; equipe nova com analista faz `work/next` entregar tickets das filas dela.
9. Migração: equipes criadas a partir dos vínculos antigos, sem mudar quem atende o quê.

## Fora de escopo

Telas; fatos do LLM e confiança mínima; regras em linguagem natural; remoção de filas com tickets; histórico
de quem editou além de `created_by`.

## Definição de pronto

Gates verdes; `smoke:routing` mostra uma mensagem com "crédito" e valor alto indo para a fila e prioridade da
regra publicada nos seeds; os testes de fumaça anteriores continuam verdes.
