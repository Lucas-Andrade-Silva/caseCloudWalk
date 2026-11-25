import { expect, test } from "@playwright/test";
import { customerChat, signedIn } from "./support";

// Modo Incidente na pilha real: um pico de reclamações parecidas vira um incidente, aparece para a analista e no
// mapa, e "Responder a todos" fecha os tickets de uma vez.
test("um pico vira incidente, aparece no painel e no mapa, e a analista fecha todos de uma vez", async ({ browser }) => {
  const customer = await customerChat(browser);
  await customer.getByRole("button", { name: "Simular pico" }).click();
  await expect(customer.getByRole("status")).toContainText(/6 clientes enviaram/);

  const analyst = await signedIn(browser, "Ana");
  await expect(analyst.getByRole("list", { name: "Incidentes abertos" })).toBeVisible({ timeout: 60_000 });

  await analyst.getByRole("link", { name: "Mapa vivo" }).click();
  await expect(analyst.getByRole("region", { name: "Incidentes abertos" })).toContainText("Incidente");

  // O incidente é um círculo em órbita; abrir o grupo dá zoom e mostra os tickets dele girando (ADR 0012). Os
  // círculos não param, então o grupo é aberto pelo teclado (foco + Enter), que não espera o elemento ficar quieto.
  await analyst.getByRole("button", { name: /^incidente · .*, \d+ tickets$/ }).focus();
  await analyst.keyboard.press("Enter");
  await expect(analyst.getByRole("button", { name: "Todos os grupos" })).toBeVisible();
  await expect.poll(() => analyst.locator("[data-ticket]").count()).toBeGreaterThanOrEqual(5);
  await analyst.getByRole("button", { name: "Todos os grupos" }).click();
  await expect(analyst.locator("[data-ticket]")).toHaveCount(0);

  await analyst.getByRole("link", { name: "Voltar" }).click();
  await analyst.getByRole("link", { name: "Fila" }).click();
  const banner = analyst.getByRole("region", { name: "Incidente aberto" });
  await expect(banner).toBeVisible();
  await banner.getByRole("button", { name: "Responder a todos" }).click();

  const dialog = analyst.getByRole("dialog", { name: "Responder a todos" });
  await expect(dialog.getByRole("textbox")).not.toHaveValue("");
  await dialog.getByRole("button", { name: "Responder e fechar" }).click();
  await expect(analyst.getByRole("status").filter({ hasText: /tickets? fechados?/ })).toBeVisible();
  await expect(banner).toHaveCount(0);
});
