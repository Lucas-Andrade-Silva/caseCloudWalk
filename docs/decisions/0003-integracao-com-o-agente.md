# ADR 0003 — Integração com o agente fiel ao TAPI, ticket único e resposta atrasada

- Status: aceito. Substitui os trechos indicados do ADR 0002 e do playbook.
- Data: 2026-11-15
- Fonte: conversa de decisão de 2026-11-15, na abertura da fatia 02. O dono escolheu cada item abaixo.

## Contexto

Ao tirar os contratos da fatia 02 direto do TAPI, apareceu um conflito. O TAPI diz que "um broker consome
do help desk as mensagens de webhooks e as repassa ao agente por meio de um tópico Kafka; as respostas
seguem o caminho inverso". O ADR 0002 e o playbook tinham registrado outra ordem: a plataforma publicava
direto no Kafka e o broker ficava entre o Kafka e o agente. A rubrica pesa a aderência ao desenho fornecido
e a robustez entre plataforma, webhooks, broker e atendente.

O playbook também falava em "ticket" e em "conversa" sem dizer se eram a mesma entidade, e deixava
pendente a política para resposta do agente com `in_reply_to_seq` defasado e a linguagem do mock.

## Decisões

**E1. A integração segue a ordem do TAPI.**

```
Plataforma (Postgres + outbox)
   │  webhook assinado (HMAC)
   ▼
Broker (nosso, sem estado)
   │  Kafka: helpdesk.messages
   ▼
Agente (mock)
   │  Kafka: agent.replies
   ▼
Broker
   │  API da plataforma, como usuário bot
   ▼
Plataforma
```

- O relay do outbox passa a **entregar webhooks ao broker**, em vez de publicar no Kafka. O outbox, a ordem
  por `id`, o lock de instância única e o backoff continuam iguais.
- O broker é um serviço próprio e **sem estado**: valida a assinatura, publica no Kafka e só responde 2xx
  depois da confirmação do Kafka. Na volta, consome `agent.replies` e chama a API da plataforma com o token
  do usuário `bot`; só confirma o offset depois da resposta da plataforma.
- A plataforma **não fala com o Kafka**. O Kafka fica só na borda do agente, como o D1 do ADR 0002 já dizia.
- A entrega continua at-least-once nas duas direções. A plataforma absorve duplicatas pelo `agent_turn_id`
  (`processed_events`); o agente recebe o `event_id` de cada mensagem.
- Descartado: manter a ordem do playbook (diverge do TAPI); híbrido com Kafka interno e despachante (dois
  saltos a mais para construir e testar no prazo).
- Consequência: o caminho lateral do enriquecimento por LLM (`ticket.created` → `ticket.enriched`), que o
  playbook previa no Kafka, precisa de novo desenho na fatia de LLM. **Pendente, perguntar ao dono.**

**E2. Ticket e conversa são uma entidade só: o ticket.**
- O ticket contém as mensagens, o modo (`ai`, `pending_human`, `human`, `closed`), o `handoff_epoch` e o
  contador de `seq`. Um contato novo depois do fechamento abre outro ticket; a memória liga os anteriores.
- Existe no máximo um ticket aberto por cliente, marca e canal. A chave de partição no Kafka é o `ticket_id`.
- Onde o ADR 0002 e o playbook dizem `conversations` ou `conversation_id`, leia `tickets` e `ticket_id`.
  A linha do tempo mantém o nome `conversation_events`.
- Descartado: conversa contínua com vários tickets dentro (dobra o modelo, as regras de ordem e os testes).

**E3. Resposta atrasada do agente é entregue e sinalizada.**
- Se o agente responde à mensagem `n` e o cliente já enviou a `n+1`, a resposta chega ao cliente e fica
  marcada como atrasada (`stale`) na mensagem e na linha do tempo.
- Continua valendo o que já estava decidido: resposta com `handoff_epoch` diferente ou com o ticket fora do
  modo `ai` é **descartada e auditada**.
- Descartado: descartar a resposta atrasada (um cliente que envia mensagens em sequência poderia nunca
  receber resposta).

**E4. Mock do agente e broker em Ruby**, cada um no seu diretório, com imagem e testes próprios.

## Consequências

- Parte da fatia 01 muda de lugar: o Karafka sai do backend e vai para o broker e para o mock.
- O gate de testes passa a ter um comando por componente (backend, broker e mock).
- O formato real das mensagens da CloudWalk no Kafka continua desconhecido; o envelope é nosso e será
  validado no onboarding.
