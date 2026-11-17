// Cores dos grupos do mapa. Cada grupo novo recebe a próxima cor livre e a mantém enquanto existir: a ordem por
// tamanho muda o tempo todo, e a cor de um grupo não pode pular. Com mais grupos que cores, elas se repetem.
export const PALETTE = ["#6b74f0", "#3fd37c", "#f2a93b", "#e36f9c", "#4cc3d9", "#b48cf2", "#e8d44d", "#f07f5a", "#7fb8ff", "#9fd36b"];

export function assignColors(keys: string[], previous: ReadonlyMap<string, string>): Map<string, string> {
  const next = new Map<string, string>();
  for (const key of keys) {
    const kept = previous.get(key);
    if (kept) next.set(key, kept);
  }
  let cursor = 0;
  for (const key of keys) {
    if (next.has(key)) continue;
    const used = new Set(next.values());
    const free = PALETTE.find((color) => !used.has(color));
    next.set(key, free ?? PALETTE[cursor++ % PALETTE.length]!);
  }
  return next;
}
