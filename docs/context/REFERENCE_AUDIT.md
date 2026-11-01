# Auditoria seletiva dos projetos anteriores

Data: 2026-11-01

## Método

Foram inspecionados, sem alterar seus worktrees, os projetos BTG LLM Debate, Suno Academy
Finance, NVIDIA Services RAG, Inteli Tractian, LigaAI e Inteli Academy AI Weekly. A seleção abaixo
prioriza práticas com evidência em código, testes, evals ou histórico; volume de arquivos e uso de
"agentes" não foram tratados como sinais de qualidade.

## Padrões aprovados para reutilização condicional

| Origem | Padrão útil | Quando adotar aqui |
|---|---|---|
| Suno | Domínio separado de provedores, API e apresentação | Quando o TAPI revelar regras de negócio estáveis |
| Suno | Suíte determinística/offline e provedores falsos | Desde o primeiro fluxo que dependa de rede ou LLM |
| Suno | Casos de eval versionados com motivo e fronteiras explícitas | Se houver comportamento de IA sujeito a julgamento |
| Suno | Vocabulário de domínio e decisões registradas | Quando os termos do TAPI forem estabilizados |
| NVIDIA | Testes de integridade: imports, CLIs, caminhos legados e arquivos proibidos | Após a estrutura de pacotes existir |
| NVIDIA | Pipelines com estado e nós de responsabilidade clara | Somente se houver fluxo multi-etapa real |
| Tractian | Golden cases, holdout separado e testes de estabilidade | Se a solução precisar comparar agentes/modelos |
| Tractian | Contratos de API e cenários esperados versionados | Se houver integração externa ou simulador |
| Figma/AI Weekly | Segurança operacional e automação explícita | Quando existirem jobs, webhooks ou publicação |
| BTG | Configuração simples e troca de modelos atrás de uma fronteira | Se múltiplos provedores forem um requisito comprovado |

## Padrões que não serão copiados por padrão

- Catálogos grandes de skills genéricas ou sobrepostas: aumentam roteamento e contexto sem provar valor.
- Múltiplos ambientes, frontends ou gerenciadores de dependência antes de uma necessidade concreta.
- RAG, LangGraph, agentes múltiplos ou fallback de modelos apenas porque apareceram em outro case.
- Diretórios `legacy/`, documentos extensos ou dados gerados sem política de retenção e dono claro.
- CI copiado entre stacks, testes que exigem chaves reais e demos tratadas como evidência de qualidade.
- Integrações, scrapers e automações sem contrato, limites, observabilidade e estratégia de recuperação.

## Decisão para este repositório

Começar com governança e contexto, não com uma stack. Depois do TAPI, cada padrão candidato deve
responder: qual requisito atende, qual complexidade adiciona, como será testado e qual é a opção
mais simples que preserva o resultado.
