# ADR 0004 — Pedido de escalação, fila inicial, prioridades e atribuição

- Status: aceito.
- Data: 2026-11-15
- Fonte: conversa de decisão de 2026-11-15, na abertura da fatia 03. O dono escolheu cada item abaixo.
- Fecha a pendência "níveis de prioridade e SLAs por prioridade" do ADR 0002.

## Contexto

A fatia 03 constrói o handoff da IA para o humano (ADR 0002, D5). Faltavam quatro definições: como o agente
pede escalação, para onde vai o ticket enquanto o motor de regras não existe, quais prioridades e prazos
o vigia de SLA usa e como o ticket chega a um analista.

## Decisões

**H1. O agente pede escalação com a ação `escalate`.**
- Mesmo endpoint da resposta (`POST /api/agent/replies`), com `action: "escalate"`, um `reason` obrigatório
  e um `text` opcional (mensagem de despedida ao cliente).
- Herda a autenticação, a idempotência pelo `agent_turn_id`, as checagens de modo e `handoff_epoch` e a
  auditoria da resposta comum.
- A plataforma escreve o brief do handoff sozinha; não depende do agente para isso.
- Descartado: endpoint separado (duplica autenticação, validação e idempotência); palavra-chave no texto
  (frágil; é a origem do "handoff fantasma" apontado na pesquisa).

**H2. Fila humana por marca até o motor de regras existir.**
- Os seeds criam uma fila padrão por marca ("Atendimento InfinitePay" e "Atendimento JIM").
- O ticket escalado vai para a fila padrão da sua marca. Na fatia de regras, essas filas viram o destino de
  quando nenhuma regra bate.
- Descartado: fila única (o painel nasceria sem separação por marca); inverter as fatias de handoff e regras
  (atrasa a parte mais avaliada).

**H3. Quatro níveis de prioridade, com prazo para a primeira resposta humana.**

| Nível | Nome | Prazo |
|---|---|---|
| P1 | urgente | 5 min |
| P2 | alta | 15 min |
| P3 | normal | 1 h (padrão do ticket escalado) |
| P4 | baixa | 4 h |

- O prazo conta a partir da escalação e termina na primeira mensagem do analista.
- Os números são nossos, não da CloudWalk, e ficam numa tabela editável. As regras da fatia seguinte
  mudam a prioridade (por exemplo, valor alto vira P1).
- Descartado: três níveis (menos granular); deixar prioridade e SLA humano para a fatia de regras (o painel
  nasceria sem ordem por urgência).

**H4. O analista puxa o próximo ticket.**
- "Pegar o próximo" entrega o ticket mais urgente das filas do analista, com lock para que dois analistas
  nunca peguem o mesmo.
- "Mais urgente" é o prazo de SLA mais próximo: combina prioridade e tempo de espera numa só ordem, como o
  playbook pede ("peso da prioridade + envelhecimento, calculado no momento de puxar").
- Descartado: distribuição automática pela plataforma (exige presença, capacidade e redistribuição).

**H5. Os vigias periódicos rodam no Sidekiq com a gem `sidekiq-cron`.**
- O Sidekiq gratuito não agenda jobs periódicos. A `sidekiq-cron` declara o agendamento num só arquivo e
  roda dentro do processo do Sidekiq, usando o Redis já previsto no ADR 0002 (D3).
- O vigia do agente roda a cada 5 s. Cada execução é idempotente, então uma execução duplicada ou perdida
  não muda o resultado.
- Descartado: job que se reagenda sozinho (sem dependência nova, mas uma falha no momento errado duplica ou
  quebra a corrente de execuções).

**H6. O limite de silêncio do agente é 30 s, e a meta passa a ser escalar em até ~40 s.**
- A plataforma escala quando o cliente espera o agente há mais de 30 s (`AGENT_SILENCE_TIMEOUT_SECONDS`).
  Somando o ciclo do vigia (5 s) e o atraso do agendador, a escalação acontece entre 30 e cerca de 40 s.
  Na pilha real, medida uma vez, levou 37,4 s.
- Substitui o item "agente em falha escala em ≤ 30 s" do ADR 0002 (D12) pela meta **≤ 40 s**, com 30 s de
  limite. O piloto de carga confirma ou recalibra o número.
- Por quê: um limite menor (20 s) cumpriria a meta antiga, mas escalaria cedo demais um agente real que
  demora, como um LLM que leva mais de 20 s para responder.
- Descartado: limite de 20 s.

## Consequências

- O mock do agente passa a escalar parte das conversas, de forma determinística, na taxa configurada
  (30% e 60% no experimento, ADR 0002, D6).
- Os gatilhos "cliente pediu humano", "frustração alta" e "valor acima do limite" dependem de fatos de
  regras e de LLM e entram nas fatias seguintes. Nesta fatia a plataforma força a escalação só quando o
  agente falha ou fica em silêncio.
