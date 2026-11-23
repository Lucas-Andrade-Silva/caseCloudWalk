# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Analista de atendimento** (primário): passa o dia na fila de tickets escalados pela IA, pega o próximo de
  prazo mais curto, lê o brief e a memória do cliente, conversa e fecha com resolução. Uso contínuo, denso,
  com teclado.
- **Operação**: configura filas, equipes e regras de roteamento sem depender de desenvolvimento, simula antes
  de publicar e acompanha o mapa vivo e os painéis.
- **Cliente final** (simulado): conversa pelo app, WhatsApp ou e-mail das marcas InfinitePay (BR) e JIM (US).
- **Banca da CloudWalk** (avaliação): engenheiros e gestores que veem a plataforma projetada numa
  apresentação. Confirmado pelo dono: o uso real vem primeiro, e a interface também precisa impressionar
  projetada.

## Product Purpose

Help desk AI-first e multimarca: a IA atende primeiro, e a plataforma tria, prioriza e distribui entre IA e
humanos, escala com resumo e contexto, lembra o cliente entre contatos e audita cada decisão. Sucesso: nenhuma
mensagem perdida, escalação no tempo certo, analista que entende o caso sem reler a conversa, e operação que
muda o roteamento sozinha.

## Positioning

Uma plataforma que prova o que faz: cada mensagem tem trace ponta a ponta, cada decisão da IA e das regras é
auditável e explicável, e picos de tickets parecidos viram um incidente em segundos, não numa revisão semanal.

## Operating Context

Projeto acadêmico (Inteli) para a CloudWalk, entrega em 2026-11-27, desenvolvido por uma pessoa com um agente
de IA. Dados sintéticos apenas (LGPD). Roda local em Docker Compose. Ver `docs/TAPI_cloudwalk.pdf`,
`docs/PLAYBOOK.md` e `docs/decisions/`.

## Capabilities and Constraints

- Telas: entrada por token, painel do analista, chat do cliente simulado, editor da operação (filas, equipes,
  regras), mapa vivo; em construção: Modo Incidente e "Por que a IA decidiu" (ADR 0009).
- Stack existente: React 19, Vite, TypeScript, Tailwind 4, Radix; Rails 8 API, Kafka, Sidekiq, ActionCable.
- Tema claro (ADR 0009, W8), denso nas telas de trabalho. Português do Brasil na interface.

## Brand Commitments

- Visual atual (dono, 2026-11-22, ADR 0009 W8): tema claro de painel de atendimento, a partir de uma referência
  dada pelo dono (Kirridesk, da Fikri Studio): fundo cinza, cards brancos, verde como ação, barra lateral clara.
  Substituiu o visual escuro da CloudWalk escolhido antes no mesmo dia. Inter no texto; IBM Plex Mono só em
  código e identificadores. Não usar logotipo ou nome de outra empresa.
- InfinitePay e JIM aparecem só como identificação de qual marca é o ticket; não há guia oficial dessas cores.

## Evidence on Hand

Dados sintéticos de desenvolvimento, piloto de carga (`docs/research/2026-11-16-piloto-de-carga.md`), traces e
painéis reais da plataforma. Não há clientes, depoimentos ou métricas de produção: não inventar.

## Product Principles

1. Provar, não prometer: tudo que a interface afirma vem de dado real da plataforma.
2. O analista não relê a conversa: contexto e próximo passo na primeira olhada.
3. A IA explica o que decidiu; o humano decide o que importa.
4. Crise é rotina: o pior dia (pico, queda) precisa ser o melhor momento da interface.

## Accessibility & Inclusion

WCAG AA de contraste em todo texto, foco visível, uso completo por teclado e respeito a movimento reduzido
(confirmado pelo dono).
