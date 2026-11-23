// Cores dos grupos do mapa. Cada grupo novo recebe a próxima cor livre e a mantém enquanto existir: a ordem por
// tamanho muda o tempo todo, e a cor de um grupo não pode pular. Com mais grupos que cores, elas se repetem.
// Sem verde puro nem laranja: são as cores dos anéis "com humano" e "esperando humano".
export const PALETTE = ["#6f95ff", "#4cc3d9", "#e8d44d", "#e36f9c", "#c9a7ff", "#9fd36b", "#ecebe9", "#f2b8a0", "#7fb8ff", "#d4b483"];

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
