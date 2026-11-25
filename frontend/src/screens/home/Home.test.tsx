import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { DashboardMetrics } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { Home } from "./Home";

const ana = { id: "u-ana", name: "Ana", role: "analyst" as const, brands: ["infinitepay"] };
const olivia = { id: "u-olivia", name: "Olivia", role: "ops" as const, brands: [] };

const metrics: DashboardMetrics = {
  generated_at: "2026-11-22T18:00:00.000Z",
  time_zone: "America/Sao_Paulo",
  open: { total: 12, ai: 7, pending_human: 3, human: 2, incidents: 1 },
  today: { created: 9, closed: 4 },
  yesterday: { created: 6, closed: 8 },
  daily: [
    { date: "2026-11-16", created: 1, closed: 0 },
    { date: "2026-11-17", created: 2, closed: 1 },
    { date: "2026-11-18", created: 11, closed: 0 },
    { date: "2026-11-19", created: 0, closed: 0 },
    { date: "2026-11-20", created: 3, closed: 3 },
    { date: "2026-11-21", created: 6, closed: 8 },
    { date: "2026-11-22", created: 9, closed: 4 },
  ],
  first_reply: { mean_seconds: 1200, answered: 3, buckets: [] },
  sla: { met: 3, missed: 1 },
  resolution: { ai: 3, human: 1 },
  channels: [{ channel: "whatsapp", count: 12 }],
  resolution_time: { median_seconds: 120_720, ai_median_seconds: 1800, human_median_seconds: 7200, resolved: 4 },
  team: {
    active: 1,
    total: 2,
    agents: [
      { id: "u-ana", name: "Ana Lima", resolved: 5, open: 1, reply_median_seconds: 300, sla_percent: 96 },
      { id: "u-bia", name: "Bia Rocha", resolved: 0, open: 0, reply_median_seconds: null, sla_percent: null },
    ],
  },
  operations: {
    stale: 18,
    unassigned: 1,
    tickets: [
      { id: "0f3a9c21-0000-0000-0000-000000000000", agent: null, agent_id: null, priority: "p1", brand: "infinitepay", mode: "pending_human", subject: "Pix não caiu" },
      { id: "7b21e044-0000-0000-0000-000000000000", agent: "Ana Lima", agent_id: "u-ana", priority: "p3", brand: "jim", mode: "human", subject: "Maquininha travou" },
    ],
  },
};

const incident = {
  id: "i1",
  key: "pix",
  label: "Pix",
  brand: "infinitepay",
  status: "open",
  title: "Pix fora do ar",
  draft_reply: "",
  title_source: "template",
  model: null,
  opened_at: "2026-11-22T17:50:00.000Z",
  resolved_at: null,
  open_tickets: 6,
  total_tickets: 6,
};

function api(extra: Record<string, () => [number, unknown]> = {}) {
  return mockApi({
    "GET /api/dashboard": () => [200, metrics],
    "GET /api/incidents": () => [200, { incidents: [incident] }],
    "GET /api/map": () => [200, { total: 0, limit: 500, tickets: [] }],
    "GET /api/work": () => [200, { mine: [], waiting: [], waiting_count: 4 }],
    ...extra,
  });
}

// O primeiro link de cada card é o título, que cobre o card inteiro; os outros links (analistas) são dos detalhes.
const cardHrefs = () =>
  within(screen.getByRole("region", { name: "Atalhos" }))
    .getAllByRole("article")
    .map((card) => card.querySelector("a")!)
    .map((link) => [link.textContent, link.getAttribute("href")]);

