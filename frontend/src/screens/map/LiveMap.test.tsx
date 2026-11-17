import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mockApi } from "../../test/mockApi";
import type { SocketLike } from "./cable";
import { LiveMap } from "./LiveMap";
import type { MapTicket } from "./model";

class FakeSocket implements SocketLike {
  static last: FakeSocket | null = null;
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  sent: string[] = [];

  constructor(
    readonly url: string,
    readonly protocols: string[],
  ) {
    FakeSocket.last = this;
  }

  send(data: string) {
    this.sent.push(data);
  }

  close() {}

  receive(frame: unknown) {
    this.onmessage?.({ data: JSON.stringify(frame) });
  }
}

const ticket = (id: string, cluster: string, overrides: Partial<MapTicket> = {}): MapTicket => ({
  id,
  brand: "infinitepay",
  channel: "whatsapp",
  mode: "ai",
  priority: "p3",
  queue: null,
  tags: [],
  cluster: { key: `fila:${cluster}`, label: cluster },
  assignee_id: null,
  created_at: "2026-11-17T12:00:00.000Z",
  escalated_at: null,
  first_response_due_at: null,
  first_human_response_at: null,
  awaiting_agent_since: null,
  ...overrides,
});

const ana = { id: "u-ana", name: "Ana", role: "analyst" as const, brands: ["infinitepay"] };

function groupCounts() {
  const groups = screen.getByRole("list", { name: "Grupos do mapa" });
  return within(groups)
    .getAllByRole("listitem")
    .map((item) => item.textContent);
}

describe("mapa vivo", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra o retrato e muda ao vivo com os eventos do canal", async () => {
    mockApi({
      "GET /api/map": () => [
        200,
        { total: 3, limit: 500, tickets: [ticket("a", "credito"), ticket("b", "credito"), ticket("c", "maquininha")] },
      ],
    });
    render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);

    expect(await screen.findByText("3 tickets abertos")).toBeInTheDocument();
    expect(groupCounts()).toEqual(["credito2", "maquininha1"]);

    const socket = FakeSocket.last!;
    socket.receive({ type: "welcome" });
    expect(socket.sent).toEqual([JSON.stringify({ command: "subscribe", identifier: JSON.stringify({ channel: "MapChannel", brand: "infinitepay" }) })]);
    socket.receive({ type: "confirm_subscription", identifier: "{}" });
    expect(await screen.findByText("Ao vivo")).toBeInTheDocument();

    socket.receive({ identifier: "{}", message: { type: "ticket.upsert", ticket: ticket("d", "maquininha") } });
    socket.receive({ identifier: "{}", message: { type: "ticket.upsert", ticket: ticket("e", "maquininha") } });
    socket.receive({ identifier: "{}", message: { type: "ticket.removed", id: "a" } });

    expect(await screen.findByText("4 tickets abertos")).toBeInTheDocument();
    expect(groupCounts()).toEqual(["maquininha3", "credito1"]);
  });

  it("avisa quem corre risco no grupo", async () => {
    mockApi({
      "GET /api/map": () => [
        200,
        {
          total: 1,
          limit: 500,
          tickets: [ticket("a", "credito", { mode: "pending_human", first_response_due_at: "2000-01-01T00:00:00.000Z" })],
        },
      ],
    });
    render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);

    expect(await screen.findByText("1 em risco")).toBeInTheDocument();
  });

  it("sem conexão, avisa e segue atualizando pelo retrato", async () => {
    mockApi({ "GET /api/map": () => [200, { total: 0, limit: 500, tickets: [] }] });
    render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
    await screen.findByText("0 tickets abertos");

    FakeSocket.last!.onclose?.();

    expect(await screen.findByText("Sem conexão ao vivo · atualizando a cada 5 s")).toBeInTheDocument();
  });
});
