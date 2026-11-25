import { describe, expect, it } from "vitest";
import { applyEvents, atRisk, capNodes, fromSnapshot, nodeRadius, summarize, summarizeIncident, type MapTicket } from "./model";

const now = new Date("2026-11-17T12:00:00.000Z");

const ticket = (overrides: Partial<MapTicket> = {}): MapTicket => ({
  id: "t1",
  brand: "infinitepay",
  channel: "whatsapp",
  mode: "ai",
  priority: "p3",
  queue: null,
  tags: [],
  cluster: { key: "marca:infinitepay", label: "InfinitePay sem fila" },
  assignee_id: null,
  created_at: "2026-11-17T11:59:00.000Z",
  escalated_at: null,
  first_response_due_at: null,
  first_human_response_at: null,
  awaiting_agent_since: null,
  ...overrides,
});

describe("modelo do mapa vivo", () => {
  it("aplica eventos: entra, muda e sai", () => {
    const start = fromSnapshot([ticket({ id: "a" }), ticket({ id: "b" })]);

    const next = applyEvents(start, [
      { type: "ticket.upsert", ticket: ticket({ id: "c", priority: "p1" }) },
      { type: "ticket.upsert", ticket: ticket({ id: "a", mode: "pending_human" }) },
      { type: "ticket.removed", id: "b" },
      { type: "ticket.removed", id: "nao-existe" },
    ]);

    expect([...next.keys()]).toEqual(["a", "c"]);
    expect(next.get("a")?.mode).toBe("pending_human");
    expect(start.size).toBe(2);
  });

  it("pulsa quem corre risco: prazo humano perto de vencer ou vencido, ou o agente calado há mais de 20 s", () => {
    expect(atRisk(ticket({ mode: "pending_human", first_response_due_at: "2026-11-17T12:09:00.000Z" }), now)).toBe(true);
    expect(atRisk(ticket({ mode: "human", first_response_due_at: "2026-11-17T11:50:00.000Z" }), now)).toBe(true);
    expect(atRisk(ticket({ mode: "pending_human", first_response_due_at: "2026-11-17T12:30:00.000Z" }), now)).toBe(false);
    expect(
      atRisk(ticket({ mode: "human", first_response_due_at: "2026-11-17T11:50:00.000Z", first_human_response_at: "2026-11-17T11:49:00.000Z" }), now),
    ).toBe(false);
    expect(atRisk(ticket({ mode: "ai", awaiting_agent_since: "2026-11-17T11:59:35.000Z" }), now)).toBe(true);
    expect(atRisk(ticket({ mode: "ai", awaiting_agent_since: "2026-11-17T11:59:50.000Z" }), now)).toBe(false);
  });

  it("dá tamanho pela prioridade", () => {
    expect(["p1", "p2", "p3", "p4"].map((priority) => nodeRadius(priority))).toEqual([9, 7, 5.5, 4.5]);
  });

  it("resume os clusters, maiores primeiro, com quantos correm risco", () => {
    const tickets = [
      ticket({ id: "a", cluster: { key: "tag:alto_valor", label: "alto_valor" }, mode: "pending_human", first_response_due_at: "2026-11-17T11:00:00.000Z" }),
      ticket({ id: "b", cluster: { key: "fila:x", label: "x" } }),
      ticket({ id: "c", cluster: { key: "fila:x", label: "x" } }),
    ];

    expect(summarize(tickets, now)).toEqual([
      { key: "fila:x", label: "x", count: 2, atRisk: 0 },
      { key: "tag:alto_valor", label: "alto_valor", count: 1, atRisk: 1 },
    ]);
  });

  it("desenha no máximo o teto e conta a sobra, prioridades altas primeiro", () => {
    const tickets = [ticket({ id: "p4", priority: "p4" }), ticket({ id: "p1", priority: "p1" }), ticket({ id: "p2", priority: "p2" })];

    const { visible, hidden } = capNodes(tickets, 2);

    expect(visible.map((t) => t.id)).toEqual(["p1", "p2"]);
    expect(hidden).toBe(1);
  });
  it("resume um incidente: contagem por situação, risco, urgentes e o mais antigo", () => {
    const tickets = [
      ticket({ id: "a", incident_id: "i1", mode: "pending_human", priority: "p1", created_at: "2026-11-17T11:40:00.000Z", first_response_due_at: "2026-11-17T12:05:00.000Z" }),
      ticket({ id: "b", incident_id: "i1", mode: "human", created_at: "2026-11-17T11:50:00.000Z" }),
      ticket({ id: "c", incident_id: "i1", mode: "ai" }),
      ticket({ id: "d", incident_id: "outro", mode: "ai" }),
      ticket({ id: "e" }),
    ];

    expect(summarizeIncident(tickets, "i1", now)).toEqual({
      count: 3,
      pendingHuman: 1,
      human: 1,
      ai: 1,
      urgent: 1,
      atRisk: 1,
      oldestAt: "2026-11-17T11:40:00.000Z",
    });
    expect(summarizeIncident(tickets, "nenhum", now)).toEqual({ count: 0, pendingHuman: 0, human: 0, ai: 0, urgent: 0, atRisk: 0, oldestAt: null });
  });
});
