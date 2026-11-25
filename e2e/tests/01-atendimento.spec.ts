import { expect, test } from "@playwright/test";
import { customerChat, MARINA, signedIn } from "./support";

// Jornada principal, de ponta a ponta na pilha real: canal → API → outbox → broker → Kafka → agente → handoff →
// analista → cliente. Pré-condição: `rails demo:reset` (scripts/e2e/run.ps1 faz isso).
test("a cliente escreve, o agente escala, a analista atende com memória e fecha", async ({ browser }) => {
  const customer = await customerChat(browser, MARINA);
  await customer.getByLabel("Sua mensagem").fill("minha maquininha travou de novo, CPF 529.982.247-25 [escalar]");
  await customer.getByRole("button", { name: "Enviar" }).click();
  await expect(customer.getByText("Aguardando uma pessoa da equipe")).toBeVisible();

  const analyst = await signedIn(browser, "Ana");
  await analyst.getByRole("link", { name: "Fila" }).click();
  await analyst.getByRole("button", { name: "Pegar o próximo" }).click();

  const conversation = analyst.getByRole("region", { name: "Conversa" });
  await expect(conversation.getByText(/maquininha travou de novo/)).toBeVisible();
  await expect(conversation.getByRole("heading", { name: /Marina Souza/ })).toBeVisible();

  // Contexto: brief do handoff e a memória dos dois atendimentos anteriores da cliente.
  const context = analyst.getByRole("region", { name: "Contexto" });
  await expect(context.getByText("Brief do handoff")).toBeVisible();
  await expect(context.getByText(/Troca da maquininha aprovada/)).toBeVisible();
  await expect(context.getByText(/Chip reconfigurado/)).toBeVisible();

  // Por que a IA decidiu: o texto que a LLM recebeu não tem o CPF.
  await analyst.getByRole("tab", { name: "Por que a IA decidiu" }).click();
  const seen = analyst.getByRole("figure", { name: "Texto que a LLM recebeu" });
  await expect(seen).toContainText("[CPF]");
  await expect(seen).not.toContainText("529.982.247-25");
  await expect(analyst.getByRole("list", { name: "Cadeia de decisão" })).toContainText("Escalado");
  await analyst.getByRole("tab", { name: "Contexto" }).click();

  // A analista responde e a cliente vê a resposta.
  const reply = "Oi, Marina! Vamos trocar a sua maquininha hoje mesmo.";
  await analyst.getByLabel("Resposta ao cliente").fill(reply);
  await conversation.getByRole("button", { name: "Enviar" }).click();
  await expect(conversation.getByText(reply)).toBeVisible();
  await expect(customer.getByRole("log", { name: "Conversa" }).getByText(reply)).toBeVisible();
  await expect(customer.getByText("Em atendimento com uma pessoa da equipe")).toBeVisible();

  // Fecha com resolução; a cliente vê o encerramento.
  await conversation.getByRole("button", { name: "Fechar ticket" }).click();
  const dialog = analyst.getByRole("dialog", { name: "Fechar ticket" });
  await dialog.getByRole("radio", { name: "Resolvido" }).check();
  await dialog.getByRole("button", { name: "Fechar", exact: true }).click();
  await expect(customer.getByText(/Atendimento encerrado/)).toBeVisible();

  // O Painel conta o resolvido de hoje.
  await analyst.getByRole("link", { name: "Painel" }).click();
  await expect(analyst.getByRole("group", { name: "Resolvidos hoje" })).toContainText(/Resolvidos hoje\s*[1-9]/);
});
