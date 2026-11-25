import { expect, test, type Page } from "@playwright/test";

// Vídeo de demonstração (não é teste de regressão): a jornada inteira, devagar, com uma legenda por passo.
// Uma aba só, navegando entre cliente, analista e operação, para o vídeo sair contínuo. Rode com
// scripts/demo/video.ps1, que limpa o banco de demo antes e copia o vídeo para e2e/videos/.

const MARINA = { brand: "infinitepay", channel: "whatsapp", external_id: "demo-marina", name: "Marina Souza" };

/** Mostra (ou troca) a legenda no canto da tela e espera o tempo de leitura. */
async function caption(page: Page, title: string, text: string, readMs = 4500) {
  await page.evaluate(
    ([heading, body]) => {
      let box = document.getElementById("demo-caption");
      if (!box) {
        box = document.createElement("div");
        box.id = "demo-caption";
        box.setAttribute("aria-hidden", "true");
        Object.assign(box.style, {
          position: "fixed", right: "28px", bottom: "28px", zIndex: "2147483647", maxWidth: "560px",
          padding: "16px 20px", borderRadius: "14px", background: "rgba(17, 24, 39, 0.92)", color: "#ffffff",
          fontFamily: "Inter Variable, Inter, system-ui, sans-serif", boxShadow: "0 12px 32px rgba(0,0,0,0.25)",
          transition: "opacity 250ms ease", pointerEvents: "none",
        });
        document.body.appendChild(box);
      }
      box.style.opacity = "0";
      box.innerHTML =
        `<div style="font-size:13px;font-weight:600;color:#4ade80;letter-spacing:0.02em">${heading}</div>` +
        `<div style="margin-top:6px;font-size:17px;line-height:1.45">${body}</div>`;
      requestAnimationFrame(() => (box!.style.opacity = "1"));
    },
    [title, text],
  );
  await page.waitForTimeout(readMs);
}

async function signInAs(page: Page, person: "Ana" | "Olivia") {
  await page.evaluate(() => window.localStorage.removeItem("helpdesk.token"));
  await page.goto("/");
  await page.getByRole("button", { name: new RegExp(`^${person}`) }).click();
  await expect(page.getByRole("navigation", { name: "Principal" })).toBeVisible();
}

async function goTo(page: Page, hash: string) {
  await page.goto(`/${hash}`);
}

