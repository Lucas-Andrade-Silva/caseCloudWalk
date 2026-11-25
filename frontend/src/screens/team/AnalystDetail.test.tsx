import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { AnalystDetailData } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { AnalystDetail } from "./AnalystDetail";

const detail: AnalystDetailData = {
  generated_at: "2026-11-22T18:00:00.000Z",
  time_zone: "America/Sao_Paulo",
  agent: { id: "u-ana", name: "Ana Lima", brands: ["infinitepay"] },
  open: 2,
  received: 3,
  answered: 2,
  resolved: 1,
  messages_sent: 7,
  first_reply: { mean_seconds: 1200, answered: 2 },
  sla: { met: 1, missed: 1, percent: 50 },
  resolution_time: { mean_seconds: 10_800, median_seconds: 9000, resolved: 1 },
  subjects: [
    { category: "maquininha", count: 2 },
    { category: null, count: 1 },
  ],
  brands: [{ brand: "infinitepay", count: 3 }],
  daily: [
    { date: "2026-11-16", received: 0, resolved: 0 },
    { date: "2026-11-17", received: 1, resolved: 0 },
    { date: "2026-11-18", received: 0, resolved: 0 },
    { date: "2026-11-19", received: 0, resolved: 0 },
    { date: "2026-11-20", received: 0, resolved: 0 },
    { date: "2026-11-21", received: 0, resolved: 0 },
    { date: "2026-11-22", received: 2, resolved: 1 },
  ],
};

describe("detalhe do analista", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra recebidos, respondidos, resolvidos, SLA, tempos, assuntos e a série diária", async () => {
    mockApi({ "GET /api/dashboard/analysts/u-ana": () => [200, detail] });
    render(<AnalystDetail token="tk" id="u-ana" />);

    expect(screen.getByRole("status")).toHaveTextContent("Carregando…");
    expect(await screen.findByRole("heading", { level: 1, name: "Ana Lima" })).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();
    const stat = (name: string) => screen.getByRole("group", { name });
    expect(stat("Recebidos")).toHaveTextContent("3");
    expect(stat("Respondidos")).toHaveTextContent("2");
    expect(stat("Respondidos")).toHaveTextContent("67% dos recebidos");
    expect(stat("Resolvidos")).toHaveTextContent("1");
    expect(stat("Em atendimento agora")).toHaveTextContent("2");
    expect(stat("Mensagens enviadas")).toHaveTextContent("7");

    const sla = screen.getByRole("region", { name: "SLA da primeira resposta" });
    expect(sla).toHaveTextContent("50%");
    expect(sla).toHaveTextContent("1 no prazo");
    expect(sla).toHaveTextContent("1 fora do prazo");
    expect(sla).toHaveTextContent("20 min");

    const solution = screen.getByRole("region", { name: "Tempo de solução" });
    expect(solution).toHaveTextContent("3 h");
    expect(solution).toHaveTextContent("2 h 30 min");

    const subjects = screen.getByRole("list", { name: "Assuntos mais tratados" });
    expect(within(subjects).getAllByRole("listitem")[0]).toHaveTextContent("Maquininha");
    expect(within(subjects).getAllByRole("listitem")[1]).toHaveTextContent("Sem categoria");
    expect(screen.getByRole("list", { name: "Marcas atendidas" })).toHaveTextContent("InfinitePay");

    const days = screen.getByRole("table", { name: "Recebidos e resolvidos por dia" });
    expect(within(days).getAllByRole("row")).toHaveLength(8);
  });

  it("não inventa números para quem ainda não atendeu nada", async () => {
    mockApi({
      "GET /api/dashboard/analysts/u-ana": () => [
        200,
        {
          ...detail,
          open: 0,
          received: 0,
          answered: 0,
          resolved: 0,
          messages_sent: 0,
          first_reply: { mean_seconds: null, answered: 0 },
          sla: { met: 0, missed: 0, percent: null },
          resolution_time: { mean_seconds: null, median_seconds: null, resolved: 0 },
          subjects: [],
          brands: [],
        },
      ],
    });
    render(<AnalystDetail token="tk" id="u-ana" />);

    expect(await screen.findByText("Sem tickets recebidos nos últimos 7 dias.")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "SLA da primeira resposta" })).toHaveTextContent("—");
  });

  it("avisa quando o analista não existe ou não é de uma marca do usuário", async () => {
    mockApi({ "GET /api/dashboard/analysts/u-x": () => [404, { error: "analista não encontrado" }] });
    render(<AnalystDetail token="tk" id="u-x" />);

    expect(await screen.findByText("Analista não encontrado.")).toBeInTheDocument();
  });
});
