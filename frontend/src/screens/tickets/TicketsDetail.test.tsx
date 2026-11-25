import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { TicketsDetailData } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { TicketsDetail } from "./TicketsDetail";

const detail: TicketsDetailData = {
  generated_at: "2026-11-22T18:00:00.000Z",
  time_zone: "America/Sao_Paulo",
  counts: {
    attention: 3,
    unassigned: 2,
    overdue: 1,
    stale: 1,
    by_priority: { p1: 1, p2: 1, p3: 1, p4: 0 },
    by_brand: [
      { brand: "infinitepay", count: 2 },
      { brand: "jim", count: 1 },
    ],
  },
  tickets: [
    {
      id: "0f3a9c21-0000-0000-0000-000000000000",
      brand: "infinitepay",
      priority: "p1",
      mode: "pending_human",
      agent: null,
      agent_id: null,
      category: "pix",
      subject: "Pix não caiu",
      waiting_seconds: 1800,
      first_response_due_at: "2000-01-01T00:00:00.000Z",
      first_human_response_at: null,
      overdue: true,
    },
    {
      id: "7b21e044-0000-0000-0000-000000000000",
      brand: "jim",
      priority: "p2",
      mode: "pending_human",
      agent: null,
      agent_id: null,
      category: null,
      subject: "Cartão recusado",
      waiting_seconds: 3600,
      first_response_due_at: "2999-01-01T00:00:00.000Z",
      first_human_response_at: null,
      overdue: false,
    },
    {
      id: "a5c1d9e2-0000-0000-0000-000000000000",
      brand: "infinitepay",
      priority: "p3",
      mode: "human",
      agent: "Ana Lima",
      agent_id: "u-ana",
      category: "maquininha",
      subject: "Maquininha travou",
      waiting_seconds: 7200,
      first_response_due_at: "2000-01-01T00:00:00.000Z",
      first_human_response_at: "2000-01-01T00:00:00.000Z",
      overdue: false,
    },
  ],
  stale_tickets: [
    { id: "e0e0e0e0-0000-0000-0000-000000000000", brand: "infinitepay", priority: "p3", mode: "ai", agent: null, agent_id: null, subject: "Dúvida antiga", age_seconds: 4 * 86_400 },
  ],
};

describe("detalhe da operação dos tickets", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra o que pede gente, por prioridade e marca, com prazo e espera, e o que está parado", async () => {
    mockApi({ "GET /api/dashboard/tickets": () => [200, detail] });
    render(<TicketsDetail token="tk" />);

    expect(screen.getByRole("status")).toHaveTextContent("Carregando…");
    expect(await screen.findByRole("heading", { level: 1, name: "Operação dos tickets" })).toBeInTheDocument();
    expect(screen.queryByRole("status")).toBeNull();

    const stat = (name: string) => screen.getByRole("group", { name });
    expect(stat("Pedem gente")).toHaveTextContent("3");
    expect(stat("Sem analista")).toHaveTextContent("2");
    expect(stat("Fora do prazo")).toHaveTextContent("1");
    expect(stat("Parados")).toHaveTextContent("1");

    const priorities = within(screen.getByRole("list", { name: "Tickets por prioridade" })).getAllByRole("listitem");
    expect(priorities.map((item) => item.textContent)).toEqual(["Urgente1", "Alta1", "Média1", "Baixa0"]);
    expect(screen.getByRole("list", { name: "Tickets por marca" })).toHaveTextContent("InfinitePay");

    const rows = within(screen.getByRole("table", { name: "Tickets que pedem gente" })).getAllByRole("row");
    expect(rows).toHaveLength(4);
    expect(rows[1]).toHaveTextContent("#0F3A9C");
    expect(rows[1]).toHaveTextContent("InfinitePay");
    expect(rows[1]).toHaveTextContent("Pix não caiu");
    expect(rows[1]).toHaveTextContent("Urgente");
    expect(rows[1]).toHaveTextContent("Esperando humano");
    expect(rows[1]).toHaveTextContent("30 min");
    expect(rows[1]).toHaveTextContent("atrasou");
    expect(rows[1]).toHaveTextContent("—");
    expect(rows[2]).toHaveTextContent("vence em");
    expect(rows[3]).toHaveTextContent("Com humano");
    expect(rows[3]).toHaveTextContent("respondido");
    expect(within(rows[3]!).getByRole("link", { name: "Ana Lima" })).toHaveAttribute("href", "#/analista/u-ana");

    const stale = within(screen.getByRole("table", { name: "Tickets parados há mais de 3 dias" })).getAllByRole("row");
    expect(stale[1]).toHaveTextContent("Dúvida antiga");
    expect(stale[1]).toHaveTextContent("4 dias");
    expect(stale[1]).toHaveTextContent("Com a IA");
  });

  it("avisa quando nada pede gente e nada está parado, e quando falha", async () => {
    mockApi({
      "GET /api/dashboard/tickets": () => [
        200,
        { ...detail, counts: { ...detail.counts, attention: 0, unassigned: 0, overdue: 0, stale: 0, by_brand: [] }, tickets: [], stale_tickets: [] },
      ],
    });
    const { unmount } = render(<TicketsDetail token="tk" />);
    expect(await screen.findByText("Nenhum ticket pedindo gente agora.")).toBeInTheDocument();
    expect(screen.getByText("Nenhum ticket parado há mais de 3 dias.")).toBeInTheDocument();
    unmount();

    mockApi({ "GET /api/dashboard/tickets": () => [500, { error: "x" }] });
    render(<TicketsDetail token="tk" />);
    expect(await screen.findByText("Não foi possível carregar os tickets.")).toBeInTheDocument();
  });
});
