# ADR 0009 — Modo Incidente, "Por que a IA decidiu", resiliência ao vivo e redesign

- Status: aceito em 2026-11-22 (escolhas do dono: W1, W3, W5 e W8); W2, W4 e W6 seguem as opções
  recomendadas, adotadas sem resposta explícita do dono e reversíveis.
- Contexto: pesquisa com três agentes em 2026-11-22. O *Trends* da Intercom roda uma vez por semana, e o
  vínculo de incidentes da Zendesk é manual, ticket a ticket. A Intercom lançou o *Fin Operator* só para
  auditar decisões da IA. A interface atual não carrega a fonte, não tem ícones, tem metadados com contraste
  abaixo do AA e componentes refeitos em cada tela.

## Decisões

**W1. Recursos de demonstração: Modo Incidente + "Por que a IA decidiu" + resiliência ao vivo** (dono).
- Modo Incidente: a plataforma percebe um pico de tickets parecidos, abre um incidente, agrupa os tickets,
  a IA escreve título e rascunho de resposta, e o analista responde e fecha todos de uma vez. O mapa vivo
  destaca o grupo.
- "Por que a IA decidiu": por ticket, a cadeia de decisão (fatos da LLM com confiança, regra e versão,
  fallback, texto redigido, link para o trace).
- Resiliência ao vivo: roteiro de demonstração que derruba Kafka ou agente e prova zero perda, com vídeo de
  reserva.

**W2. Limiar do incidente: 5 ou mais tickets abertos da mesma categoria e marca em 10 minutos**
(recomendado; configurável por ambiente). Categoria vem da LLM; sem ela, da primeira tag.

**W3. Escopo do experimento oficial: enxuto** — ver W6 (dono escolheu "o último" da pergunta de recursos;
o escopo do experimento segue a recomendação).

**W4. Ticket resolvido pela IA fecha sozinho após 30 minutos sem mensagem do cliente** (recomendado), com
código de resolução próprio e resumo de memória.

**W5. Redesign no visual da CloudWalk** (dono, 2026-11-22; substitui a proposta inicial de Radix Slate +
Iris). Valores tirados do CSS público de cloudwalk.io: fundo quase preto (#0d0d0d), branco quente (#ecebe9),
verde terminal (#24d332) como acento, IBM Plex Mono para dados e Inter Variable no texto (BDO Grotesk e
Cera Pro não têm pacote livre). Ícones Lucide; componentes únicos em `frontend/src/ui/` (Button, Kbd,
BrandMark, BrandDot, PriorityTag, classes de campo). Contraste AA conferido em todo texto, foco visível,
teclado e movimento reduzido (dono). Não usa o logotipo da CloudWalk. Cores das marcas InfinitePay e JIM
seguem provisórias até o dono confirmar.

**W6. Experimento enxuto:** k6 em modo de produção (rampa 1×→10×→50×, Kafka parado 60 s, agente em caos,
LLM fora), invariantes, gráficos do Grafana e relatório com hipótese, método e limitações.

**W7. Detalhes do Modo Incidente** (implementação de W1 e W2, 2026-11-22; adotados sem resposta explícita do
dono e reversíveis):
- Chave do grupo: categoria da LLM; sem categoria útil, a primeira tag. "outro" e "falar_com_humano" não
  abrem incidente (muitos pedidos assim não indicam uma falha comum).
- No máximo um incidente aberto por marca e chave (índice único parcial). Com um aberto, todo ticket novo da
  mesma chave entra nele. A detecção roda num job depois da entrada e de cada enriquecimento.
- Título e rascunho nascem de um template; a LLM (`prompts/incident/v1.yaml`) os reescreve quando está ligada.
- "Responder a todos" assume e fecha, numa transação, os tickets que estão com a IA, na fila ou com o próprio
  analista. Os de outro analista ficam de fora e voltam como pulados: a plataforma não tira atendimento de
  ninguém. O incidente fica resolvido.
- No mapa, os tickets de um incidente aberto formam um grupo próprio, em laranja.
- Observado na pilha: a detecção na entrada usa a tag da regra antes de a categoria da LLM chegar, então a
  chave pode ser a tag (ex.: "dispositivo") enquanto o título da LLM fala da categoria.

**W8. Tema claro no estilo de painel de atendimento** (dono, 2026-11-22; substitui o visual escuro de W5 e o
tema escuro de I1 do ADR 0007). Referência visual dada pelo dono (Kirridesk, da Fikri Studio): fundo cinza,
cards brancos, verde como cor de ação, barra lateral clara com perfil no topo e uma tela **Painel** com
indicadores e gráficos. Adaptado sem inventar dados: todo número vem de `GET /api/dashboard` (abertos agora,
criados e resolvidos hoje contra ontem, série de 7 dias, primeira resposta humana, SLA, quem resolveu, canais).
"Satisfação do cliente" virou "Quem resolveu" e SLA, porque a plataforma não mede satisfação. Busca, base de
conhecimento e fórum ficaram de fora, porque não existem. Contraste AA conferido; paletas dos gráficos
validadas para daltonismo. A identidade (logotipo e nome) da referência não é usada.

## Consequências

- Nova entidade `Incident` e nova ação em lote (responder e fechar vários tickets).
- Novas dependências de frontend (todas com 14 dias ou mais de publicação, sem dependências transitivas):
  `@fontsource-variable/inter` 5.3.0 e `@fontsource/ibm-plex-mono` 5.3.0 (OFL) e `lucide-react` 1.70.0 (ISC).
- Ordem de execução: redesign da base → Modo Incidente → "Por que a IA" → fechamento automático e dados de
  demonstração → resiliência ao vivo → experimento → README.
