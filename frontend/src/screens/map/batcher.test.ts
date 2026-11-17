import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createBatcher } from "./batcher";

describe("agrupamento de eventos", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("entrega os eventos juntos uma vez por janela, na ordem em que chegaram", () => {
    const flush = vi.fn();
    const batcher = createBatcher<number>(flush, 250);

    batcher.push(1);
    batcher.push(2);
    vi.advanceTimersByTime(249);
    expect(flush).not.toHaveBeenCalled();

    vi.advanceTimersByTime(1);
    expect(flush).toHaveBeenCalledExactlyOnceWith([1, 2]);

    batcher.push(3);
    vi.advanceTimersByTime(250);
    expect(flush).toHaveBeenLastCalledWith([3]);
  });

  it("não entrega nada depois de parado", () => {
    const flush = vi.fn();
    const batcher = createBatcher<number>(flush, 250);

    batcher.push(1);
    batcher.stop();
    vi.advanceTimersByTime(1000);

    expect(flush).not.toHaveBeenCalled();
  });
});
