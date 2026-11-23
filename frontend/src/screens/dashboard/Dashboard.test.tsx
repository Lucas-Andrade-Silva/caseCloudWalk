import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { DashboardMetrics } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { Dashboard } from "./Dashboard";

const ana = { id: "u-ana", name: "Ana", role: "analyst" as const, brands: ["infinitepay"] };

const metrics: DashboardMetrics = {
  generated_at: "2026-11-22T18:00:00.000Z",
  time_zone: "America/Sao_Paulo",
  open: { total: 12, ai: 7, pending_human: 3, human: 2, incidents: 1 },
  today: { created: 9, closed: 4 },
  yesterday: { created: 6, closed: 8 },
  daily: [
    { date: "2026-11-16", created: 0, closed: 0 },
    { date: "2026-11-17", created: 2, closed: 1 },
    { date: "2026-11-18", created: 0, closed: 0 },
    { date: "2026-11-19", created: 0, closed: 0 },
    { date: "2026-11-20", created: 3, closed: 3 },
    { date: "2026-11-21", created: 6, closed: 8 },
    { date: "2026-11-22", created: 9, closed: 4 },
  ],
  first_reply: {
    median_seconds: 1200,
    answered: 3,
    buckets: [
      { key: "up_to_5m", count: 1 },
      { key: "5m_to_15m", count: 0 },
      { key: "15m_to_1h", count: 1 },
      { key: "over_1h", count: 1 },
      { key: "waiting", count: 1 },
    ],
  },
  sla: { met: 2, missed: 2 },
  resolution: { ai: 3, human: 1 },
  channels: [
    { channel: "whatsapp", count: 12 },
    { channel: "email", count: 4 },
    { channel: "app_chat", count: 4 },
  ],
};

describe("Painel", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra os indicadores reais com a comparação com ontem", async () => {
    mockApi({ "GET /api/dashboard": () => [200, metrics] });
    render(<Dashboard token="tk" me={ana} />);

    const kpis = await screen.findByRole("region", { name: "Indicadores" });
    const tile = (name: string) => within(kpis).getByRole("group", { name });
    expect(tile("Abertos agora")).toHaveTextContent("12");
    expect(tile("Abertos agora")).toHaveTextContent("7 com a IA · 3 na fila · 2 com humano");
    expect(tile("Criados hoje")).toHaveTextContent("9");
    expect(tile("Criados hoje")).toHaveTextContent("+3 em relação a ontem");
    expect(tile("Resolvidos hoje")).toHaveTextContent("4");
    expect(tile("Resolvidos hoje")).toHaveTextContent("−4 em relação a ontem");
    expect(tile("Primeira resposta humana")).toHaveTextContent("20 min");
    expect(tile("Primeira resposta humana")).toHaveTextContent("mediana de 3 respostas em 7 dias");
  });

  it("a série diária tem tabela acessível e os cards de canal, resposta e resolução usam os números da API", async () => {
    mockApi({ "GET /api/dashboard": () => [200, metrics] });
    render(<Dashboard token="tk" me={ana} />);

    const table = await screen.findByRole("table", { name: "Tickets criados e resolvidos por dia" });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(8);
    expect(rows[7]).toHaveTextContent("22/11" + "9" + "4");

    const channels = screen.getByRole("list", { name: "Tickets por canal" });
    expect(within(channels).getAllByRole("listitem").map((item) => item.textContent)).toEqual([
      "WhatsApp1260%",
      "E-mail420%",
      "App420%",
    ]);

    const reply = screen.getByRole("list", { name: "Primeira resposta humana por faixa" });
    expect(within(reply).getAllByRole("listitem")[0]).toHaveTextContent("Até 5 min1");
    expect(within(reply).getAllByRole("listitem")[4]).toHaveTextContent("Ainda sem resposta1");

    const resolution = screen.getByRole("region", { name: "Quem resolveu" });
    expect(resolution).toHaveTextContent("Resolvido pela IA3");
    expect(resolution).toHaveTextContent("75%");
    expect(resolution).toHaveTextContent("SLA da primeira resposta2 de 4 no prazo");
  });

  it("sem tickets na janela, diz isso em vez de desenhar gráficos vazios", async () => {
    const empty: DashboardMetrics = {
      ...metrics,
      open: { total: 0, ai: 0, pending_human: 0, human: 0, incidents: 0 },
      today: { created: 0, closed: 0 },
      yesterday: { created: 0, closed: 0 },
      daily: metrics.daily.map((day) => ({ ...day, created: 0, closed: 0 })),
      first_reply: { median_seconds: null, answered: 0, buckets: metrics.first_reply.buckets.map((b) => ({ ...b, count: 0 })) },
      sla: { met: 0, missed: 0 },
      resolution: { ai: 0, human: 0 },
      channels: [],
    };
    mockApi({ "GET /api/dashboard": () => [200, empty] });
    render(<Dashboard token="tk" me={ana} />);

    expect(await screen.findByText("Nenhum ticket nos últimos 7 dias.")).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Primeira resposta humana" })).toHaveTextContent("sem respostas ainda");
  });
});
