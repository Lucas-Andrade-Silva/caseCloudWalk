# Sistema de contexto

Este diretório reduz a necessidade de reexplicar o projeto em cada chat sem despejar todo o
histórico no contexto do modelo.

## Como funciona

- `STATE.md` é a memória operacional curta: estado, decisões vigentes, próximos passos e bloqueios.
- `REFERENCE_AUDIT.md` registra o que foi aprendido nos projetos anteriores e só é consultado
  quando uma decisão arquitetural realmente precisa dessa comparação.
- Decisões duráveis ficam em `../decisions/`; PRs e Git preservam o histórico de execução.

Ao encerrar uma mudança material, atualize `STATE.md` substituindo fatos obsoletos. Não acrescente
um diário de sessão e não copie detalhes já registrados em ADRs ou PRs.
