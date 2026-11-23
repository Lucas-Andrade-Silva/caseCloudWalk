# Experimento oficial enxuto (2026-11-22/23)

Escopo do ADR 0009, W6 (versão enxuta do playbook §9). Resultados por rodada, com os invariantes e o hash de
cada ledger, em [`experimento-2026-11-23/`](experimento-2026-11-23/).

## Pergunta e hipótese (escritas antes de rodar)

A plataforma mantém as garantias sob pico combinado com falhas? Hipótese: com 30% de webhooks reenviados fora
de ordem, a rampa até 50×, o Kafka parado 60 s e o agente lento, os 4 invariantes (§3.7) se mantêm. A latência
ponta a ponta p99 fica abaixo de 1 s em 10×, e o atraso acumulado se recupera em menos de 5 min. É refutada se
houver perda, duplicata, quebra de ordem ou conversa órfã.

## Método

- **Pilha:** modo de produção (`compose.pilot.yaml`), com banco e Kafka próprios, API em 4 × 5 e LLM desligada
  (`LLM_MODE=off`).
- **Gerador:** k6 2.3.0 (`experiment/k6/webhooks.js`), taxa de chegada fixa (modelo aberto) e 1× = 5 mensagens/s.
  - 30% de reentregas fora de ordem.
  - Cerca de 8 mensagens por cliente.
  - Semente fixa por rodada.
  - Limitado a 2 CPUs na mesma máquina.
- **Cenários:** 3 rodadas de cada (`scripts/experiment/run.ps1`).
  - S1: rampa 1× (60 s) → 10× (180 s) → 50× (120 s) → 1× (60 s).
  - S2: 10× por 240 s, com o Kafka pausado (`docker pause`) 60 s no meio.
  - S3: 10× por 240 s, com o agente em caos (latência de 200 a 2000 ms e 5% de silêncio).
- **Medidas** (`experiment:report`), em percentis pelo posto mais próximo:
  - ACK do webhook;
  - ponta a ponta, da mensagem do cliente gravada até a resposta do agente gravada;
  - respondidas × escaladas;
  - atraso do outbox na janela da fase.
- **Invariantes:** `invariants:check` sobre o ledger de cada rodada.

## Resultados

Invariantes: **OK nas 9 rodadas**. Nenhuma mensagem perdida, duplicada, fora de ordem ou órfã, nenhum webhook
recusado e nada na fila de mortos.

| Cenário e fase | Enviado (msg/s) | ACK p99 | Ponta a ponta p50 / p99 | Escaladas / respondidas |
|---|---|---|---|---|
| S1, 1× | 5,0 | 73–425 ms | 259–404 ms / 426–441 ms¹ | 1–3 / ~300 |
| S1, 10× | 49,5–49,7 | 218–223 ms | 602–636 ms / **1,18–1,25 s** | ~2.150 / ~6.750 |
| S1, 50× (pedido 250) | **186–189** | 8,6–8,9 s | 80–92 s / 110–119 s | 19–21 mil / 1–3,7 mil |
| S2, 10× com Kafka parado 60 s | 49,6 | 119–141 ms | 588–657 ms / 20,6–24,2 s | ~10.760 / ~1.140 |
| S3, 10× com agente em caos | 49,6 | 153–166 ms | 1,53–1,57 s / 14–20 s | 7,4–7,5 mil / 4,4–4,5 mil |

¹ A primeira rodada de S1 teve um p99 de 25 s no 1×: aquecimento da pilha recém-subida.

- **Kafka (S2):** com o Kafka parado, o webhook seguiu aceitando tudo (ACK p99 ≤ 141 ms). O outbox esvaziou
  **53 a 59 s** depois de o Kafka voltar, com o gerador ainda em 10×.

## Conclusões

1. **Correção:** a hipótese se mantém. Os invariantes valeram em pico, com reentregas, com o Kafka parado e com
   o agente em caos.
2. **Latência em 10×:** a meta de p99 < 1 s foi **refutada por pouco** (1,18 a 1,25 s nesta máquina). O p50
   fica em torno de 0,6 s.
3. **Recuperação:** atendida. O atraso do Kafka se recuperou em menos de 1 min (meta: < 5 min).
4. **Ponto de ruptura:** entre 10× (sustentado) e cerca de 37× (187 msg/s, o máximo que o gerador entregou).
   - Em 187 msg/s, o ACK sobe para ~8 s e a resposta do agente para mais de 1 min.
   - O vigia escala os clientes em vez de perdê-los.
   - Nesta máquina, a referência segura é **10×**.
5. **Agente lento (S3):** um agente de 0,2 a 2 s por mensagem, num consumidor só, não acompanha 10×. A plataforma
   protege o cliente passando para humanos (~62% escalados). Antes de produção, é preciso paralelizar o
   consumo do agente.

## Limitações

- Um host só (Windows, Docker Desktop), com o gerador disputando CPU com a pilha.
- Kafka de 1 nó.
- Mock de agente; dados sintéticos; LLM desligada.
- Fases curtas: 2 a 4 min, quando o playbook pede de 5 a 15.
- Rodadas seguidas no mesmo banco.
- No 50×, o gerador não alcançou a taxa pedida.
- A ponta a ponta inclui o tempo do mock.
- Os resultados são relativos e não indicam capacidade de produção.
