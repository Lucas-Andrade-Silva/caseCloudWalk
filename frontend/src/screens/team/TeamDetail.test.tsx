import { fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { TeamDetailData } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { TeamDetail } from "./TeamDetail";

const detail: TeamDetailData = {
  generated_at: "2026-11-22T18:00:00.000Z",
  time_zone: "America/Sao_Paulo",
  totals: {
    received: 4,
    answered: 2,
    resolved: 1,
    open: 3,
    messages_sent: 7,
    first_reply_mean_seconds: 1200,
    sla_percent: 50,
    solution_mean_seconds: 10_800,
  },
  agents: [
    {
      id: "u-ana",
      name: "Ana Lima",
      brands: ["infinitepay"],
      received: 3,
      answered: 2,
      resolved: 1,
      open: 2,
      first_reply_mean_seconds: 1200,
      sla_percent: 50,
      solution_mean_seconds: 10_800,
      top_subject: "maquininha",
    },
    {
      id: "u-bia",
      name: "Bia Rocha",
      brands: ["infinitepay", "jim"],
      received: 1,
      answered: 0,
      resolved: 0,
      open: 1,
      first_reply_mean_seconds: null,
      sla_percent: null,
      solution_mean_seconds: null,
      top_subject: null,
    },
  ],
  subjects: [
    { category: "maquininha", count: 2 },
    { category: null, count: 2 },
  ],
  daily: [
    { date: "2026-11-16", received: 0, resolved: 0 },
    { date: "2026-11-17", received: 1, resolved: 0 },
    { date: "2026-11-18", received: 0, resolved: 0 },
    { date: "2026-11-19", received: 0, resolved: 0 },
    { date: "2026-11-20", received: 0, resolved: 0 },
    { date: "2026-11-21", received: 0, resolved: 0 },
    { date: "2026-11-22", received: 3, resolved: 1 },
  ],
};

describe("detalhe do desempenho do time", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra os totais do time, uma linha por analista, os assuntos e a série diária", async () => {
    mockApi({ "GET /api/dashboard/team": () => [200, detail] });
    render(<TeamDetail token="tk" />);

    expect(screen.getByRole("status")).toHaveTextContent("Carregando…");
    expect(await screen.findByRole("heading", { level: 1, name: "Desempenho do time" })).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();

    const stat = (name: string) => screen.getByRole("group", { name });
    expect(stat("Recebidos")).toHaveTextContent("4");
    expect(stat("Respondidos")).toHaveTextContent("2");
    expect(stat("Respondidos")).toHaveTextContent("50% dos recebidos");
    expect(stat("Resolvidos")).toHaveTextContent("1");
    expect(stat("Em atendimento agora")).toHaveTextContent("3");
    expect(stat("SLA do time")).toHaveTextContent("50%");
    expect(stat("Tempo médio da primeira resposta")).toHaveTextContent("20 min");

    const table = screen.getByRole("table", { name: "Analistas do time" });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(rows[1]).toHaveTextContent("Ana Lima");
    expect(rows[1]).toHaveTextContent("InfinitePay");
    expect(rows[1]).toHaveTextContent("20 min");
    expect(rows[1]).toHaveTextContent("50%");
    expect(rows[1]).toHaveTextContent("3 h");
    expect(rows[1]).toHaveTextContent("Maquininha");
    expect(rows[2]).toHaveTextContent("Bia Rocha");
    expect(rows[2]).toHaveTextContent("—");

    const subjects = screen.getByRole("list", { name: "Assuntos mais tratados" });
    expect(within(subjects).getAllByRole("listitem")[0]).toHaveTextContent("Maquininha");
    expect(within(subjects).getAllByRole("listitem")[1]).toHaveTextContent("Sem categoria");
    expect(within(screen.getByRole("table", { name: "Recebidos e resolvidos por dia" })).getAllByRole("row")).toHaveLength(8);
  });

  it("cada analista leva ao detalhe dele, pelo nome e pela linha inteira", async () => {
    window.location.hash = "#/time";
    mockApi({ "GET /api/dashboard/team": () => [200, detail] });
    render(<TeamDetail token="tk" />);
    const table = await screen.findByRole("table", { name: "Analistas do time" });
    const rows = within(table).getAllByRole("row");

    expect(within(rows[1]!).getByRole("link", { name: "Ana Lima" })).toHaveAttribute("href", "#/analista/u-ana");

    fireEvent.click(rows[2]!);

    expect(window.location.hash).toBe("#/analista/u-bia");
  });

  it("avisa quando não há analista nas marcas, e quando falha", async () => {
    mockApi({ "GET /api/dashboard/team": () => [200, { ...detail, agents: [] }] });
    const { unmount } = render(<TeamDetail token="tk" />);
    expect(await screen.findByText("Nenhum analista nas suas marcas.")).toBeInTheDocument();
    unmount();

    mockApi({ "GET /api/dashboard/team": () => [500, { error: "x" }] });
    render(<TeamDetail token="tk" />);
    expect(await screen.findByText("Não foi possível carregar o desempenho do time.")).toBeInTheDocument();
  });
});
