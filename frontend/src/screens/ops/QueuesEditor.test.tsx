import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Analyst, Queue, Team } from "../../lib/opsApi";
import { mockApi } from "../../test/mockApi";
import { QueuesEditor } from "./QueuesEditor";

const credito: Team = { id: "team-credito", slug: "credito", name: "Crédito", members: [{ id: "u-carla", name: "Carla" }], queues: ["credito-infinitepay"] };
const atendimento: Team = { id: "team-at", slug: "atendimento-infinitepay", name: "Atendimento InfinitePay", members: [], queues: ["infinitepay-atendimento"] };

const queues: Queue[] = [
  { id: "q1", slug: "infinitepay-atendimento", name: "Atendimento InfinitePay", brand: "infinitepay", default: true, team: { id: atendimento.id, slug: atendimento.slug, name: atendimento.name } },
  { id: "q2", slug: "credito-infinitepay", name: "Crédito InfinitePay", brand: "infinitepay", default: false, team: { id: credito.id, slug: credito.slug, name: credito.name } },
  { id: "q3", slug: "jim-atendimento", name: "Atendimento JIM", brand: "jim", default: true, team: { id: atendimento.id, slug: atendimento.slug, name: atendimento.name } },
];
const analysts: Analyst[] = [
  { id: "u-ana", name: "Ana", teams: [] },
  { id: "u-carla", name: "Carla", teams: ["credito"] },
];

function setup() {
  return mockApi({
    "GET /api/ops/queues": () => [200, queues],
    "GET /api/ops/teams": () => [200, [atendimento, credito]],
    "GET /api/ops/analysts": () => [200, analysts],
  });
}

describe("filas e equipes", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra as filas por marca e troca a equipe dona", async () => {
    const api = setup();
    api.set("PATCH /api/ops/queues/q2", () => [200, { ...queues[1], team: atendimento }]);
    render(<QueuesEditor token="tk" />);

    const infinitepay = await screen.findByRole("region", { name: "Filas InfinitePay" });
    const rows = within(infinitepay).getAllByRole("listitem");
    expect(rows.map((row) => row.querySelector("p")?.textContent)).toEqual([
      "Atendimento InfinitePaypadrãoRenomear",
      "Crédito InfinitePayRenomear",
    ]);
    expect(within(screen.getByRole("region", { name: "Filas JIM" })).getAllByRole("listitem")).toHaveLength(1);

    await userEvent.selectOptions(within(infinitepay).getByLabelText("Equipe da fila Crédito InfinitePay"), atendimento.id);

    expect(api.calls.find((call) => call.method === "PATCH")?.body).toEqual({ team_id: atendimento.id });
  });

  it("cria uma fila e mostra o erro de validação no campo", async () => {
    const api = setup();
    api.set("POST /api/ops/queues", () => [422, { errors: [{ path: "slug", message: "já está em uso" }] }]);
    render(<QueuesEditor token="tk" />);

    const form = await screen.findByRole("form", { name: "Nova fila" });
    await userEvent.selectOptions(within(form).getByLabelText("Marca"), "jim");
    await userEvent.type(within(form).getByLabelText("Nome"), "Crédito JIM");
    await userEvent.type(within(form).getByLabelText("Identificador"), "credito-jim");
    await userEvent.selectOptions(within(form).getByLabelText("Equipe"), credito.id);
    await userEvent.click(within(form).getByRole("button", { name: "Criar fila" }));

    expect(api.calls.find((call) => call.method === "POST")?.body).toEqual({
      brand: "jim",
      name: "Crédito JIM",
      slug: "credito-jim",
      team_id: credito.id,
    });
    expect(await within(form).findByRole("alert")).toHaveTextContent("Identificador: já está em uso");
  });

  it("adiciona e remove analistas de uma equipe", async () => {
    const api = setup();
    api.set(`POST /api/ops/teams/${credito.id}/members`, () => [204]);
    api.set(`DELETE /api/ops/teams/${credito.id}/members/u-carla`, () => [204]);
    render(<QueuesEditor token="tk" />);

    const team = await screen.findByRole("region", { name: "Equipe Crédito" });
    await userEvent.selectOptions(within(team).getByLabelText("Adicionar à equipe Crédito"), "u-ana");
    await userEvent.click(within(team).getByRole("button", { name: "Adicionar" }));
    await userEvent.click(within(team).getByRole("button", { name: "Remover Carla" }));

    expect(api.calls.filter((call) => call.method !== "GET").map((call) => [call.method, call.path, call.body])).toEqual([
      ["POST", `/api/ops/teams/${credito.id}/members`, { user_id: "u-ana" }],
      ["DELETE", `/api/ops/teams/${credito.id}/members/u-carla`, undefined],
    ]);
  });
});
