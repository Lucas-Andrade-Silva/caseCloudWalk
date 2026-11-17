import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mockApi } from "../../test/mockApi";
import { CustomerChat } from "./CustomerChat";

const CONVERSATION = "/api/simulator/conversation";

function conversationPath(brand: string, channel: string, externalId: string) {
  return `${CONVERSATION}?brand=${brand}&channel=${channel}&external_id=${encodeURIComponent(externalId)}`;
}

describe("chat do cliente simulado", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("escolhe marca, canal e nome, conversa e vê a resposta", async () => {
    let messages: unknown[] = [];
    let mode: string | null = null;
    const api = mockApi({
      [`GET ${CONVERSATION}*`]: () => [200, { ticket_id: mode && "t1", mode, messages }],
    });
    api.set("POST /api/simulator/messages", (body) => {
      const sent = body as { text: string };
      mode = "ai";
      messages = [
        { seq: 1, sender: "customer", text: sent.text, created_at: "2026-11-16T12:00:00.000Z" },
        { seq: 2, sender: "bot", text: "Hi! Let me check your payout.", created_at: "2026-11-16T12:00:01.000Z" },
      ];
      return [201, { ticket_id: "t1", seq: 1 }];
    });
    render(<CustomerChat />);

    await userEvent.selectOptions(screen.getByLabelText("Marca"), "jim");
    await userEvent.selectOptions(screen.getByLabelText("Canal"), "whatsapp");
    await userEvent.type(screen.getByLabelText("Seu nome"), "John");
    const stored = () => JSON.parse(window.localStorage.getItem("helpdesk.customer") ?? "{}");
    await userEvent.click(screen.getByRole("button", { name: "Começar conversa" }));

    expect(stored()).toMatchObject({ brand: "jim", channel: "whatsapp", name: "John" });
    expect(stored().external_id).toMatch(/^cliente-[0-9a-f]{6}$/);
    expect(await screen.findByText("Escreva para começar.")).toBeInTheDocument();

    await userEvent.type(screen.getByLabelText("Sua mensagem"), "where is my payout?");
    await userEvent.click(screen.getByRole("button", { name: "Enviar" }));

    const chat = screen.getByRole("log", { name: "Conversa" });
    expect(await within(chat).findByText("Hi! Let me check your payout.")).toBeInTheDocument();
    expect(screen.getByText("Atendimento automático")).toBeInTheDocument();
    expect(api.calls.find((call) => call.method === "POST")?.body).toEqual({
      brand: "jim",
      channel: "whatsapp",
      customer: { external_id: stored().external_id, name: "John" },
      text: "where is my payout?",
    });
    expect(api.calls.some((call) => call.path === conversationPath("jim", "whatsapp", stored().external_id))).toBe(true);
  });

  it("volta como o mesmo cliente e mostra em que pé está o atendimento", async () => {
    window.localStorage.setItem(
      "helpdesk.customer",
      JSON.stringify({ brand: "infinitepay", channel: "app_chat", external_id: "cliente-abc123", name: "Maria" }),
    );
    let mode = "pending_human";
    const api = mockApi({});
    api.set(`GET ${conversationPath("infinitepay", "app_chat", "cliente-abc123")}`, () => [
      200,
      {
        ticket_id: "t1",
        mode,
        messages: [{ seq: 1, sender: "customer", text: "quero falar com uma pessoa", created_at: "2026-11-16T12:00:00.000Z" }],
      },
    ]);
    const { unmount } = render(<CustomerChat />);

    expect(await screen.findByText("Aguardando uma pessoa da equipe")).toBeInTheDocument();
    expect(screen.getByText(/Maria · InfinitePay · App/)).toBeInTheDocument();
    unmount();

    mode = "closed";
    render(<CustomerChat />);
    expect(await screen.findByText("Atendimento encerrado. Mande uma mensagem para abrir outro.")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Trocar cliente" }));
    expect(screen.getByRole("button", { name: "Começar conversa" })).toBeInTheDocument();
    expect(window.localStorage.getItem("helpdesk.customer")).toBeNull();
  });

  it("avisa quando o simulador de canal está desligado", async () => {
    window.localStorage.setItem(
      "helpdesk.customer",
      JSON.stringify({ brand: "infinitepay", channel: "app_chat", external_id: "cliente-abc123", name: "Maria" }),
    );
    mockApi({ [`GET ${conversationPath("infinitepay", "app_chat", "cliente-abc123")}`]: () => [404] });
    render(<CustomerChat />);

    expect(await screen.findByRole("alert")).toHaveTextContent("O simulador de canal está desligado nesta instalação.");
  });
});
