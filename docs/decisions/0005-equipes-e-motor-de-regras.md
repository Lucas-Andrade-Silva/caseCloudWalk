# ADR 0005 — Equipes e detalhes do motor de regras

- Status: aceito (R1 escolhido pelo dono; R2 a R5 detalham o D4 do ADR 0002 e aguardam confirmação).
- Data: 2026-11-15
- Fonte: conversa de decisão de 2026-11-15, na abertura da fatia 04.

## Contexto

O TAPI pede filas que distingam atendimentos "por marca, equipe, categoria ou prioridade", editáveis pela
operação, numa operação "multi equipes". O ADR 0002 (D4) decidiu o formato das regras (JSON próprio em
árvore, lista ordenada por marca, primeira que bate vence, versões imutáveis, dry-run). Faltava dizer o que é
uma equipe e alguns detalhes de execução das regras.

## Decisões

**R1. Equipe é um grupo de analistas que é dono de filas.** (escolha do dono)
- Uma equipe pode ser dona de filas de várias marcas. O analista entra na equipe e atende as filas dela.
- Substitui o vínculo direto analista ↔ fila da fatia 03. A migração cria uma equipe por fila existente e
  move os analistas, sem mudar quem atende o quê.
- Descartado: manter o vínculo direto (mover alguém exigiria editar fila por fila).

**R2. As regras rodam em dois momentos, com a mesma lista.**
- Na **abertura** do ticket: definem prioridade, tags e a fila prevista.
- Na **escalação**: rodam de novo, com fatos de escalação (motivo, gatilho, tempo com a IA), e definem a fila
  e a prioridade de verdade (ADR 0002, D5).
- O fato `stage` (`opening` ou `escalation`) permite escrever regras de um momento só.
- Sem regra que bata: fica a fila prevista na abertura; sem ela, a fila padrão da marca (ADR 0004, H2).

**R3. Fatos duros da primeira versão** (lista fechada e tipada): `brand`, `channel`, `stage`,
`message_text` (palavras-chave), `customer_recurring`, `contacts_24h`, `amount` (maior valor em dinheiro
citado pelo cliente), `escalation_reason`, `escalation_trigger`, `ai_minutes`. Fatos do LLM entram na fatia
de LLM. Fato ausente faz a condição ser falsa.

**R4. Cada versão guarda a lista inteira de regras.** Um conjunto de regras é um documento JSON imutável depois
de publicado; cada regra tem um `id` estável, que a decisão registra (`matched_rule_id`). Uma marca tem no
máximo um conjunto publicado; publicar outro arquiva o anterior.

**R5. Toda decisão de roteamento vira um registro de auditoria** (`decisions`) com versão do conjunto, regra
que bateu, fatos usados e resultado. O texto do cliente não é copiado: fica só o hash. O dry-run recalcula os
fatos a partir dos tickets.

## Consequências

- O painel de operação (fatia de interface) edita equipes, filas e regras por esta API.
- A extração de valor por expressão regular é limitada; o LLM pode trazer um fato de valor mais confiável depois.
