import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { TicketDetail, Work, WorkItem } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { AnalystWorkspace } from "./AnalystWorkspace";

const item = (overrides: Partial<WorkItem> = {}): WorkItem => ({
  id: "t1",
  brand: "infinitepay",
  channel: "whatsapp",
  mode: "pending_human",
  priority: "p2",
  queue: "credito-infinitepay",
  tags: ["alto_valor"],
  customer: { external_id: "c-42", name: "Maria" },
  escalated_at: "2026-11-16T12:00:00.000Z",
  first_response_due_at: "2026-11-16T12:15:00.000Z",
  first_human_response_at: null,
  last_message: { sender: "customer", text: "preciso de um empréstimo de R$ 12000", created_at: "2026-11-16T12:00:00.000Z" },
  ...overrides,
});

const detail = (overrides: Partial<TicketDetail> = {}): TicketDetail => ({
  ...item({ mode: "human" }),
  assignee_id: "u-ana",
  closed_at: null,
  resolution_code: null,
  handoff_brief: { summary: "Escalado pelo agente (motivo: credito_alto_valor).", reason: "credito_alto_valor", trigger: "agent_requested" },
  messages: [
    { id: "m1", seq: 1, sender: "customer", text: "preciso de um empréstimo de R$ 12000", stale: false, created_at: "2026-11-16T12:00:00.000Z" },
    { id: "m2", seq: 2, sender: "bot", text: "Vou chamar uma pessoa do time.", stale: false, created_at: "2026-11-16T12:00:01.000Z" },
  ],
  memory: {
    window_days: 90,
    tickets: [
      {
        ticket_id: "t0", channel: "app_chat", mode: "closed", opened_at: "2026-11-01T10:00:00.000Z",
        closed_at: "2026-11-01T10:30:00.000Z", priority: "p3", queue: "infinitepay-atendimento", tags: [],
        escalation_reason: null, resolution_code: "resolved", summary: "Ticket t0 via app_chat. Resolução: resolvido.",
      },
    ],
  },
  ...overrides,
});

const emptyWork: Work = { mine: [], waiting: [], waiting_count: 0 };

