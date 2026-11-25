import { expect, test } from "@playwright/test";
import { signedIn } from "./support";

// Cada card da tela inicial abre o detalhe em qualquer ponto dele, não só no título. Gráficos e o mapa são
// elementos posicionados e já interceptaram o clique antes.
const CARDS: [string, string][] = [
  ["Volume de tickets", "#/painel"],
  ["Resolvidos pela IA", "#/painel"],
  ["SLA da primeira resposta", "#/painel"],
  ["Mapa vivo", "#/mapa"],
  ["Tempo de solução", "#/solucao"],
  ["Modo Incidente", "#/mapa"],
  ["Filas e regras", "#/operacao"],
  ["Desempenho do time", "#/time"],
  ["Operação dos tickets", "#/tickets"],
];

test("todo card da tela inicial abre ao clicar no meio dele", async ({ browser }) => {
  const page = await signedIn(browser, "Olivia");
  for (const [name, hash] of CARDS) {
    await page.goto("/#/inicio");
    const card = page.getByRole("article", { name });
    await card.scrollIntoViewIfNeeded();
    const box = (await card.boundingBox())!;
    // Nos cards com tabela, as linhas abrem o analista; o resto do card abre o detalhe do card. Esses dois
    // clicam na faixa do título, onde não há linha.
    const withRows = name === "Desempenho do time" || name === "Operação dos tickets";
    await page.mouse.click(box.x + box.width * (withRows ? 0.6 : 0.5), box.y + (withRows ? 34 : box.height * 0.65));
    await expect(page, name).toHaveURL(new RegExp(`${hash}$`));
  }
});

test("clicar num analista abre o detalhe dele, com os números e sem as conversas", async ({ browser }) => {
  const page = await signedIn(browser, "Olivia");
  await page.goto("/#/inicio");
  const team = page.getByRole("table", { name: "Desempenho por analista" });
  await expect(team.getByRole("row")).not.toHaveCount(1);
  const row = team.getByRole("row").nth(1);
  await row.scrollIntoViewIfNeeded();
  const name = (await row.getByRole("link").innerText()).trim();

  // Em qualquer ponto da linha, não só no nome.
  const box = (await row.boundingBox())!;
  await page.mouse.click(box.x + box.width * 0.55, box.y + box.height / 2);

  await expect(page).toHaveURL(/#\/analista\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { level: 1, name })).toBeVisible();
  for (const stat of ["Recebidos", "Respondidos", "Resolvidos", "Em atendimento agora", "Mensagens enviadas"]) {
    await expect(page.getByRole("group", { name: stat })).toBeVisible();
  }
  await expect(page.getByRole("region", { name: "SLA da primeira resposta" })).toBeVisible();
  await expect(page.getByRole("list", { name: "Assuntos mais tratados" }).or(page.getByText("Nenhum assunto ainda."))).toBeVisible();
  await expect(page.getByRole("region", { name: "Conversa" })).toHaveCount(0);

  await page.getByRole("link", { name: "Voltar" }).click();
  await expect(page).toHaveURL(/#\/inicio$/);
});

test("o card Tempo de solução abre o detalhe com a distribuição", async ({ browser }) => {
  const page = await signedIn(browser, "Olivia");
  await page.goto("/#/inicio");
  await page.getByRole("article", { name: "Tempo de solução" }).click();

  await expect(page).toHaveURL(/#\/solucao$/);
  await expect(page.getByRole("heading", { level: 1, name: "Tempo de solução" })).toBeVisible();
  for (const stat of ["Mediana", "Média", "Resolvidos", "Dentro da meta"]) {
    await expect(page.getByRole("group", { name: stat })).toBeVisible();
  }
});

test("os cards do time e dos tickets abrem a tela deles, com tabela de analistas e de tickets", async ({ browser }) => {
  const page = await signedIn(browser, "Olivia");
  await page.goto("/#/inicio");
  await page.getByRole("article", { name: "Desempenho do time" }).getByRole("link", { name: "Desempenho do time" }).click();

  await expect(page).toHaveURL(/#\/time$/);
  await expect(page.getByRole("heading", { level: 1, name: "Desempenho do time" })).toBeVisible();
  for (const stat of ["Recebidos", "Respondidos", "Resolvidos", "Em atendimento agora", "SLA do time"]) {
    await expect(page.getByRole("group", { name: stat })).toBeVisible();
  }
  await expect(page.getByRole("table", { name: "Analistas do time" }).getByRole("row")).not.toHaveCount(1);

  await page.getByRole("link", { name: "Voltar" }).click();
  await page.getByRole("article", { name: "Operação dos tickets" }).getByRole("link", { name: "Operação dos tickets" }).click();

  await expect(page).toHaveURL(/#\/tickets$/);
  await expect(page.getByRole("heading", { level: 1, name: "Operação dos tickets" })).toBeVisible();
  for (const stat of ["Pedem gente", "Sem analista", "Fora do prazo", "Parados"]) {
    await expect(page.getByRole("group", { name: stat })).toBeVisible();
  }
});
