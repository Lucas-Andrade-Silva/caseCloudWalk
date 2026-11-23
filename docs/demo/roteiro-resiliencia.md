# Roteiro da demo: incidente, explicação da IA e resiliência ao vivo

Roteiro de 8 a 10 minutos para a banca (ADR 0009, W1). Tudo roda na pilha local, com dados sintéticos. Cada
afirmação na tela vem do banco ou de um comando; nada é slide.

## Antes de começar (10 min antes)

1. Docker no ar. Se o Docker Desktop não abrir depois de uma queda, ver "Bloqueios e riscos" em
   `docs/context/STATE.md` (arquivos `.sock` presos).
2. Pilha com o Groq e a observabilidade:
   `$env:LLM_MODE="live"; $env:OTEL_TRACES_EXPORTER="otlp"; docker compose --profile obs up -d`
   (ou `LLM_MODE=live` no `.env`). Sem chave ou sem rede: `LLM_MODE=replay` usa as respostas gravadas.
3. Banco limpo: `docker compose exec api bundle exec rails demo:reset` (cria a cliente `demo-marina`, com dois
   atendimentos anteriores). Recarregue as abas abertas.
4. Abas no navegador, todas em `http://127.0.0.1:5173` (nunca `localhost`):
   - Ana (analista): `#/painel`;
   - chat do cliente: `#/cliente`;
   - Grafana: `http://127.0.0.1:3030` (painel do help desk);
   - terminal PowerShell na raiz do repositório.
5. Ensaio do terminal: `./scripts/demo/resiliencia.ps1 -Cenario kafka -Mensagens 40 -QuedaSegundos 40` precisa
   terminar com "INVARIANTES OK". Depois rode o `demo:reset` de novo.

## 1. Painel (1 min)

Mostre o Painel da Ana: abertos agora, criados e resolvidos hoje contra ontem, primeira resposta humana, canais e
quem resolveu (IA ou humano). Fala: "todo número aqui é uma consulta ao banco; não há estimativa".

## 2. Memória do cliente (1 min)

A cliente sintética Marina Souza (`demo-marina`) já tem dois atendimentos anteriores. O chat do cliente gera uma
identidade nova a cada conversa, então a mensagem dela sai pelo simulador, com o id fixo:
`curl -X POST http://127.0.0.1:5173/api/simulator/messages -H "Content-Type: application/json" -d '{"brand":"infinitepay","channel":"whatsapp","customer":{"external_id":"demo-marina","name":"Marina Souza"},"text":"a maquininha travou de novo, preciso de ajuda [escalar]"}'`.
Na fila da Ana, "Pegar o próximo": o painel lateral mostra o brief da IA e os dois atendimentos anteriores.

## 3. Por que a IA decidiu (1 min)

Na mesma conversa, aba "Por que a IA decidiu": o texto que a LLM recebeu (dados pessoais redigidos), a regra que
casou com a versão, a categoria com a confiança, a escalação e o brief. Se a observabilidade estiver no ar, o
link abre o trace ponta a ponta no Jaeger.

## 4. Modo Incidente (2 min)

No chat do cliente, "Simular pico": 6 clientes sintéticos com a mesma reclamação. Em segundos:
- a barra lateral e o topo da fila mostram o incidente, com título e rascunho escritos pela LLM;
- no mapa vivo, os tickets do pico saem do grupo de origem e formam um grupo laranja.
Na fila, "Responder a todos", revise o rascunho e confirme: os tickets fecham de uma vez e o aviso mostra
quantos.

## 5. Resiliência ao vivo (3 min)

No terminal: `./scripts/demo/resiliencia.ps1 -Cenario kafka`. Enquanto roda, alterne para o Grafana e o Painel.
- Com o Kafka fora, o webhook continua aceitando mensagens (ACK 201): elas ficam no outbox, que cresce na tela.
- Clientes que esperam o agente há mais de 30 s vão para a fila humana: ninguém fica sem resposta.
- Ao religar o Kafka, o outbox esvazia sozinho; nada vai para a fila de mortos.
- O script confere o ledger da rajada: 0 perdidas, 0 duplicadas, ordem preservada, um ticket aberto por
  cliente. Termina com "INVARIANTES OK".
Variante: `-Cenario agente` derruba o agente; todos os clientes da rajada passam para humanos pelo vigia.

Resultados medidos ao preparar este roteiro (2026-11-22, pilha de desenvolvimento):

| Cenário | Mensagens (reentregas) | Queda | Outbox no pico | Perdidas | Duplicadas | Escaladas pelo vigia |
|---|---|---|---|---|---|---|
| Kafka | 60 (9) | 60 s | 88 | 0 | 0 | 57 |
| Kafka | 40 (8) | 40 s | — | 0 | 0 | 36 |
| Agente | 40 (5) | 45 s | 0 | 0 | 0 | 40 |

As latências da pilha de desenvolvimento não valem como medida (o experimento oficial roda em produção).

## Vídeo de reserva

Grave o roteiro inteiro uma vez, com a pilha estável, para o caso de algo falhar na hora (por exemplo, com a
Barra de Jogo do Windows: Win+Alt+R). O vídeo é do dono; não fica no repositório.

## Se algo der errado

- Mapa com tickets que já não existem: recarregue a página (o reset não avisa o mapa aberto).
- LLM sem resposta: a plataforma segue com regras e templates; o incidente nasce com título de template.
- Script parado no meio: `docker compose start kafka mock-agent` religa o que estiver fora.
