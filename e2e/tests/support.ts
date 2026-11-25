import { expect, type Browser, type Page } from "@playwright/test";

// Cliente sintética criada pelo demo:reset, com dois atendimentos anteriores (memória).
export const MARINA = { brand: "infinitepay", channel: "whatsapp", external_id: "demo-marina", name: "Marina Souza" };

/** Abre um contexto novo de navegador (sessão própria) e entra pela tela de entrada como uma pessoa de teste. */
export async function signedIn(browser: Browser, person: "Ana" | "Olivia"): Promise<Page> {
  const page = await (await browser.newContext()).newPage();
  await page.goto("/");
  await page.getByRole("button", { name: new RegExp(`^${person}`) }).click();
  await expect(page.getByRole("navigation", { name: "Principal" })).toBeVisible();
  return page;
}

/** Chat do cliente simulado numa sessão própria; com `identity`, entra direto como aquele cliente. */
export async function customerChat(browser: Browser, identity?: typeof MARINA): Promise<Page> {
  const page = await (await browser.newContext()).newPage();
  if (identity) {
    await page.addInitScript((value) => window.localStorage.setItem("helpdesk.customer", JSON.stringify(value)), identity);
  }
  await page.goto("/#/cliente");
  return page;
}
