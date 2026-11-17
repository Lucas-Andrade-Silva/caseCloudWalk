import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Queue, RuleSet, RuleSetSummary } from "../../lib/opsApi";
import { mockApi } from "../../test/mockApi";
import type { Catalog } from "./rules/builder";
import { RulesEditor } from "./RulesEditor";

const catalog: Catalog = {
  facts: { message_text: "text", amount: "number" },
  operators: { text: ["contains_any"], number: ["eq", "gt", "gte", "lt", "lte"], string: ["eq"], boolean: ["eq"] },
};
const queues: Queue[] = [
  { id: "q2", slug: "credito-infinitepay", name: "Crédito InfinitePay", brand: "infinitepay", default: false, team: { id: "t", slug: "credito", name: "Crédito" } },
];
const rules = [
  {
    id: "credito-alto-valor",
    name: "Crédito acima de R$ 5 mil",
    when: { all: [{ fact: "message_text", op: "contains_any", value: ["crédito"] }, { fact: "amount", op: "gte", value: 5000 }] },
    then: { queue: "credito-infinitepay", priority: "p1" },
  },
];
const published: RuleSet = { id: "rs1", brand: "infinitepay", version: 1, status: "published", published_at: "2026-11-15T12:00:00.000Z", rules_count: 1, rules };

function setup(versions: RuleSetSummary[] = [published]) {
  return mockApi({
    "GET /api/ops/rules/catalog": () => [200, catalog],
    "GET /api/ops/queues": () => [200, queues],
    "GET /api/ops/brands/infinitepay/rule_sets": () => [200, versions],
    "GET /api/ops/rule_sets/rs1": () => [200, published],
  });
}

describe("editor de regras", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra a versão publicada só para leitura e cria um rascunho a partir dela", async () => {
    const versions: RuleSetSummary[] = [published];
    const api = setup(versions);
    const draft: RuleSet = { ...published, id: "rs2", version: 2, status: "draft", published_at: null };
    api.set("POST /api/ops/brands/infinitepay/rule_sets", () => {
      versions.unshift(draft);
      return [201, draft];
    });
    api.set("GET /api/ops/rule_sets/rs2", () => [200, draft]);
    render(<RulesEditor token="tk" />);

    const card = await screen.findByRole("group", { name: "Regra Crédito acima de R$ 5 mil" });
    expect(within(card).getByLabelText("Valor da condição 2")).toBeDisabled();
    expect(screen.getByText("Versão 1 · publicada")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Criar rascunho a partir desta versão" }));

    expect(api.calls.find((call) => call.method === "POST")?.body).toEqual({ rules });
    expect(await screen.findByText("Versão 2 · rascunho")).toBeInTheDocument();
    expect(within(screen.getByRole("group", { name: "Regra Crédito acima de R$ 5 mil" })).getByLabelText("Valor da condição 2")).toBeEnabled();
  });

  it("edita o rascunho, salva com o tipo certo e aponta o erro na regra", async () => {
    const draft: RuleSet = { ...published, id: "rs2", version: 2, status: "draft", published_at: null };
    const api = setup([{ ...draft }, published]);
    api.set("GET /api/ops/rule_sets/rs2", () => [200, draft]);
    let attempt = 0;
    api.set("PATCH /api/ops/rule_sets/rs2", (body) => {
      attempt++;
      if (attempt === 1) return [422, { errors: [{ path: "rules[0].name", message: "é obrigatório" }] }];
      return [200, { ...draft, rules: (body as { rules: unknown }).rules }];
    });
    render(<RulesEditor token="tk" />);

    const card = await screen.findByRole("group", { name: "Regra Crédito acima de R$ 5 mil" });
    const value = within(card).getByLabelText("Valor da condição 2");
    await userEvent.clear(value);
    await userEvent.type(value, "10.000");
    await userEvent.clear(within(card).getByLabelText("Nome da regra"));
    await userEvent.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByText("Nome: é obrigatório")).toBeInTheDocument();

    await userEvent.type(within(screen.getByRole("group", { name: "Regra sem nome" })).getByLabelText("Nome da regra"), "Crédito alto");
    await userEvent.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    const saved = api.calls.filter((call) => call.method === "PATCH").at(-1)?.body as { rules: { name: string; when: unknown }[] };
    expect(saved.rules[0]).toMatchObject({
      name: "Crédito alto",
      when: { all: [{ fact: "message_text", op: "contains_any", value: ["crédito"] }, { fact: "amount", op: "gte", value: 10000 }] },
    });
    expect(await screen.findByRole("status")).toHaveTextContent("Rascunho salvo.");
  });

  it("simula o rascunho e publica depois de confirmar", async () => {
    const draft: RuleSet = { ...published, id: "rs2", version: 2, status: "draft", published_at: null };
    const api = setup([{ ...draft }, published]);
    api.set("GET /api/ops/rule_sets/rs2", () => [200, draft]);
    api.set("POST /api/ops/rule_sets/rs2/dry_run", () => [
      200,
      {
        current_version: 1,
        candidate_version: 2,
        evaluated: 50,
        changed: 1,
        changes: [
          {
            ticket_id: "t-123456789",
            before: { rule_id: null, queue: null, priority: "p3", tags: [] },
            after: { rule_id: "credito-alto-valor", queue: "credito-infinitepay", priority: "p1", tags: [] },
          },
        ],
      },
    ]);
    api.set("POST /api/ops/rule_sets/rs2/publish", () => [200, { ...draft, status: "published" }]);
    render(<RulesEditor token="tk" />);

    await userEvent.click(await screen.findByRole("button", { name: "Simular" }));
    const result = await screen.findByRole("region", { name: "Resultado da simulação" });
    expect(result).toHaveTextContent("1 de 50 tickets recentes mudariam");
    expect(result).toHaveTextContent("p3 → p1");

    await userEvent.click(screen.getByRole("button", { name: "Publicar" }));
    expect(api.calls.some((call) => call.path.endsWith("/publish"))).toBe(false);
    await userEvent.click(screen.getByRole("button", { name: "Confirmar publicação" }));

    expect(api.calls.some((call) => call.path === "/api/ops/rule_sets/rs2/publish")).toBe(true);
  });
});
