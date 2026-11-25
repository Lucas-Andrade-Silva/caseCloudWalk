import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";

const ana = { id: "u-ana", name: "Ana", role: "analyst", brands: ["infinitepay"] };
const emptyWork = { mine: [], waiting: [], waiting_count: 0 };
const olivia = { id: "u-olivia", name: "Olivia", role: "ops", brands: [] };

function respond(status: number, body: unknown) {
  return Promise.resolve(new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } }));
}

describe("entrada na plataforma", () => {
  const fetchMock = vi.fn();

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    window.location.hash = "";
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    fetchMock.mockReset();
  });

  it("pede o token, confere quem é e abre a tela inicial em cards, sem barra lateral", async () => {
    fetchMock.mockImplementation((path: string) => (path === "/api/work" ? respond(200, emptyWork) : path === "/api/me" ? respond(200, ana) : respond(404, {})));
    render(<App />);

    await userEvent.type(screen.getByLabelText("Token de acesso"), "token-da-ana");
    await userEvent.click(screen.getByRole("button", { name: "Entrar" }));

    expect(await screen.findByText("Ana")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith("/api/me", {
      headers: { Accept: "application/json", Authorization: "Bearer token-da-ana" },
    });
    expect(screen.getByRole("navigation", { name: "Principal" })).toBeInTheDocument();
    expect(screen.queryByRole("complementary")).not.toBeInTheDocument();
    expect(window.localStorage.getItem("helpdesk.token")).toBe("token-da-ana");
    expect(await screen.findByRole("region", { name: "Atalhos" })).toBeInTheDocument();
    expect(window.location.hash).toBe("#/inicio");
    expect(screen.queryByRole("link", { name: "Voltar" })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole("link", { name: "Fila" }));
    expect(await screen.findByRole("button", { name: "Pegar o próximo" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Voltar" })).toHaveAttribute("href", "#/inicio");
  });

  it("com sessão guardada, mostra a tela de carregamento enquanto confere o token", async () => {
    window.localStorage.setItem("helpdesk.token", "token-da-ana");
    fetchMock.mockImplementation((path: string) => (path === "/api/me" ? respond(200, ana) : respond(404, {})));
    render(<App />);

    expect(screen.getByRole("status")).toHaveTextContent("Entrando…");
    expect(await screen.findByText("Ana")).toBeInTheDocument();
    window.localStorage.removeItem("helpdesk.token");
  });

  it("leva a operação às filas e regras pelo card", async () => {
    fetchMock.mockImplementation((path: string) => (path.startsWith("/api/ops/") ? respond(200, []) : path === "/api/me" ? respond(200, olivia) : respond(404, {})));
    render(<App />);

    await userEvent.type(screen.getByLabelText("Token de acesso"), "token-da-olivia");
    await userEvent.click(screen.getByRole("button", { name: "Entrar" }));

    await userEvent.click(await screen.findByRole("link", { name: "Filas e regras" }));
    expect(await screen.findByRole("form", { name: "Nova fila" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Regras" })).toHaveAttribute("href", "#/operacao/regras");
    expect(window.location.hash).toBe("#/operacao");
  });

  it("avisa quando o token não vale e continua na entrada", async () => {
    fetchMock.mockImplementation(() => respond(401, { error: "token inválido" }));
    render(<App />);

    await userEvent.type(screen.getByLabelText("Token de acesso"), "errado");
    await userEvent.click(screen.getByRole("button", { name: "Entrar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Token inválido.");
    expect(window.localStorage.getItem("helpdesk.token")).toBeNull();
  });

  it("em desenvolvimento, entra com um clique como uma pessoa de teste", async () => {
    fetchMock.mockImplementation((path: string) => (path === "/api/work" ? respond(200, emptyWork) : path === "/api/me" ? respond(200, ana) : respond(404, {})));
    render(<App />);

    await userEvent.click(screen.getByRole("button", { name: /Ana/ }));

    expect(await screen.findByRole("navigation", { name: "Principal" })).toBeInTheDocument();
    expect(fetchMock.mock.calls[0]?.[1]).toEqual({
      headers: { Accept: "application/json", Authorization: "Bearer dev-analyst-ana" },
    });
  });

  it("abre o chat do cliente sem pedir login", async () => {
    window.location.hash = "#/cliente";
    render(<App />);

    expect(await screen.findByRole("button", { name: "Começar conversa" })).toBeInTheDocument();
    expect(screen.queryByLabelText("Token de acesso")).not.toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("abre o chat do cliente mesmo com uma sessão de analista aberta no navegador", async () => {
    window.localStorage.setItem("helpdesk.token", "token-da-ana");
    window.location.hash = "#/fila";
    fetchMock.mockImplementation((path: string) => (path === "/api/work" ? respond(200, emptyWork) : path === "/api/me" ? respond(200, ana) : respond(404, {})));
    render(<App />);
    expect(await screen.findByRole("button", { name: "Pegar o próximo" })).toBeInTheDocument();

    window.location.hash = "#/cliente";
    window.dispatchEvent(new HashChangeEvent("hashchange"));

    expect(await screen.findByRole("button", { name: "Começar conversa" })).toBeInTheDocument();
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(window.location.hash).toBe("#/cliente");
  });

  it("volta com a sessão guardada e sai limpando tudo", async () => {
    window.localStorage.setItem("helpdesk.token", "token-da-ana");
    fetchMock.mockImplementation((path: string) => (path === "/api/work" ? respond(200, emptyWork) : path === "/api/me" ? respond(200, ana) : respond(404, {})));
    render(<App />);

    expect(await screen.findByText("Ana")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Sair" }));

    expect(screen.getByLabelText("Token de acesso")).toBeInTheDocument();
    expect(window.localStorage.getItem("helpdesk.token")).toBeNull();
  });
});
