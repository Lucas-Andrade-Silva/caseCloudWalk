import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Incident } from "../../lib/api";
import { mockApi } from "../../test/mockApi";
import { IncidentBanner } from "./IncidentBanner";

const incident = (overrides: Partial<Incident> = {}): Incident => ({
  id: "i1",
  key: "categoria:maquininha",
  label: "maquininha",
  brand: "infinitepay",
  status: "open",
  title: "Maquininhas não ligam após atualização",
  draft_reply: "Olá! Identificamos uma instabilidade e já estamos trabalhando nisso.",
  title_source: "live",
  model: "openai/gpt-oss-120b",
  opened_at: "2026-11-22T12:00:00.000Z",
  resolved_at: null,
  open_tickets: 7,
  total_tickets: 7,
  ...overrides,
});

describe("Modo Incidente no painel do analista", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("sem incidente aberto, não mostra nada", async () => {
    const api = mockApi({ "GET /api/incidents": () => [200, { incidents: [] }] });
    const { container } = render(<IncidentBanner token="tk" />);

    await waitFor(() => expect(api.calls).toHaveLength(1));
    expect(container).toBeEmptyDOMElement();
  });

  it("mostra o incidente e responde a todos com o rascunho editado", async () => {
    const api = mockApi({ "GET /api/incidents": () => [200, { incidents: [incident()] }] });
    api.set("POST /api/incidents/i1/resolve", () => [
      200,
      { closed: 6, skipped: [{ id: "t9", reason: "other_analyst" }], incident: incident({ status: "resolved", open_tickets: 1 }) },
    ]);
    render(<IncidentBanner token="tk" />);

    const banner = await screen.findByRole("region", { name: "Incidente aberto" });
    expect(within(banner).getByText("Maquininhas não ligam após atualização")).toBeInTheDocument();
    expect(within(banner).getByText(/7 tickets/)).toBeInTheDocument();

    await userEvent.click(within(banner).getByRole("button", { name: "Responder a todos" }));
    const dialog = await screen.findByRole("dialog", { name: "Responder a todos" });
    const reply = within(dialog).getByLabelText("Resposta para os 7 clientes");
    expect(reply).toHaveValue("Olá! Identificamos uma instabilidade e já estamos trabalhando nisso.");

    await userEvent.type(reply, " Avisamos aqui.");
    api.set("GET /api/incidents", () => [200, { incidents: [] }]);
    await userEvent.click(within(dialog).getByRole("button", { name: "Responder e fechar" }));

    const post = api.calls.find((call) => call.method === "POST");
    expect(post?.body).toEqual({
      text: "Olá! Identificamos uma instabilidade e já estamos trabalhando nisso. Avisamos aqui.",
      resolution_code: "resolved",
    });
    expect(await screen.findByRole("status")).toHaveTextContent("6 tickets fechados · 1 com outro analista");
  });

  it("avisa quando o fechamento em lote falha", async () => {
    const api = mockApi({ "GET /api/incidents": () => [200, { incidents: [incident()] }] });
    api.set("POST /api/incidents/i1/resolve", () => [409, { error: "o incidente já foi resolvido" }]);
    render(<IncidentBanner token="tk" />);

    await userEvent.click(await screen.findByRole("button", { name: "Responder a todos" }));
    await userEvent.click(within(await screen.findByRole("dialog")).getByRole("button", { name: "Responder e fechar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Não foi possível fechar os tickets do incidente.");
  });
});
