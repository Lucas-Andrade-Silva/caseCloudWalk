import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Explanation } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { DecisionTrail } from "./DecisionTrail";

const explanation: Explanation = {
  ticket_id: "t1",
  redacted_text: "minha maquininha não liga, CPF [CPF]",
  redactions: { cpf: 1 },
  trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
  steps: [
    { kind: "opened", at: "2026-11-22T12:00:00.000Z", actor: "customer", channel: "whatsapp" },
    {
      kind: "rule", at: "2026-11-22T12:00:00.010Z", actor: "rule", step: "routing.opening", rule_set_version: 3,
      rule: null, output: { queue: null, priority: null, tags: [] }, facts: { channel: "whatsapp" },
    },
    {
      kind: "llm_facts", at: "2026-11-22T12:00:01.000Z", actor: "llm", category: "maquininha", language: "pt",
      frustration: "alta", confidence: 0.99, accepted: true, min_confidence: 0.5, source: "live",
      model: "openai/gpt-oss-120b", prompt_version: "enrich-v2",
    },
    {
      kind: "rule", at: "2026-11-22T12:00:01.010Z", actor: "rule", step: "routing.enrichment", rule_set_version: 3,
      rule: { id: "maquininha-llm", name: "Maquininha (LLM)", when: { fact: "category", op: "eq", value: "maquininha" } },
      output: { queue: "maquininha", priority: "p1", tags: ["dispositivo"] }, facts: { category: "maquininha" },
    },
    { kind: "escalated", at: "2026-11-22T12:00:02.000Z", actor: "bot", trigger: "agent_requested", reason: "device_issue", priority: "p1" },
    { kind: "brief_fallback", at: "2026-11-22T12:00:03.000Z", actor: "llm", reason: "circuit_open" },
  ],
};

describe("Por que a IA decidiu", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("mostra o texto como a LLM viu, cada passo da cadeia e o link do trace", async () => {
    mockApi({ "GET /api/tickets/t1/explanation": () => [200, explanation] });
    render(<DecisionTrail token="tk" ticketId="t1" />);

    const seen = await screen.findByRole("figure", { name: "Texto que a LLM recebeu" });
    expect(within(seen).getByText("minha maquininha não liga, CPF [CPF]")).toBeInTheDocument();
    expect(within(seen).getByText("1 CPF redigido")).toBeInTheDocument();

    const steps = screen.getByRole("list", { name: "Cadeia de decisão" });
    const items = within(steps).getAllByRole("listitem");
    expect(items).toHaveLength(6);

    expect(items[1]).toHaveTextContent("Regras v3 · abertura");
    expect(items[1]).toHaveTextContent("Nenhuma regra casou");

    expect(items[2]).toHaveTextContent("LLM classificou");
    expect(items[2]).toHaveTextContent("maquininha");
    expect(items[2]).toHaveTextContent("confiança 0,99 (mínimo 0,50)");
    expect(items[2]).toHaveTextContent("openai/gpt-oss-120b · enrich-v2 · ao vivo");

    expect(items[3]).toHaveTextContent("Regras v3 · depois da LLM");
    expect(items[3]).toHaveTextContent("Maquininha (LLM)");
    expect(items[3]).toHaveTextContent("Categoria (IA) é igual a maquininha");
    expect(items[3]).toHaveTextContent("fila maquininha · P1 · dispositivo");

    expect(items[4]).toHaveTextContent("o agente pediu");
    expect(items[5]).toHaveTextContent("Brief por template");
    expect(items[5]).toHaveTextContent("disjuntor da LLM aberto");

    expect(screen.getByRole("link", { name: /Ver o trace ponta a ponta/ })).toHaveAttribute(
      "href",
      "http://127.0.0.1:16686/trace/4bf92f3577b34da6a3ce929d0e0e4736",
    );
  });

  it("categoria abaixo da confiança mínima aparece como descartada", async () => {
    mockApi({
      "GET /api/tickets/t1/explanation": () => [
        200,
        {
          ...explanation,
          trace_id: null,
          steps: [{ ...explanation.steps[2], category: null, confidence: 0.3, accepted: false }],
        },
      ],
    });
    render(<DecisionTrail token="tk" ticketId="t1" />);

    const steps = await screen.findByRole("list", { name: "Cadeia de decisão" });
    expect(steps).toHaveTextContent("abaixo do mínimo: categoria descartada");
    expect(screen.queryByRole("link", { name: /trace/ })).not.toBeInTheDocument();
    expect(screen.getByText("Sem trace registrado para este ticket.")).toBeInTheDocument();
  });
});
