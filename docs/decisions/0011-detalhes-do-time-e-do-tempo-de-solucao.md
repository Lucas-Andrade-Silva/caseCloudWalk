# ADR 0011 — Detalhe do analista e detalhe do tempo de solução

- Status: aceito em 2026-11-25 (pedido do dono). Complementa o ADR 0010 (home em cards).
- Contexto: na home, os cards "Desempenho do time" e "Operação dos tickets" listam analistas e o card "Tempo de
  solução" mostra só uma mediana. O dono pediu que clicar num analista mostre o que ele está fazendo (sem as
  respostas dele) e que o tempo de solução abra com mais detalhe.

## Decisões

**D1. Clicar num analista abre `#/analista/:id`.** Na tabela do card "Desempenho do time" a linha inteira
abre o analista; em "Operação dos tickets" abre pelo nome do analista. Essas linhas ficam acima do link do card
(que cobre o card todo, ADR 0010); o resto do card continua abrindo o detalhe do card.

**D2. O detalhe do analista mostra só números, nunca o texto das conversas dele.** Janela dos últimos 7 dias,
como o Painel: recebidos (tickets escalados que são dele), respondidos, resolvidos por ele, em atendimento agora,
quantidade de mensagens enviadas, SLA da primeira resposta e tempo médio dela, tempo de solução (média e
mediana), assuntos mais tratados (categoria que a LLM deu ao ticket), marcas e a série por dia.

**D3. Escopo.** A operação abre qualquer analista. O analista abre colegas que atendem pelo menos uma marca em
comum com ele e vê só os tickets das marcas dele; o resto responde 404, sem dizer que existe. `GET
/api/dashboard/analysts/:id`.

**D4. `#/solucao` detalha o tempo de solução** (card "Tempo de solução"): mediana, média, quanto cabe na meta
de 8 h, faixas (até 15 min, 15 min a 1 h, 1 a 8 h, 8 a 24 h, mais de 24 h), IA contra humano, por marca, por
assunto, mediana por dia e os cinco tickets mais lentos. Mesmo escopo do Painel (analista: suas marcas;
operação: todas). `GET /api/dashboard/resolution`.

**D5. Primeira resposta em tempo médio.** O número do tile "Primeira resposta humana" e a legenda do card "SLA da
primeira resposta" passam de mediana para média (pedido do dono); `first_reply.median_seconds` virou
`first_reply.mean_seconds`.

**D6. O card "Desempenho do time" abre `#/time`.** Tela própria (e não o Painel): totais do time (recebidos,
respondidos, resolvidos, em atendimento, SLA, tempo médio da primeira resposta), uma linha por analista com os mesmos
números mais o tempo de solução e o assunto principal, assuntos mais tratados e série diária. Cada linha abre o
analista (D1). `GET /api/dashboard/team`, com o escopo de D3. O card avisa "Clique num analista para ver os detalhes".

**D7. O card "Operação dos tickets" abre `#/tickets`.** Tela própria (e não o Mapa): contagens (pedem gente, sem
analista, fora do prazo, parados), por prioridade e por marca, a lista completa do que pede gente (até 100, com
situação, analista, espera e prazo) e a dos parados há mais de 3 dias (até 20). `GET /api/dashboard/tickets`.

## Limites conhecidos

- "Recebidos" e "resolvidos" usam o analista atual do ticket (`assignee_id`); a plataforma não guarda o histórico
  de reatribuições.
- "Mensagens enviadas" conta as mensagens de analista nos tickets que são dele, sem saber quem escreveu quando o
  ticket mudou de mãos.
- O assunto vem de `llm_facts.category`; sem LLM (ou se ela falhou) o ticket entra como "Sem categoria".
- A plataforma não coleta CSAT nem presença (ADR 0010, H4): a qualidade do analista é o SLA da primeira resposta.