describe("painel do analista", () => {
  beforeEach(() => {
    window.location.hash = "#/fila";
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra a fila de espera e, ao pegar o próximo, abre a conversa com brief e memória", async () => {
    let work: Work = { mine: [], waiting: [item()], waiting_count: 1 };
    const api = mockApi({
      "GET /api/work": () => [200, work],
      "POST /api/work/next": () => {
        work = { mine: [item({ mode: "human" })], waiting: [], waiting_count: 0 };
        return [200, { id: "t1" }];
      },
      "GET /api/tickets/t1": () => [200, detail()],
    });
    render(<AnalystWorkspace token="tk" />);

    const waiting = await screen.findByRole("region", { name: "Esperando nas suas filas" });
    expect(within(waiting).getByText("Maria")).toBeInTheDocument();
    expect(screen.getByText("Nenhum ticket com você.")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Pegar o próximo" }));

    const conversation = await screen.findByRole("region", { name: "Conversa" });
    expect(within(conversation).getByText("Vou chamar uma pessoa do time.")).toBeInTheDocument();
    const context = screen.getByRole("region", { name: "Contexto" });
    expect(within(context).getByText(/Escalado pelo agente/)).toBeInTheDocument();
    expect(within(context).getByText("Ticket t0 via app_chat. Resolução: resolvido.")).toBeInTheDocument();
    expect(api.calls.find((call) => call.method === "POST")?.headers).toMatchObject({ Authorization: "Bearer tk" });
    expect(window.location.hash).toBe("#/fila/t1");
  });

  it("mostra o resumo da IA identificado e os fatos que a IA deu, sem repetir o resumo por template", async () => {
    window.location.hash = "#/fila/t1";
    mockApi({
      "GET /api/work": () => [200, { ...emptyWork, mine: [item({ mode: "human" })] }],
      "GET /api/tickets/t1": () => [
        200,
        detail({
          handoff_brief: {
            summary: "Escalado pelo agente (motivo: credito_alto_valor).",
            reason: "credito_alto_valor",
            trigger: "agent_requested",
            llm_summary: "Cliente quer R$ 12 mil; o agente não pode aprovar valor alto.",
            llm_model: "openai/gpt-oss-120b",
          },
          llm_facts: { category: "credito", frustration: "alta", language: "pt", confidence: 0.82, source: "live" },
        }),
      ],
    });
    render(<AnalystWorkspace token="tk" />);

    const context = await screen.findByRole("region", { name: "Contexto" });
    expect(within(context).getByText("Cliente quer R$ 12 mil; o agente não pode aprovar valor alto.")).toBeInTheDocument();
    expect(within(context).getByText("Gerado por IA · openai/gpt-oss-120b")).toBeInTheDocument();
    expect(within(context).queryByText("Resumo por template")).not.toBeInTheDocument();
    expect(within(context).queryByText("Escalado pelo agente (motivo: credito_alto_valor).")).not.toBeInTheDocument();
    expect(within(context).getByText("categoria: credito")).toBeInTheDocument();
    expect(within(context).getByText("frustração: alta")).toBeInTheDocument();
  });

  it("troca o painel lateral para a cadeia de decisão da IA", async () => {
    window.location.hash = "#/fila/t1";
    mockApi({
      "GET /api/work": () => [200, { ...emptyWork, mine: [item({ mode: "human" })] }],
      "GET /api/tickets/t1": () => [200, detail()],
      "GET /api/tickets/t1/explanation": () => [
        200,
        { ticket_id: "t1", redacted_text: "oi", redactions: {}, trace_id: null, steps: [] },
      ],
    });
    render(<AnalystWorkspace token="tk" />);

    const tab = await screen.findByRole("tab", { name: "Por que a IA decidiu" });
    expect(screen.getByRole("tab", { name: "Contexto" })).toHaveAttribute("aria-selected", "true");
    await userEvent.click(tab);

    expect(tab).toHaveAttribute("aria-selected", "true");
    expect(await screen.findByRole("figure", { name: "Texto que a LLM recebeu" })).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Contexto" })).not.toBeInTheDocument();
  });

  it("avisa quando não há nada para pegar", async () => {
    mockApi({ "GET /api/work": () => [200, emptyWork], "POST /api/work/next": () => [204] });
    render(<AnalystWorkspace token="tk" />);

    expect(await screen.findByText("Fila vazia.")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Pegar o próximo" }));

    expect(await screen.findByRole("status")).toHaveTextContent("Nada esperando nas suas filas.");
  });

  it("responde ao cliente", async () => {
    window.location.hash = "#/fila/t1";
    let ticket = detail();
    const api = mockApi({
      "GET /api/work": () => [200, { ...emptyWork, mine: [item({ mode: "human" })] }],
      "GET /api/tickets/t1": () => [200, ticket],
      "POST /api/tickets/t1/messages": (body) => {
        const text = (body as { text: string }).text;
        ticket = { ...ticket, messages: [...ticket.messages, { id: "m3", seq: 3, sender: "analyst", text, stale: false, created_at: "2026-11-16T12:05:00.000Z" }] };
        return [201, { message_id: "m3", seq: 3, sla_met: true }];
      },
    });
    render(<AnalystWorkspace token="tk" />);

    const composer = await screen.findByLabelText("Resposta ao cliente");
    await userEvent.type(composer, "Oi, Maria, sou a Ana.");
    await userEvent.click(screen.getByRole("button", { name: "Enviar" }));

    const conversation = screen.getByRole("region", { name: "Conversa" });
    expect(await within(conversation).findByText("Oi, Maria, sou a Ana.")).toBeInTheDocument();
    expect(api.calls.find((call) => call.method === "POST")?.body).toEqual({ text: "Oi, Maria, sou a Ana." });
    expect(composer).toHaveValue("");
  });

  it("fecha só com uma resolução escolhida e volta para a fila", async () => {
    window.location.hash = "#/fila/t1";
    let work: Work = { ...emptyWork, mine: [item({ mode: "human" })] };
    const api = mockApi({
      "GET /api/work": () => [200, work],
      "GET /api/tickets/t1": () => [200, detail()],
      "POST /api/tickets/t1/close": () => {
        work = emptyWork;
        return [200, { id: "t1", mode: "closed" }];
      },
    });
    render(<AnalystWorkspace token="tk" />);

    await userEvent.click(await screen.findByRole("button", { name: "Fechar ticket" }));
    const dialog = await screen.findByRole("dialog", { name: "Fechar ticket" });
    const confirm = within(dialog).getByRole("button", { name: "Fechar" });
    expect(confirm).toBeDisabled();

    await userEvent.click(within(dialog).getByRole("radio", { name: "Resolvido" }));
    await userEvent.type(within(dialog).getByLabelText("Nota (opcional)"), "Limite liberado.");
    await userEvent.click(confirm);

    await waitFor(() => expect(window.location.hash).toBe("#/fila"));
    expect(api.calls.find((call) => call.path === "/api/tickets/t1/close")?.body).toEqual({
      resolution_code: "resolved",
      resolution_note: "Limite liberado.",
    });
    expect(await screen.findByText("Nenhum ticket com você.")).toBeInTheDocument();
  });
});
