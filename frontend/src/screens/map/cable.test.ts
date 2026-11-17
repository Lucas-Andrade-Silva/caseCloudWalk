import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { connectMap, tokenProtocol, type SocketLike } from "./cable";

class FakeSocket implements SocketLike {
  static last: FakeSocket | null = null;
  sent: unknown[] = [];
  closed = false;
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;

  constructor(
    readonly url: string,
    readonly protocols: string[],
  ) {
    FakeSocket.last = this;
  }

  send(data: string) {
    this.sent.push(JSON.parse(data));
  }

  close() {
    this.closed = true;
  }

  receive(frame: unknown) {
    this.onmessage?.({ data: JSON.stringify(frame) });
  }
}

describe("cliente do canal do mapa", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    FakeSocket.last = null;
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("leva o token no subprotocolo, em base64url, e nunca na URL", () => {
    expect(tokenProtocol("dev-analyst-ana")).toBe("helpdesk-token.ZGV2LWFuYWx5c3QtYW5h");

    connectMap({ url: "/cable", token: "dev-analyst-ana", brands: ["infinitepay"], onEvent: vi.fn(), onStatus: vi.fn(), socket: FakeSocket });

    expect(FakeSocket.last?.url).toBe("/cable");
    expect(FakeSocket.last?.protocols).toEqual(["actioncable-v1-json", "helpdesk-token.ZGV2LWFuYWx5c3QtYW5h"]);
  });

  it("assina cada marca depois do welcome e repassa só os eventos", () => {
    const onEvent = vi.fn();
    const onStatus = vi.fn();
    connectMap({ url: "/cable", token: "tk", brands: ["infinitepay", "jim"], onEvent, onStatus, socket: FakeSocket });
    const socket = FakeSocket.last!;

    socket.receive({ type: "welcome" });
    expect(socket.sent).toEqual([
      { command: "subscribe", identifier: JSON.stringify({ channel: "MapChannel", brand: "infinitepay" }) },
      { command: "subscribe", identifier: JSON.stringify({ channel: "MapChannel", brand: "jim" }) },
    ]);

    socket.receive({ type: "confirm_subscription", identifier: "{}" });
    expect(onStatus).toHaveBeenLastCalledWith("live");

    socket.receive({ type: "ping", message: 123 });
    socket.receive({ identifier: "{}", message: { type: "ticket.removed", id: "t1" } });
    expect(onEvent).toHaveBeenCalledExactlyOnceWith({ type: "ticket.removed", id: "t1" });
  });

  it("avisa que caiu e tenta de novo com espera crescente, até ser fechado", () => {
    const onStatus = vi.fn();
    const connection = connectMap({ url: "/cable", token: "tk", brands: ["infinitepay"], onEvent: vi.fn(), onStatus, socket: FakeSocket });
    const first = FakeSocket.last!;

    first.onclose?.();
    expect(onStatus).toHaveBeenLastCalledWith("offline");
    vi.advanceTimersByTime(1000);
    expect(FakeSocket.last).not.toBe(first);

    const second = FakeSocket.last!;
    second.onclose?.();
    vi.advanceTimersByTime(1000);
    expect(FakeSocket.last).toBe(second);
    vi.advanceTimersByTime(1000);
    expect(FakeSocket.last).not.toBe(second);

    connection.close();
    const third = FakeSocket.last!;
    expect(third.closed).toBe(true);
    third.onclose?.();
    vi.advanceTimersByTime(60_000);
    expect(FakeSocket.last).toBe(third);
  });
});