test("vídeo: o help desk de ponta a ponta", async ({ browser }) => {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    recordVideo: { dir: "demo-results/raw", size: { width: 1440, height: 900 } },
    locale: "pt-BR",
    timezoneId: "America/Sao_Paulo",
  });
  const page = await context.newPage();

  // Abertura
  await page.goto("/");
  await caption(page, "Help desk AI-first · InfinitePay e JIM",
    "A IA atende primeiro. A plataforma tria, prioriza, escala para pessoas com contexto e lembra o cliente. Dados sintéticos.", 6000);

  await signInAs(page, "Ana");
  await goTo(page, "#/painel");
  await expect(page.getByRole("region", { name: "Indicadores" })).toBeVisible();
  await caption(page, "Painel",
    "Tudo aqui é consulta ao banco: abertos agora, criados e resolvidos hoje contra ontem, primeira resposta humana e quem resolveu.", 6000);

  // 1. A cliente escreve
  await page.evaluate((identity) => window.localStorage.setItem("helpdesk.customer", JSON.stringify(identity)), MARINA);
  await goTo(page, "#/cliente");
  await caption(page, "1 · A cliente escreve", "Marina Souza fala com a InfinitePay pelo WhatsApp e cita o CPF na mensagem.", 3500);
  await page.getByLabel("Sua mensagem").pressSequentially("a maquininha travou de novo, CPF 529.982.247-25 [escalar]", { delay: 35 });
  await page.getByRole("button", { name: "Enviar" }).click();
  await expect(page.getByText("Aguardando uma pessoa da equipe")).toBeVisible();
  await caption(page, "O agente de IA pede uma pessoa",
    "A mensagem passou por API, outbox, broker e Kafka até o agente, que escalou. A cliente vê que já tem alguém vindo.", 6000);

  // 2. A analista pega o próximo
  await goTo(page, "#/fila");
  await caption(page, "2 · A analista pega o próximo", "A plataforma escolhe o ticket de prazo mais curto; ninguém escolhe a dedo.", 3500);
  await page.getByRole("button", { name: "Pegar o próximo" }).click();
  const conversation = page.getByRole("region", { name: "Conversa" });
  await expect(conversation.getByText(/maquininha travou de novo/)).toBeVisible();
  const ticketUrl = page.url();
  await caption(page, "Brief e memória do cliente",
    "A IA resume o caso, e a analista vê os dois atendimentos anteriores da Marina, sem reler conversa nenhuma.", 7000);

  // 3. Por que a IA decidiu
  await page.getByRole("tab", { name: "Por que a IA decidiu" }).click();
  await expect(page.getByRole("figure", { name: "Texto que a LLM recebeu" })).toBeVisible();
  await caption(page, "3 · Por que a IA decidiu",
    "O texto que a LLM recebeu (o CPF virou [CPF]), a regra que casou e a versão dela, a confiança da LLM e o link do trace.", 8000);
  await page.getByRole("tab", { name: "Contexto" }).click();

  // 4. Responde e fecha
  await caption(page, "4 · A analista responde", "Ctrl + Enter envia.", 2500);
  await page.getByLabel("Resposta ao cliente").pressSequentially("Oi, Marina! Já liberei a troca da sua maquininha; chega amanhã.", { delay: 30 });
  await page.keyboard.press("Control+Enter");
  await expect(conversation.getByText(/Já liberei a troca/)).toBeVisible();

  await goTo(page, "#/cliente");
  await expect(page.getByText(/Já liberei a troca/)).toBeVisible();
  await caption(page, "A cliente recebe na hora", "Do outro lado, a resposta da pessoa da equipe chega na conversa.", 4500);

  await page.goto(ticketUrl);
  await page.getByRole("region", { name: "Conversa" }).getByRole("button", { name: "Fechar ticket" }).click();
  const close = page.getByRole("dialog", { name: "Fechar ticket" });
  await close.getByRole("radio", { name: "Resolvido" }).check();
  await caption(page, "Fecha com resolução", "A resolução e o resumo do atendimento entram na memória da cliente.", 3500);
  await close.getByRole("button", { name: "Fechar", exact: true }).click();
  await expect(page.getByRole("button", { name: "Pegar o próximo" })).toBeVisible();

  // 5. Modo Incidente
  await page.evaluate(() => window.localStorage.removeItem("helpdesk.customer"));
  await goTo(page, "#/cliente");
  await caption(page, "5 · Um pico de reclamações", "Seis clientes sintéticos mandam a mesma reclamação ao mesmo tempo.", 3500);
  await page.getByRole("button", { name: "Simular pico" }).click();
  await expect(page.getByRole("status")).toContainText(/clientes enviaram/);

  await goTo(page, "#/fila");
  const banner = page.getByRole("region", { name: "Incidente aberto" });
  await expect(banner).toBeVisible();
  await caption(page, "Modo Incidente",
    "Em segundos a plataforma percebeu o pico, abriu um incidente e a LLM escreveu o título e o rascunho da resposta.", 6500);

  await goTo(page, "#/mapa");
  await expect(page.getByRole("region", { name: "Incidentes abertos" })).toBeVisible();
  await caption(page, "Mapa vivo", "Os tickets do pico se juntam num grupo laranja, em tempo real.", 7000);

  await goTo(page, "#/fila");
  await page.getByRole("region", { name: "Incidente aberto" }).getByRole("button", { name: "Responder a todos" }).click();
  const all = page.getByRole("dialog", { name: "Responder a todos" });
  await expect(all).toBeVisible();
  await caption(page, "Responder a todos", "A analista revisa o rascunho da IA e fecha todos os tickets do incidente de uma vez.", 5000);
  await all.getByRole("button", { name: "Responder e fechar" }).click();
  await expect(page.getByRole("status").filter({ hasText: /fechados?/ })).toBeVisible();
  await page.waitForTimeout(2500);

  // 6. A operação
  await signInAs(page, "Olivia");
  await expect(page.getByRole("form", { name: "Nova fila" })).toBeVisible();
  await caption(page, "6 · A operação", "Equipes e filas por marca, configuradas sem depender de desenvolvimento.", 4500);
  await page.getByRole("link", { name: "Regras", exact: true }).click();
  await caption(page, "Regras versionadas",
    "Condições e ações (fila, prioridade, tags), simuladas contra tickets reais antes de publicar, com auditoria de cada decisão.", 7000);

  // Encerramento
  await goTo(page, "#/painel");
  await expect(page.getByRole("region", { name: "Indicadores" })).toBeVisible();
  await caption(page, "Painel atualizado", "Os atendimentos de agora já aparecem nos números.", 5500);
  await caption(page, "E se algo cair?",
    "Kafka parado, agente lento ou respostas quebradas: nenhuma mensagem se perde (scripts/demo/resiliencia.ps1 e veneno.ps1).", 6000);

  const video = page.video();
  await context.close();
  await video?.saveAs("videos/helpdesk-demo.webm");
});
