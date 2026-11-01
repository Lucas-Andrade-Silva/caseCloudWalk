# Estado do projeto

Atualizado em: 2026-11-01

## Fase atual

Fundação de engenharia. O repositório remoto começou vazio e ainda não recebeu o TAPI nem a
definição do problema de produto.

## Verdades vigentes

- Desenvolvimento solo com Codex como parceiro de implementação e revisão.
- Toda mudança de conteúdo usa branch, pull request, checks e revisão independente.
- `AGENTS.md` contém regras duráveis; este arquivo contém apenas o estado mutável.
- Projetos anteriores são referências, não templates para cópia integral.
- Stack, arquitetura de produto, modelos, provedores, dados e infraestrutura estão indefinidos.

## Entregue nesta fase

- Regras de engenharia e Git em `AGENTS.md`.
- Memória dinâmica e econômica em `docs/context/`.
- Auditoria comparativa em `docs/context/REFERENCE_AUDIT.md`.
- Skills locais `$ship-change` e `$review-pr`.
- Template de pull request e proteção básica contra arquivos locais/segredos.

## Próximos passos

1. Receber e registrar o TAPI como fonte do problema e dos critérios de sucesso.
2. Separar fatos, hipóteses, restrições, riscos e perguntas em aberto.
3. Fazer ideação crítica antes de escolher arquitetura ou stack.
4. Definir objetivos mensuráveis, não objetivos e plano de fases.
5. Criar o primeiro esqueleto ponta a ponta somente após a decisão arquitetural.

## Questões em aberto

- Problema, usuários, entregáveis e critérios de avaliação do TAPI.
- Restrições de dados, privacidade, integração, custo e prazo.
- Necessidade real de agentes, RAG, modelos, evals e interface.
- Checks técnicos que substituirão o gate genérico quando a stack for definida.

## Bloqueio operacional conhecido

O GitHub remoto era vazio. Um commit local vazio inicializa `main`, mas o primeiro push direto
à branch padrão exige autorização excepcional; depois disso, todo conteúdo seguirá por PR.
