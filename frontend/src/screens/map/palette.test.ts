import { describe, expect, it } from "vitest";
import { assignColors, PALETTE } from "./palette";

describe("cores dos grupos", () => {
  it("dá uma cor diferente para cada grupo enquanto houver cor na paleta", () => {
    const keys = PALETTE.map((_, index) => `fila:${index}`);

    const colors = assignColors(keys, new Map());

    expect(new Set(colors.values()).size).toBe(PALETTE.length);
  });

  it("mantém a cor de quem já tinha, mesmo quando a ordem muda e grupos somem", () => {
    const first = assignColors(["fila:a", "fila:b", "fila:c"], new Map());

    const second = assignColors(["fila:c", "fila:d", "fila:a"], first);

    expect(second.get("fila:a")).toBe(first.get("fila:a"));
    expect(second.get("fila:c")).toBe(first.get("fila:c"));
    expect(second.get("fila:d")).toBe(first.get("fila:b"));
    expect(second.has("fila:b")).toBe(false);
  });

  it("repete cores só quando há mais grupos que cores", () => {
    const keys = [...PALETTE, "extra"].map((_, index) => `fila:${index}`);

    const colors = assignColors(keys, new Map());

    expect(colors.size).toBe(PALETTE.length + 1);
    expect(PALETTE).toContain(colors.get(`fila:${PALETTE.length}`));
  });
});
