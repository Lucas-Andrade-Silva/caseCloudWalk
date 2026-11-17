import { describe, expect, it } from "vitest";
import { dueLabel } from "./format";

describe("prazo da primeira resposta", () => {
  const now = new Date("2026-11-16T12:10:00.000Z");

  it("diz quanto falta, quanto passou ou que já foi respondido", () => {
    expect(dueLabel("2026-11-16T12:15:00.000Z", null, now)).toEqual({ text: "vence em 5 min", tone: "warning" });
    expect(dueLabel("2026-11-16T13:00:00.000Z", null, now)).toEqual({ text: "vence em 50 min", tone: "neutral" });
    expect(dueLabel("2026-11-16T12:07:00.000Z", null, now)).toEqual({ text: "atrasou 3 min", tone: "danger" });
    expect(dueLabel("2026-11-16T12:15:00.000Z", "2026-11-16T12:09:00.000Z", now)).toEqual({ text: "respondido", tone: "success" });
    expect(dueLabel(null, null, now)).toEqual({ text: "sem prazo", tone: "neutral" });
  });
});