describe("tela inicial em cards", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra ao analista os cards da área dele, cada um levando ao detalhe", async () => {
    api();
    render(<Home token="tk" me={ana} />);

    expect(await screen.findByText(/^Suas marcas · atualizado às/)).toBeInTheDocument();
    expect(cardHrefs()).toEqual([
      ["Volume de tickets", "#/painel"],
      ["Resolvidos pela IA", "#/painel"],
      ["SLA da primeira resposta", "#/painel"],
      ["Mapa vivo", "#/mapa"],
      ["Tempo de solução", "#/solucao"],
      ["Modo Incidente", "#/fila"],
      ["Fila", "#/fila"],
      ["Desempenho do time", "#/time"],
      ["Operação dos tickets", "#/tickets"],
    ]);
  });

  it("mostra à operação a visão de tudo, com filas e regras no lugar da fila", async () => {
    api();
    render(<Home token="tk" me={olivia} />);

    expect(await screen.findByText(/^Todas as marcas · atualizado às/)).toBeInTheDocument();
    const labels = cardHrefs().map(([label]) => label);
    expect(labels).toContain("Filas e regras");
    expect(labels).not.toContain("Fila");
    expect(cardHrefs()).toContainEqual(["Modo Incidente", "#/mapa"]);
  });

  it("marca o pico da curva de volume e mostra os números reais", async () => {
    api();
    render(<Home token="tk" me={ana} />);

    expect(await screen.findByText("11 · Pico")).toBeInTheDocument();
    const volume = screen.getByRole("table", { name: "Tickets criados por dia" });
    expect(within(volume).getAllByRole("row")).toHaveLength(8);
    expect(screen.getByRole("article", { name: "Resolvidos pela IA" })).toHaveTextContent("75%");
    expect(screen.getByRole("article", { name: "SLA da primeira resposta" })).toHaveTextContent("75%");
    expect(screen.getByRole("list", { name: "Incidentes abertos" })).toHaveTextContent("Pix fora do ar");
    expect(screen.getByRole("article", { name: "Fila" })).toHaveTextContent("4");
  });

  it("mostra tempo de solução, desempenho do time e operação dos tickets com os números da plataforma", async () => {
    api();
    render(<Home token="tk" me={olivia} />);

    const solution = await screen.findByRole("article", { name: "Tempo de solução" });
    await within(solution).findByText("Meta 8h");
    expect(solution).toHaveTextContent("33h32m");
    expect(solution).toHaveTextContent("Meta 8h");

    const team = screen.getByRole("table", { name: "Desempenho por analista" });
    const rows = within(team).getAllByRole("row");
    expect(rows[1]).toHaveTextContent("Ana Lima");
    expect(rows[1]).toHaveTextContent("5");
    expect(rows[1]).toHaveTextContent("5min");
    expect(rows[1]).toHaveTextContent("96%");
    expect(rows[2]).toHaveTextContent("—");
    expect(rows[1]!.querySelector("img")).toHaveAttribute("src", "/avatars/ana.jpg");
    expect(rows[2]!.querySelector("img")).toBeNull();
    expect(screen.getByRole("article", { name: "Desempenho do time" })).toHaveTextContent("1/2");
    // Cada analista leva ao detalhe dele, na lista do time e na dos tickets.
    expect(within(rows[1]!).getByRole("link", { name: "Ana Lima" })).toHaveAttribute("href", "#/analista/u-ana");
    expect(within(rows[2]!).getByRole("link", { name: "Bia Rocha" })).toHaveAttribute("href", "#/analista/u-bia");

    const operations = screen.getByRole("article", { name: "Operação dos tickets" });
    expect(within(operations).getByRole("group", { name: "Tickets parados" })).toHaveTextContent("18");
    expect(within(operations).getByRole("group", { name: "Sem analista" })).toHaveTextContent("1");
    const tickets = within(operations).getAllByRole("row");
    expect(tickets[1]).toHaveTextContent("#0F3A9C");
    expect(tickets[1]).toHaveTextContent("Pix não caiu");
    expect(tickets[1]).toHaveTextContent("Urgente");
    expect(tickets[2]).toHaveTextContent("Ana Lima");
    expect(within(tickets[2]!).getByRole("link", { name: "Ana Lima" })).toHaveAttribute("href", "#/analista/u-ana");
    expect(within(tickets[1]!).queryByRole("link")).toBeNull();
  });

  it("mostra a tela de carregamento até os dados da tela inicial chegarem", async () => {
    api();
    render(<Home token="tk" me={ana} />);

    expect(screen.getByRole("status")).toHaveTextContent("Montando a tela inicial…");
    expect(screen.queryByRole("region", { name: "Atalhos" })).toBeNull();

    expect(await screen.findByText(/^Suas marcas · atualizado às/)).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();
  });

  it("não fica preso no carregamento quando um dos dados falha", async () => {
    api({ "GET /api/dashboard": () => [500, { error: "x" }] });
    render(<Home token="tk" me={ana} />);

    expect(await screen.findByRole("region", { name: "Atalhos" })).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();
  });
});
