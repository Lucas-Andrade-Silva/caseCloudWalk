import { describe, expect, it } from "vitest";
import { curvePoints, peakIndex, smoothPath } from "./curve";

describe("curva do volume", () => {
  it("acha o pico, ficando com o primeiro em caso de empate", () => {
    expect(peakIndex([1, 4, 2, 4])).toBe(1);
    expect(peakIndex([])).toBe(-1);
  });

  it("espalha os pontos pela largura e põe o maior valor no topo", () => {
    const points = curvePoints([0, 5, 10], 200, 100, 10);
    expect(points).toEqual([
      { x: 0, y: 100 },
      { x: 100, y: 55 },
      { x: 200, y: 10 },
    ]);
  });

  it("desenha uma curva que passa por todos os pontos", () => {
    const path = smoothPath([
      { x: 0, y: 10 },
      { x: 50, y: 0 },
      { x: 100, y: 10 },
    ]);
    expect(path.startsWith("M 0 10")).toBe(true);
    expect(path).toContain(" 50 0");
    expect(path.endsWith(" 100 10")).toBe(true);
  });

  it("não deixa a curva passar abaixo do zero", () => {
    const path = smoothPath([
      { x: 0, y: 100 },
      { x: 50, y: 100 },
      { x: 100, y: 0 },
    ]);
    const ys = path.match(/-?[\d.]+/g)!.map(Number).filter((_, index) => index % 2 === 1);
    expect(Math.max(...ys)).toBeLessThanOrEqual(100);
  });
});
