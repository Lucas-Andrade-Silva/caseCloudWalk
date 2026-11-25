# ADR 0010 — Home em cards, sem barra lateral, em tema escuro

- Status: aceito em 2026-11-24 (escolhas do dono). Substitui o tema claro com Painel (ADR 0009, W8) e a barra
  lateral do ADR 0007.
- Contexto: o dono trouxe uma referência de dashboard escuro com acento verde, em cards, e pediu uma cara mais
  viva e próxima da CloudWalk, faltando três dias para a entrega.

## Decisões

**H1. Sem barra lateral.** Uma barra superior fina (marca, papel e marcas do usuário, incidentes, sair). A tela
inicial (`#/inicio`) é uma grade de cards; tudo o que a plataforma faz aparece ali como card.

**H2. Card abre tela de detalhe.** Clicar leva à tela existente (Painel, Fila, Mapa vivo, Filas e regras). Toda
tela de detalhe tem "Voltar" no canto superior esquerdo, que leva à tela inicial. Rota desconhecida leva à
tela inicial.

**H3. Escopo por papel.** O analista vê só as marcas dele; a operação vê tudo. É o escopo que a API já aplica
(`/api/dashboard`, `/api/map`, `/api/incidents`); a interface só rotula.

**H4. Cards do diferencial e da operação.** Resolvidos pela IA, Mapa vivo, Modo Incidente, SLA da primeira
resposta, Tempo de solução (mediana da abertura ao fechamento, meta de 8 h, separada entre IA e humano),
Desempenho do time e Operação dos tickets (parados há mais de 3 dias, sem analista e os que pedem gente),
todos calculados em `Dashboard::Metrics` (2026-11-25, pedido do dono). A plataforma não coleta CSAT nem
presença: a coluna de qualidade do time é o SLA da primeira resposta, e "em atendimento agora" conta quem
tem ticket com humano aberto. A home só mostra números da plataforma.

**H5. Tema escuro com as cores e o estilo de ícones do anexo do dono** (verde-esmeralda, laranja, amarelo de
risco, vermelho e ciano; ícones Lucide finos em caixas). A página rola. Todo texto passa de 4,5:1 (axe no e2e).

**H6. Tela viva.** Volume de tickets em curva suavizada com rótulo de pico e uma luz que percorre a linha da
esquerda para a direita sem parar; o card do mapa vivo mostra as bolhas atuais girando devagar. Os dois param
com `prefers-reduced-motion`. A curva suavizada é escolha do dono, com a tabela acessível dos valores reais
por baixo.

**H7. Idioma:** português, mantendo termos já usados em inglês (ticket, SLA, handoff, DLQ).
