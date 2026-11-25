import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ResolutionDetailData } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { ResolutionDetail } from "./ResolutionDetail";

const detail: ResolutionDetailData = {
  generated_at: "2026-11-22T18:00:00.000Z",
  time_zone: "America/Sao_Paulo",
  target_seconds: 28_800,
  resolved: 4,
  median_seconds: 19_800,
  mean_seconds: 37_050,
  within_target_percent: 50,
  by_resolver: {
    ai: { count: 1, median_seconds: 600, mean_seconds: 600 },
    human: { count: 3, median_seconds: 32_400, mean_seconds: 49_200 },
  },
  buckets: [
    { key: "up_to_15m", count: 1 },
    { key: "15m_to_1h", count: 0 },
    { key: "1h_to_8h", count: 1 },
    { key: "8h_to_24h", count: 1 },
    { key: "over_24h", count: 1 },
  ],
  brands: [
    { brand: "infinitepay", resolved: 3, median_seconds: 7200 },
    { brand: "jim", resolved: 1, median_seconds: 108_000 },
  ],
  categories: [
    { category: "maquininha", resolved: 2, median_seconds: 57_600 },
    { category: null, resolved: 2, median_seconds: 16_500 },
  ],
  slowest: [
    { id: "0f3a9c21-0000-0000-0000-000000000000", brand: "jim", category: "maquininha", seconds: 108_000, resolved_by: "human", agent: null },
    { id: "7b21e044-0000-0000-0000-000000000000", brand: "infinitepay", category: null, seconds: 600, resolved_by: "ai", agent: null },
  ],
  daily: [
    { date: "2026-11-16", resolved: 0, median_seconds: null },
    { date: "2026-11-17", resolved: 0, median_seconds: null },
    { date: "2026-11-18", resolved: 0, median_seconds: null },
    { date: "2026-11-19", resolved: 0, median_seconds: null },
    { date: "2026-11-20", resolved: 0, median_seconds: null },
    { date: "2026-11-21", resolved: 1, median_seconds: 108_000 },
    { date: "2026-11-22", resolved: 3, median_seconds: 7200 },
  ],
};

describe("detalhe do tempo de solução", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra mediana, média, meta, faixas, IA contra humano, marcas, assuntos, dias e os mais lentos", async () => {
    mockApi({ "GET /api/dashboard/resolution": () => [200, detail] });
    render(<ResolutionDetail token="tk" />);

    expect(screen.getByRole("status")).toHaveTextContent("Carregando…");
    expect(await screen.findByRole("heading", { level: 1, name: "Tempo de solução" })).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();
    const stat = (name: string) => screen.getByRole("group", { name });
    expect(stat("Mediana")).toHaveTextContent("5 h 30 min");
    expect(stat("Média")).toHaveTextContent("10 h 18 min");
    expect(stat("Resolvidos")).toHaveTextContent("4");
    expect(stat("Dentro da meta")).toHaveTextContent("50%");
    expect(stat("Dentro da meta")).toHaveTextContent("meta de 8 h");

    const buckets = screen.getByRole("list", { name: "Resolvidos por faixa de tempo" });
    expect(within(buckets).getAllByRole("listitem")[0]).toHaveTextContent("Até 15 min");
    expect(within(buckets).getAllByRole("listitem")[4]).toHaveTextContent("Mais de 24 h");

    const ai = screen.getByRole("group", { name: "Pela IA" });
    expect(ai).toHaveTextContent("1 ticket");
    expect(ai).toHaveTextContent("10 min");
    const human = screen.getByRole("group", { name: "Por humano" });
    expect(human).toHaveTextContent("3 tickets");
    expect(human).toHaveTextContent("9 h");

    expect(screen.getByRole("list", { name: "Por marca" })).toHaveTextContent("InfinitePay");
    expect(screen.getByRole("list", { name: "Por assunto" })).toHaveTextContent("Sem categoria");
    expect(within(screen.getByRole("table", { name: "Mediana por dia" })).getAllByRole("row")).toHaveLength(8);

    const slowest = screen.getByRole("table", { name: "Tickets mais lentos" });
    const rows = within(slowest).getAllByRole("row");
    expect(rows[1]).toHaveTextContent("#0F3A9C");
    expect(rows[1]).toHaveTextContent("JIM");
    expect(rows[1]).toHaveTextContent("30 h");
    expect(rows[2]).toHaveTextContent("IA");
  });

  it("não inventa números quando nada foi resolvido", async () => {
    mockApi({
      "GET /api/dashboard/resolution": () => [
        200,
        {
          ...detail,
          resolved: 0,
          median_seconds: null,
          mean_seconds: null,
          within_target_percent: null,
          by_resolver: {
            ai: { count: 0, median_seconds: null, mean_seconds: null },
            human: { count: 0, median_seconds: null, mean_seconds: null },
          },
          buckets: detail.buckets.map((bucket) => ({ ...bucket, count: 0 })),
          brands: [],
          categories: [],
          slowest: [],
        },
      ],
    });
    render(<ResolutionDetail token="tk" />);

    expect(await screen.findByText("Nenhum ticket resolvido nos últimos 7 dias.")).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Mediana" })).toHaveTextContent("—");
  });
});
