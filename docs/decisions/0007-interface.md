# ADR 0007 — Interface: direção visual, componentes, grafo e cluster

- Status: aceito (I1 a I4 pelo dono em 2026-11-16; I5 e I6 propostas pelo agente, aguardam o dono)
- Contexto: ADR 0002 (D2 React com Vite, D7 mapa vivo, tempo real por ActionCable com polling de reserva,
  Vitest com Testing Library); playbook §2.4 ("super intuitiva") e §7 (mapa vivo).

## Decisões

**I1. Direção visual: escuro, denso, no estilo do Linear.** Fundo escuro, tipografia pequena e precisa,
muita informação por tela, atalhos de teclado. Um tema só (sem troca de tema nesta entrega).

**I2. Componentes: Tailwind com Radix, no padrão shadcn.** Primitivos acessíveis do Radix, estilo próprio em
Tailwind, código dos componentes dentro do projeto. Cada primitivo do Radix entra quando uma tela precisar.

**I3. Mapa vivo: d3-force com canvas próprio.** A física vem do d3-force; o desenho (anéis, pulso, bolha
"+N") é nosso, em canvas. A lógica do mapa fica em funções puras testadas.

**I4. Cluster do mapa: tags das regras.** Enquanto não há categoria por LLM, os tickets se agrupam pelas tags
que o motor de regras atribui. **Em aberto (perguntar ao dono antes do mapa):** onde fica um ticket sem tag e
como desempatar um ticket com várias tags.

## Propostas (aguardam o dono)

**I5. TypeScript**, pela regra de fronteiras tipadas do `AGENTS.md`. Fica na 6.0, porque o typescript-eslint
ainda não suporta a 7.

**I6. Frontend em container**, como o resto: serviço `web` (Vite em modo de desenvolvimento, porta 5173) e
`web-test` (gate), com `node_modules` em volume. O Vite repassa `/api` e `/webhooks` para a API, então não há
CORS a configurar.

## Chat do cliente simulado (dono, 2026-11-16)

**I7. Simulador de canal no backend.** O navegador não guarda o segredo do webhook. Rotas `/api/simulator`
fazem o papel do canal: enviam pela mesma ingestão do webhook (`Ingestion::ReceiveMessage`) e leem a conversa
do cliente. Só existem com `CHANNEL_SIMULATOR_ENABLED=true` (ligada no Compose de desenvolvimento, desligada
no piloto de produção); desligadas, respondem 404.

**I8. Página própria, sem login**, em `#/cliente`, como um cliente abriria. Consequência aceita: com o
simulador ligado, quem souber o identificador de um cliente sintético lê a conversa dele. Por isso a chave
nunca é ligada fora de desenvolvimento e demonstração.

**I9. Visual neutro**, no tema da plataforma, com marca e canal indicados. Não imita apps de terceiros.

## Editor da operação (dono, 2026-11-16)

**I10. Regras com construtor visual de um nível.** Cada regra é um cartão: nome, condições (todas ou
qualquer uma; fato, operador e valor) e ações (fila, prioridade, tags), com a ordem ajustável (a primeira que
casa vence). Regras com aninhamento mais fundo aparecem só para leitura e continuam editáveis pela API. Fatos
e operadores vêm do catálogo do backend (`GET /api/ops/rules/catalog`), sem cópia no frontend.

**I11. A tela de filas também gerencia as equipes**: criar e renomear filas, trocar a equipe dona, criar
equipes e adicionar ou remover analistas (`GET /api/ops/analysts`).

## Dependências e versões

Versões exatas, cada uma publicada há pelo menos 14 dias na data da escolha (risco de cadeia de
suprimentos): React 19.1, Vite 8.3, TypeScript 6.0, Vitest 5.1, Testing Library, jsdom, Tailwind 4.3,
ESLint 10 com typescript-eslint. Radix e d3-force entram com a primeira tela que os usar.

## Consequências

- O gate do frontend é testes, checagem de tipos e lint, registrado no `STATE.md`.
- O tema escuro único simplifica o trabalho; trocar de tema depois exige revisar os tokens de cor.
