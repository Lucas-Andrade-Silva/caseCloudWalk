import { fireEvent, render, screen, within } from "@testing-library/react";
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

  it("mostra a tela de carregamento até o retrato do mapa chegar", async () => {
    mockApi({ "GET /api/map": () => [200, { total: 1, limit: 500, tickets: [ticket("a", "credito")] }] });
    render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);

    expect(screen.getByRole("status")).toHaveTextContent("Abrindo o mapa vivo…");
    expect(await screen.findByText("1 tickets abertos")).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();
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

  it("destaca o incidente aberto: aviso no topo e os tickets dele contados", async () => {
    mockApi({
      "GET /api/map": () => [
        200,
        {
          total: 3,
          limit: 500,
          tickets: [ticket("a", "maquininha", { incident_id: "i1" }), ticket("b", "maquininha", { incident_id: "i1" }), ticket("c", "credito")],
        },
      ],
      "GET /api/incidents": () => [
        200,
        { incidents: [{ id: "i1", label: "maquininha", brand: "infinitepay", title: "Maquininhas não ligam", open_tickets: 2 }] },
      ],
    });
    render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);

    const alert = await screen.findByRole("region", { name: "Incidentes abertos" });
    expect(within(alert).getByText("Maquininhas não ligam")).toBeInTheDocument();
    expect(within(alert).getByText("2 tickets")).toBeInTheDocument();
    // Os tickets do incidente saem do grupo de origem e formam um grupo próprio no mapa.
    expect(await screen.findByRole("button", { name: "incidente · maquininha, 2 tickets" })).toBeInTheDocument();
    expect(groupCounts()).toEqual(["incidente · maquininha2", "credito1"]);
  });

  it("sem conexão, avisa e segue atualizando pelo retrato", async () => {
    mockApi({ "GET /api/map": () => [200, { total: 0, limit: 500, tickets: [] }] });
    render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
    await screen.findByText("0 tickets abertos");

    FakeSocket.last!.onclose?.();

    expect(await screen.findByText("Sem conexão ao vivo · atualizando a cada 5 s")).toBeInTheDocument();
  });

  describe("órbitas e zoom (ADR 0012)", () => {
    const three = () =>
      mockApi({
        "GET /api/map": () => [
          200,
          { total: 3, limit: 500, tickets: [ticket("a", "credito"), ticket("b", "credito"), ticket("c", "maquininha")] },
        ],
      });
    const group = (name: RegExp) => screen.getByRole("button", { name });
    const tickets = (container: HTMLElement) => [...container.querySelectorAll("[data-ticket]")].map((node) => node.getAttribute("data-ticket"));

    it("mostra cada grupo como um círculo em órbita, maior quanto mais tickets tem", async () => {
      three();
      render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);

      expect(await screen.findByRole("group", { name: "Mapa com 3 tickets em 2 grupos" })).toBeInTheDocument();
      const radius = (button: HTMLElement) => Number(button.querySelector(".map-bubble-body")!.getAttribute("r"));
      expect(radius(group(/credito, 2 tickets/))).toBeGreaterThan(radius(group(/maquininha, 1 ticket/)));
    });

    it("o círculo cresce quando chegam tickets daquele grupo", async () => {
      three();
      render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
      await screen.findByText("3 tickets abertos");
      const radius = () => Number(group(/maquininha, \d+ tickets?/).querySelector(".map-bubble-body")!.getAttribute("r"));
      const before = radius();

      FakeSocket.last!.receive({ type: "welcome" });
      FakeSocket.last!.receive({ identifier: "{}", message: { type: "ticket.upsert", ticket: ticket("d", "maquininha") } });
      FakeSocket.last!.receive({ identifier: "{}", message: { type: "ticket.upsert", ticket: ticket("e", "maquininha") } });

      await screen.findByText("5 tickets abertos");
      expect(radius()).toBeGreaterThan(before);
    });

    it("clicar no círculo dá zoom e abre os tickets do grupo, e voltar leva aos grupos", async () => {
      three();
      const { container } = render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
      await screen.findByText("3 tickets abertos");

      fireEvent.click(group(/credito, 2 tickets/));

      expect(await screen.findByRole("button", { name: "Todos os grupos" })).toBeInTheDocument();
      expect(screen.getByText("credito · 2 tickets")).toBeInTheDocument();
      expect(tickets(container).sort()).toEqual(["a", "b"]);
      expect(screen.queryByRole("button", { name: /maquininha, 1 ticket/ })).toBeNull();

      fireEvent.click(screen.getByRole("button", { name: "Todos os grupos" }));

      expect(group(/credito, 2 tickets/)).toBeInTheDocument();
      expect(tickets(container)).toEqual([]);
    });

    it("a legenda muda com a tela: grupos na visão geral, estados do ticket no zoom", async () => {
      three();
      render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
      await screen.findByText("3 tickets abertos");
      const legend = () => within(screen.getByRole("list", { name: "Como ler o mapa" })).getAllByRole("listitem").map((item) => item.textContent);

      expect(legend()).toContain("Grupocresce com os tickets");

      fireEvent.click(group(/credito, 2 tickets/));
      await screen.findByRole("button", { name: "Todos os grupos" });

      expect(legend()).toContain("Esperando humanoanel laranja");
      expect(legend()).not.toContain("Grupocresce com os tickets");
    });

    it("Esc também volta aos grupos", async () => {
      three();
      render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
      await screen.findByText("3 tickets abertos");
      fireEvent.click(group(/credito, 2 tickets/));
      await screen.findByRole("button", { name: "Todos os grupos" });

      fireEvent.keyDown(window, { key: "Escape" });

      expect(await screen.findByRole("button", { name: /credito, 2 tickets/ })).toBeInTheDocument();
    });

    it("volta sozinho aos grupos quando o grupo ampliado esvazia", async () => {
      three();
      render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
      await screen.findByText("3 tickets abertos");
      fireEvent.click(group(/maquininha, 1 ticket/));
      await screen.findByRole("button", { name: "Todos os grupos" });

      FakeSocket.last!.receive({ type: "welcome" });
      FakeSocket.last!.receive({ identifier: "{}", message: { type: "ticket.removed", id: "c" } });

      expect(await screen.findByRole("button", { name: /credito, 2 tickets/ })).toBeInTheDocument();
      expect(screen.queryByRole("button", { name: "Todos os grupos" })).toBeNull();
    });

    it("no zoom, clicar num ticket abre o atendimento dele para o analista", async () => {
      three();
      const { container } = render(<LiveMap token="tk" me={ana} socket={FakeSocket} />);
      await screen.findByText("3 tickets abertos");
      fireEvent.click(group(/credito, 2 tickets/));
      await screen.findByRole("button", { name: "Todos os grupos" });

      fireEvent.click(container.querySelector('[data-ticket="b"]')!);

      expect(window.location.hash).toBe("#/fila/b");
    });

    it("a operação vê os tickets no zoom, mas não abre a fila de um analista", async () => {
      three();
      const ops = { id: "u-ops", name: "Olivia", role: "ops" as const, brands: [] };
      window.location.hash = "#/mapa";
      const { container } = render(<LiveMap token="tk" me={ops} socket={FakeSocket} />);
      await screen.findByText("3 tickets abertos");
      fireEvent.click(group(/credito, 2 tickets/));
      await screen.findByRole("button", { name: "Todos os grupos" });

      fireEvent.click(container.querySelector('[data-ticket="a"]')!);

      expect(window.location.hash).toBe("#/mapa");
    });
  });
});
