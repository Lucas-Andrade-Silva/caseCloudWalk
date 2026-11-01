# ADR 0001 — Fluxo de engenharia e contexto

- Status: aceito
- Data: 2026-11-01

## Contexto

O projeto será desenvolvido por uma pessoa em conversas diferentes com Codex. Sem uma fonte curta
de estado, cada chat exige reexplicar o projeto; sem separação entre autoria e revisão, o agente
pode confirmar as próprias suposições. O repositório começou vazio e o produto ainda aguarda o TAPI.

## Decisão

1. Todo conteúdo nasce em branch e chega à `main` por pull request.
2. A autoria e a revisão usam conversas ou tarefas independentes.
3. O merge exige checks relevantes e veredito `APPROVE` da skill `$review-pr`.
4. `AGENTS.md` mantém regras duráveis; `docs/context/STATE.md` mantém o snapshot mutável.
5. O estado é curto e substitutivo. Git, PRs e ADRs guardam o histórico detalhado.
6. Arquitetura e stack só serão decididas após a leitura crítica do TAPI.

## Consequências

- Novos chats começam com contexto suficiente e baixo custo de tokens.
- A revisão continua independente mesmo em um projeto solo.
- Há um pequeno custo de manter o estado e os gates atualizados.
- O primeiro push vazio para criar a base `main` é uma exceção operacional, sem conteúdo de projeto.
