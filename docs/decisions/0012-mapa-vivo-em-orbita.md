# ADR 0012 — Mapa vivo em órbita, com zoom nos grupos

- Status: aceito em 2026-11-25 (pedido do dono). Substitui o desenho em nuvem com física (d3-force) do ADR 0007
  (I3); mantém retrato, eventos ao vivo, risco de prazo e Modo Incidente.
- Contexto: o dono não gostou dos aglomerados do mapa vivo e prefere o jeito orbital do card da tela inicial
  (ADR 0010, H6).

## Decisões

**O1. Visão geral: cada ponto da órbita é um grupo.** Os grupos (o mesmo agrupamento de antes: primeira tag, senão a
fila; tickets de um incidente aberto formam um grupo laranja próprio) são círculos que giram devagar em até três
órbitas em volta de um centro. O círculo cresce com a quantidade de tickets (raio proporcional à raiz da
quantidade, com teto) e mostra o número dentro e o nome embaixo. Os maiores ficam nas órbitas de dentro.

**O2. Clicar num grupo dá zoom e abre os tickets dele.** A visão geral some com um zoom e o grupo vira o centro;
cada ticket é um círculo que gira em órbitas em volta dele (os mais urgentes e antigos mais perto). "Todos os
grupos" (ou Esc) volta. Se o grupo esvaziar, volta sozinho. No zoom, o analista clica num ticket para abrir o
atendimento; a operação só observa (como antes).

**O3. Mesma leitura visual dos tickets.** Cor: o grupo. Tamanho do ponto: a prioridade. Anel: esperando humano ou
com humano. Pulso vermelho: prazo perto de vencer (no círculo do grupo, quando há ao menos um ticket em risco) ou
agente calado há 20 s. Anel laranja tracejado: ticket de incidente. Ticket novo cresce ao chegar.

**O4. Tudo parte do mesmo estado ao vivo.** O desenho é SVG (acessível por teclado: cada grupo é um botão com
nome "grupo, N tickets"), com a geometria em funções puras (`orbit.ts`). O teto de ~500 tickets desenhados
continua. A rotação é CSS e para com `prefers-reduced-motion`.

**O5. O incidente aberto é o centro do mapa, e não é clicável (pedido do dono).** Os tickets de um incidente
aberto saem dos grupos em órbita e viram um círculo laranja no centro, com a contagem; várias incidências somam
e o centro diz "N incidentes". Ao lado, o painel "Incidentes abertos" (também sem clique) traz marca, assunto,
título, há quanto tempo está aberto, quantos tickets, esperando humano, com humano, com a IA, em risco de prazo,
urgentes (P1) e há quanto espera o mais antigo. O total do mapa e a lista de grupos continuam contando o incidente.
Não há zoom nos tickets de um incidente; quem age sobre ele usa o aviso da fila ("Responder a todos"). Na tela
inicial, o card "Modo Incidente" também não é link e se lê de relance (pedido do dono): a situação em uma palavra,
uma frase de motivo e três números (incidentes abertos, prazo em risco, entradas da última hora). O detalhe por
incidente fica no painel do mapa.

## Consequências

- Some a física (d3-force) do mapa; a dependência continua só se outra tela usar.
- Os grupos vizinhos não se sobrepõem: a geometria garante o espaço de cada órbita (testado). Com mais grupos
  que o espaço das três órbitas, os excedentes vão para a última e podem encostar.
- Dentro do zoom, grupos com centenas de tickets ficam com pontos pequenos (o desenho encolhe para caber).
