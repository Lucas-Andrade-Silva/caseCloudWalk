import { describe, expect, it } from "vitest";
import { categoryLabel, dueLabel, resolutionLabel } from "./format";

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

describe("resolução na memória do cliente", () => {
  it("nomeia também o fechamento automático da IA, e mostra o código quando não conhece", () => {
    expect(resolutionLabel("resolved")).toBe("Resolvido");
    expect(resolutionLabel("ai_resolved")).toBe("Resolvido pela IA");
    expect(resolutionLabel("outro_codigo")).toBe("outro_codigo");
  });
});

describe("assunto de um ticket", () => {
  it("começa com maiúscula e diz quando não há categoria", () => {
    expect(categoryLabel("maquininha")).toBe("Maquininha");
    expect(categoryLabel("conta_cadastro")).toBe("Conta cadastro");
    expect(categoryLabel(null)).toBe("Sem categoria");
    expect(categoryLabel("")).toBe("Sem categoria");
  });
});
