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

## Dependências e versões

Versões exatas, cada uma publicada há pelo menos 14 dias na data da escolha (risco de cadeia de
suprimentos): React 19.1, Vite 8.3, TypeScript 6.0, Vitest 5.1, Testing Library, jsdom, Tailwind 4.3,
ESLint 10 com typescript-eslint. Radix e d3-force entram com a primeira tela que os usar.

## Consequências

- O gate do frontend é testes, checagem de tipos e lint, registrado no `STATE.md`.
- O tema escuro único simplifica o trabalho; trocar de tema depois exige revisar os tokens de cor.
