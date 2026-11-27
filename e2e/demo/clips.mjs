// Grava clipes curtos da plataforma para a apresentação (docs/apresentacao/video/). Não é teste.
// Uso, com a pilha no ar e o banco de demo limpo (rails demo:reset):  node e2e/demo/clips.mjs
import { chromium } from "@playwright/test";
import { mkdirSync, renameSync } from "node:fs";
import path from "node:path";

const BASE = process.env.BASE_URL ?? "http://127.0.0.1:5173";
const OUT = path.resolve(process.argv[2] ?? "docs/apresentacao/video");
const RAW = path.join(OUT, "raw");
mkdirSync(RAW, { recursive: true });
const MARINA = { brand: "infinitepay", channel: "whatsapp", external_id: "demo-marina", name: "Marina Souza" };
const size = { width: 1440, height: 900 };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await chromium.launch({ slowMo: 90 });

const ONLY = process.env.ONLY?.split(",");
async function clip(name, run) {
  if (ONLY && !ONLY.includes(name)) return;
  const context = await browser.newContext({ viewport: size, recordVideo: { dir: RAW, size }, locale: "pt-BR", timezoneId: "America/Sao_Paulo", baseURL: BASE });
  const page = await context.newPage();
  page.setDefaultTimeout(60_000);
  try { await run(page); } catch (e) { console.error(`[${name}]`, e.message); }
  const video = page.video();
  await context.close();
  const file = await video.path();
  renameSync(file, path.join(OUT, `${name}.webm`));
  console.log("ok", name);
}

async function signIn(page, person) {
  await page.goto("/");
  await page.evaluate(() => localStorage.removeItem("helpdesk.token"));
  await page.goto("/");
  await page.getByRole("button", { name: new RegExp(`^${person}`) }).click();
  await page.getByRole("navigation", { name: "Principal" }).waitFor();
}

// 1. A cliente escreve e a IA responde, depois pede uma pessoa.
await clip("01-cliente", async (page) => {
  await page.goto("/");
  await page.evaluate((m) => localStorage.setItem("helpdesk.customer", JSON.stringify(m)), MARINA);
  await page.goto("/#/cliente");
  await wait(1500);
  await page.getByLabel("Sua mensagem").pressSequentially("oi, como faço para antecipar meus recebíveis?", { delay: 40 });
  await page.getByRole("button", { name: "Enviar" }).click();
  await wait(6000);
  await page.getByLabel("Sua mensagem").pressSequentially("a maquininha travou de novo, CPF 529.982.247-25 [escalar]", { delay: 40 });
  await page.getByRole("button", { name: "Enviar" }).click();
  await page.getByText("Aguardando uma pessoa da equipe").waitFor();
  await wait(3500);
});

// 2. A analista pega o próximo: brief, memória e "Por que a IA decidiu".
await clip("02-analista", async (page) => {
  await signIn(page, "Ana");
  await page.goto("/#/fila");
  await wait(1500);
  await page.getByRole("button", { name: "Pegar o próximo" }).click();
  await page.getByRole("region", { name: "Conversa" }).getByText(/maquininha travou de novo/).waitFor();
  await wait(5000);
  await page.mouse.wheel(0, 300);
  await wait(1500);
  await page.getByRole("tab", { name: "Por que a IA decidiu" }).click();
  await wait(6000);
  await page.getByRole("tab", { name: "Contexto" }).click();
  await page.getByLabel("Resposta ao cliente").pressSequentially("Oi, Marina! Já liberei a troca da sua maquininha; chega amanhã.", { delay: 30 });
  await page.keyboard.press("Control+Enter");
  await wait(3000);
});

// 3. Pico: seis clientes ao mesmo tempo viram um incidente.
await clip("03-incidente", async (page) => {
  await signIn(page, "Ana");
  await page.evaluate(() => localStorage.removeItem("helpdesk.customer"));
  await page.goto("/#/cliente");
  await wait(1200);
  await page.getByRole("button", { name: "Simular pico" }).click();
  await wait(2500);
  await page.goto("/#/fila");
  await page.getByRole("region", { name: "Incidente aberto" }).waitFor();
  await wait(4000);
  await page.getByRole("region", { name: "Incidente aberto" }).getByRole("button", { name: "Responder a todos" }).click();
  await wait(5000);
  await page.keyboard.press("Escape");
  await wait(800);
});

// 4. Mapa vivo em órbita, com zoom num grupo.
await clip("04-mapa", async (page) => {
  await signIn(page, "Ana");
  // Alguns tickets com humano, para o mapa mostrar as três cores.
  await page.goto("/#/fila");
  for (let i = 0; i < 2; i++) { await page.getByRole("button", { name: "Pegar o próximo" }).click().catch(() => {}); await wait(1500); }
  await page.goto("/#/mapa");
  await wait(7000);
  const bubble = page.locator(".map-bubble").first();
  if (await bubble.count()) { await bubble.click({ force: true, timeout: 5000 }).catch(() => {}); await wait(6000); await page.keyboard.press("Escape"); }
  await wait(3000);
});

// 5. Home em cards da operação.
await clip("05-home", async (page) => {
  await signIn(page, "Olivia");
  await page.goto("/#/inicio");
  await wait(3000);
  for (const [x, y] of [[400, 280], [880, 260], [1200, 200], [300, 560], [800, 560], [1250, 560]]) { await page.mouse.move(x, y, { steps: 18 }); await wait(1100); }
  await page.mouse.wheel(0, 500);
  await wait(3000);
});

// 6. Operação: filas e regras versionadas.
await clip("06-operacao", async (page) => {
  await signIn(page, "Olivia");
  await page.goto("/#/operacao");
  await wait(3500);
  const rules = page.getByRole("link", { name: "Regras", exact: true });
  if (await rules.count()) { await rules.click(); await wait(6000); }
});

await browser.close();
