// Agrupa eventos que chegam em rajada e os entrega juntos a cada `windowMs` (~250 ms no mapa vivo): um
// pico de mil eventos vira poucas atualizações de tela, não mil.
export function createBatcher<T>(flush: (items: T[]) => void, windowMs: number) {
  let pending: T[] = [];
  let timer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;

  return {
    push(item: T) {
      if (stopped) return;
      pending.push(item);
      timer ??= setTimeout(() => {
        const items = pending;
        pending = [];
        timer = null;
        if (!stopped) flush(items);
      }, windowMs);
    },
    stop() {
      stopped = true;
      if (timer) clearTimeout(timer);
      pending = [];
    },
  };
}
