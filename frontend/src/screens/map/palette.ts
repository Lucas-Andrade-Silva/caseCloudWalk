// Cores dos grupos do mapa. Cada grupo novo recebe a próxima cor livre e a mantém enquanto existir: a ordem por
// tamanho muda o tempo todo, e a cor de um grupo não pode pular. Com mais grupos que cores, elas se repetem.
// Sem verde puro nem laranja: são as cores dos anéis "com humano" e "esperando humano".
export const PALETTE = ["#2a78d6", "#6250d6", "#e87ba4", "#eda100", "#0891b2", "#8b5cf6", "#64748b", "#db2777", "#0ea5e9", "#a16207"];

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
