import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";
import { customerChat, MARINA, signedIn } from "./support";

// Acessibilidade (PRODUCT.md: WCAG AA e uso completo por teclado). O axe confere cada tela nas regras WCAG 2.1
// A e AA; a segunda parte faz uma jornada só com o teclado e confere que o foco é sempre visível.
const WCAG = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"];

async function expectAccessible(page: Page, screen: string) {
  const { violations } = await new AxeBuilder({ page }).withTags(WCAG).analyze();
  const summary = violations.map(
    (violation) =>
      `${violation.id} (${violation.impact}): ${violation.help}\n` +
      violation.nodes.slice(0, 3).map((node) => `    ${node.target.join(" ")} — ${node.failureSummary?.split("\n")[1] ?? ""}`).join("\n"),
  );
  expect(summary, `violações de acessibilidade em ${screen}`).toEqual([]);
}

async function escalatedTicketFor(page: Page, externalId: string, name: string, text: string) {
  const response = await page.request.post("/api/simulator/messages", {
    data: { brand: "infinitepay", channel: "whatsapp", customer: { external_id: externalId, name }, text },
  });
  expect(response.ok()).toBeTruthy();
}

test("as telas passam nas regras WCAG 2.1 AA do axe", async ({ browser }) => {
  const visitor = await (await browser.newContext()).newPage();
  await visitor.goto("/");
  await expect(visitor.getByLabel("Token de acesso")).toBeVisible();
  await expectAccessible(visitor, "entrada");

  const customer = await customerChat(browser);
  await expect(customer.getByRole("button", { name: "Começar conversa" })).toBeVisible();
  await expectAccessible(customer, "chat do cliente (início)");
  const marina = await customerChat(browser, MARINA);
  await expect(marina.getByLabel("Sua mensagem")).toBeVisible();
  await expectAccessible(marina, "chat do cliente (conversa)");

  const analyst = await signedIn(browser, "Ana");
  await analyst.getByRole("link", { name: "Painel" }).click();
  await expect(analyst.getByRole("region", { name: "Indicadores" })).toBeVisible();
  await expectAccessible(analyst, "Painel");

  await escalatedTicketFor(analyst, `a11y-${Date.now()}`, "Cliente a11y", "minha maquininha não liga [escalar]");
  await analyst.getByRole("link", { name: "Fila" }).click();
  await expect(analyst.getByRole("region", { name: "Esperando nas suas filas" })).toContainText(/Cliente a11y/, { timeout: 30_000 });
  await analyst.getByRole("button", { name: "Pegar o próximo" }).click();
  await expect(analyst.getByRole("region", { name: "Conversa" })).toBeVisible();
  await expectAccessible(analyst, "fila com conversa aberta");
  await analyst.getByRole("tab", { name: "Por que a IA decidiu" }).click();
  await expect(analyst.getByRole("figure", { name: "Texto que a LLM recebeu" })).toBeVisible();
  await expectAccessible(analyst, "Por que a IA decidiu");

  await analyst.getByRole("link", { name: "Mapa vivo" }).click();
  await expect(analyst.getByRole("img", { name: /Mapa com/ })).toBeVisible();
  await expectAccessible(analyst, "mapa vivo");

  const ops = await signedIn(browser, "Olivia");
  await expect(ops.getByRole("form", { name: "Nova fila" })).toBeVisible();
  await expectAccessible(ops, "operação: filas e equipes");
  await ops.getByRole("link", { name: "Regras", exact: true }).click();
  await expect(ops.getByRole("button", { name: "Simular" }).or(ops.getByRole("button", { name: /Criar rascunho/ }))).toBeVisible();
  await expectAccessible(ops, "operação: regras");
});

/** Aperta Tab até o elemento focado ter o nome acessível pedido; falha se não chegar em `limit` toques. */
async function tabTo(page: Page, name: RegExp, limit = 40) {
  for (let presses = 0; presses < limit; presses++) {
    await page.keyboard.press("Tab");
    const label = await page.evaluate(() => {
      const element = document.activeElement as HTMLElement | null;
      if (!element) return "";
      return element.getAttribute("aria-label") ?? element.labels?.[0]?.textContent ?? element.textContent ?? "";
    });
    if (name.test(label.trim())) return;
  }
  throw new Error(`o Tab não chegou em ${name} em ${limit} toques`);
}

async function expectVisibleFocus(page: Page) {
  const outline = await page.evaluate(() => {
    const element = document.activeElement as HTMLElement | null;
    if (!element || element === document.body) return "sem foco";
    const style = getComputedStyle(element);
    return style.outlineStyle !== "none" && parseFloat(style.outlineWidth) > 0 ? "visível" : `invisível (${element.tagName})`;
  });
  expect(outline).toBe("visível");
}

test("dá para entrar, pegar o próximo e responder só com o teclado, sempre com foco visível", async ({ browser }) => {
  const seeder = await (await browser.newContext()).newPage();
  await seeder.goto("/");
  await escalatedTicketFor(seeder, `teclado-${Date.now()}`, "Cliente teclado", "não recebi meu repasse de ontem [escalar]");

  const page = await (await browser.newContext()).newPage();
  await page.goto("/");
  await tabTo(page, /^Token de acesso$/);
  await expectVisibleFocus(page);
  await page.keyboard.type("dev-analyst-ana");
  await page.keyboard.press("Enter");
  await expect(page.getByRole("navigation", { name: "Principal" })).toBeVisible();

  await tabTo(page, /^Fila$/);
  await expectVisibleFocus(page);
  await page.keyboard.press("Enter");
  await expect(page.getByRole("region", { name: "Esperando nas suas filas" })).toContainText(/Cliente teclado/, { timeout: 30_000 });

  await tabTo(page, /^Pegar o próximo$/);
  await expectVisibleFocus(page);
  await page.keyboard.press("Enter");
  const conversation = page.getByRole("region", { name: "Conversa" });
  await expect(conversation.getByText(/repasse de ontem/)).toBeVisible();

  await tabTo(page, /^Resposta ao cliente$/);
  await expectVisibleFocus(page);
  const reply = "Respondido só pelo teclado.";
  await page.keyboard.type(reply);
  await page.keyboard.press("Control+Enter");
  await expect(conversation.getByText(reply)).toBeVisible();

  await tabTo(page, /^Fechar ticket$/);
  await expectVisibleFocus(page);
  await page.keyboard.press("Enter");
  const dialog = page.getByRole("dialog", { name: "Fechar ticket" });
  await expect(dialog).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
});
