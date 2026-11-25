import { describe, expect, it } from "vitest";
import type { MapTicket } from "../map/model";
import { situation } from "./situation";

const now = new Date("2026-11-22T18:00:00.000Z");
const t = (o: Partial<MapTicket> = {}): MapTicket => ({
  id: Math.random().toString(36),
  brand: "infinitepay",
  channel: "whatsapp",
  mode: "ai",
  priority: "p3",
  queue: null,
  tags: [],
  cluster: { key: "a", label: "pix" },
  assignee_id: null,
  created_at: "2026-11-22T10:00:00.000Z",
  escalated_at: null,
  first_response_due_at: null,
  first_human_response_at: null,
  awaiting_agent_since: null,
  ...o,
});
const risky = { mode: "pending_human" as const, first_response_due_at: "2000-01-01T00:00:00.000Z" };

describe("situação da operação", () => {
  it("estável sem incidente e sem risco", () => {
    expect(situation([t(), t()], 0, now)).toMatchObject({ level: "estavel", word: "Estável", risky: 0, lastHour: 0 });
  });

  it("atenção com incidente aberto, e conta o que entrou na última hora", () => {
    const tickets = [
      t({ created_at: "2026-11-22T17:40:00.000Z" }),
      t({ created_at: "2026-11-22T17:50:00.000Z" }),
      t(),
    ];
    expect(situation(tickets, 1, now)).toMatchObject({ level: "atencao", word: "Atenção", risky: 0, lastHour: 2 });
  });

  it("crítico com incidente e tickets perto de estourar o prazo", () => {
    expect(situation([t(risky)], 1, now)).toMatchObject({ level: "critico", word: "Crítico" });
  });
});
