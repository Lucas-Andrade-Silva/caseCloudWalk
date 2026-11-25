import { describe, expect, it } from "vitest";
import type { MapTicket } from "./model";
import { BUBBLE_MAX, bubbleRadius, layoutClusters, layoutTickets, ORBIT_RADII, position, ticketRadius, ZOOM_CORE } from "./orbit";
import { nodeRadius } from "./model";

const ticket = (id: string, priority = "p3", createdAt = "2026-11-17T12:00:00.000Z"): MapTicket => ({
  id,
  brand: "infinitepay",
  channel: "whatsapp",
  mode: "ai",
  priority,
  queue: null,
  tags: [],
  cluster: { key: "fila:credito", label: "credito" },
  assignee_id: null,
  created_at: createdAt,
  escalated_at: null,
  first_response_due_at: null,
  first_human_response_at: null,
  awaiting_agent_since: null,
});

const distance = (a: { orbit: number; angle: number }, b: { orbit: number; angle: number }) => {
  const [ax, ay] = position(a.orbit, a.angle);
  const [bx, by] = position(b.orbit, b.angle);
  return Math.hypot(ax - bx, ay - by);
};

describe("círculo do grupo", () => {
  it("cresce com a quantidade de tickets e para num teto", () => {
    expect(bubbleRadius(1)).toBeLessThan(bubbleRadius(4));
    expect(bubbleRadius(4)).toBeLessThan(bubbleRadius(16));
    expect(bubbleRadius(10_000)).toBe(BUBBLE_MAX);
  });
});

describe("grupos em órbita", () => {
  const clusters = (counts: number[]) => counts.map((count, index) => ({ key: `fila:g${index}`, count }));

  it("reparte os grupos pelas três órbitas, o maior na de dentro", () => {
    const slots = layoutClusters(clusters([40, 30, 20, 10, 5, 2, 1]));

    expect(slots).toHaveLength(7);
    expect(slots[0]!.ring).toBe(0);
    expect(new Set(slots.map((slot) => slot.ring))).toEqual(new Set([0, 1, 2]));
    for (const slot of slots) expect(slot.orbit).toBe(ORBIT_RADII[slot.ring]);
  });

  it("com poucos grupos, cada um fica numa órbita, para o desenho não ficar só no centro", () => {
    const slots = layoutClusters(clusters([9, 5, 2]));

    expect(slots.map((slot) => slot.ring)).toEqual([0, 1, 2]);
  });

  it("não deixa dois círculos se tocarem na mesma órbita", () => {
    const slots = layoutClusters(clusters([60, 50, 40, 30, 25, 20, 15, 12, 9, 6, 4, 2]));
    const radius = new Map(slots.map((slot) => [slot.key, slot.radius]));

    for (const a of slots) {
      for (const b of slots) {
        if (a.key >= b.key || a.ring !== b.ring) continue;
        expect(distance(a, b)).toBeGreaterThan(radius.get(a.key)! + radius.get(b.key)!);
      }
    }
  });

  it("um grupo só fica na primeira órbita e nenhum grupo devolve lista vazia", () => {
    expect(layoutClusters(clusters([3]))[0]!.ring).toBe(0);
    expect(layoutClusters([])).toEqual([]);
  });

  it("usa a última órbita para o que não couber nas anteriores, sem perder grupo", () => {
    const many = clusters(Array.from({ length: 40 }, () => 30));

    expect(layoutClusters(many)).toHaveLength(40);
  });
});

describe("tamanho dos tickets no zoom", () => {
  it("é bem maior que o ponto do mapa antigo, para ser fácil de clicar, e segue a prioridade", () => {
    for (const priority of ["p1", "p2", "p3", "p4"]) expect(ticketRadius(priority)).toBeGreaterThanOrEqual(nodeRadius(priority) * 1.8);
    expect(ticketRadius("p1")).toBeGreaterThan(ticketRadius("p3"));
    expect(ticketRadius("p3")).toBeGreaterThan(ticketRadius("p4"));
  });

  it("a primeira órbita deixa folga entre o grupo no centro e o maior ticket", () => {
    const { slots } = layoutTickets([ticket("a", "p1")]);

    expect(slots[0]!.orbit - ticketRadius("p1")).toBeGreaterThan(ZOOM_CORE + 8);
  });
});

describe("tickets em órbita dentro do grupo", () => {
  it("põe os mais urgentes nas órbitas de dentro", () => {
    const { slots } = layoutTickets([ticket("baixa", "p4"), ticket("urgente", "p1"), ticket("media", "p3")]);
    const ring = (id: string) => slots.find((slot) => slot.id === id)!.orbit;

    expect(ring("urgente")).toBeLessThanOrEqual(ring("media"));
    expect(ring("media")).toBeLessThanOrEqual(ring("baixa"));
  });

  it("abre mais órbitas quando há muitos tickets, e a área cresce junto", () => {
    const few = layoutTickets(Array.from({ length: 5 }, (_, index) => ticket(`f${index}`)));
    const many = layoutTickets(Array.from({ length: 200 }, (_, index) => ticket(`m${index}`)));

    expect(many.rings).toBeGreaterThan(few.rings);
    expect(many.extent).toBeGreaterThan(few.extent);
    expect(many.slots).toHaveLength(200);
  });

  it("nenhum ticket encosta em outro da mesma órbita", () => {
    const { slots } = layoutTickets(Array.from({ length: 120 }, (_, index) => ticket(`t${index}`, index % 5 === 0 ? "p1" : "p3")));

    for (const a of slots) {
      for (const b of slots) {
        if (a.id >= b.id || a.ring !== b.ring) continue;
        expect(distance(a, b)).toBeGreaterThanOrEqual(2 * ticketRadius("p1"));
      }
    }
  });

  it("é estável: a mesma lista dá o mesmo desenho", () => {
    const list = Array.from({ length: 30 }, (_, index) => ticket(`t${index}`, `p${(index % 4) + 1}`));

    expect(layoutTickets(list)).toEqual(layoutTickets([...list].reverse()));
  });
});
