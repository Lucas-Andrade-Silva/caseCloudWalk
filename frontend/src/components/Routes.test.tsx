import { render } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mockApi } from "../test/mockApi";
import { Routes } from "./Routes";

const ana = { id: "u-ana", name: "Ana", role: "analyst" as const, brands: ["infinitepay"] };

describe("rotas da plataforma", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("leva rota desconhecida para a tela inicial do papel", async () => {
    mockApi({ "GET /api/work": () => [200, { mine: [], waiting: [], waiting_count: 0 }] });
    window.location.hash = "#/nada";

    render(<Routes me={ana} token="tk" />);

    await vi.waitFor(() => expect(window.location.hash).toBe("#/fila"));
  });

  // Defeito visto no navegador: o polling renderizava as rotas da plataforma com o endereço já em /cliente,
  // antes de o App trocar para o chat do cliente, e a plataforma mandava de volta para /fila.
  it("não mexe na rota pública do chat do cliente", async () => {
    mockApi({});
    window.location.hash = "#/cliente";

    render(<Routes me={ana} token="tk" />);
    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(window.location.hash).toBe("#/cliente");
  });
});
