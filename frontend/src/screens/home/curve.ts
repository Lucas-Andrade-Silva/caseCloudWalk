// Geometria da curva de volume da tela inicial (ADR 0010, H6). Funções puras: o SVG só desenha o que sai daqui.

export interface Point {
  x: number;
  y: number;
}

/** Índice do maior valor (o primeiro, em empate); -1 sem valores. */
export function peakIndex(values: number[]): number {
  if (values.length === 0) return -1;
  return values.reduce((best, value, index) => (value > values[best]! ? index : best), 0);
}

/** Espalha os valores pela largura; o maior fica em `top` e o zero no fundo. */
export function curvePoints(values: number[], width: number, height: number, top: number): Point[] {
  const max = Math.max(...values, 1);
  const step = values.length > 1 ? width / (values.length - 1) : 0;
  return values.map((value, index) => ({ x: index * step, y: height - (value / max) * (height - top) }));
}

/**
 * Catmull-Rom convertido em Bézier cúbicas: suave e passando por todos os pontos. Os pontos de controle ficam
 * dentro da faixa dos dados, para a curva não afundar abaixo do zero.
 */
export function smoothPath(points: Point[]): string {
  if (points.length === 0) return "";
  const ys = points.map((point) => point.y);
  const low = Math.min(...ys);
  const high = Math.max(...ys);
  const round = (n: number) => Math.round(n * 100) / 100;
  const clamp = (y: number) => Math.min(high, Math.max(low, y));
  let path = `M ${round(points[0]!.x)} ${round(points[0]!.y)}`;
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[i - 1] ?? points[i]!;
    const p1 = points[i]!;
    const p2 = points[i + 1]!;
    const p3 = points[i + 2] ?? p2;
    const c1 = { x: p1.x + (p2.x - p0.x) / 6, y: clamp(p1.y + (p2.y - p0.y) / 6) };
    const c2 = { x: p2.x - (p3.x - p1.x) / 6, y: clamp(p2.y - (p3.y - p1.y) / 6) };
    path += ` C ${round(c1.x)} ${round(c1.y)}, ${round(c2.x)} ${round(c2.y)}, ${round(p2.x)} ${round(p2.y)}`;
  }
  return path;
}
