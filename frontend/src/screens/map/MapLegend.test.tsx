import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { MapLegend } from "./MapLegend";

const items = () => within(screen.getByRole("list", { name: "Como ler o mapa" })).getAllByRole("listitem");

describe("legenda do mapa vivo", () => {
  it("na visão dos grupos, explica o círculo, o incidente e o prazo, cada um com nome e detalhe", () => {
    render(<MapLegend zoomed={false} />);

    expect(items().map((item) => item.textContent)).toEqual([
      "Grupocresce com os tickets",
      "Incidenteanel laranja tracejado",
      "Prazo em riscoanel vermelho pulsando",
    ]);
    expect(screen.getByText("Clique num círculo para ampliar.")).toBeInTheDocument();
  });

  it("dentro de um grupo, explica o tamanho, o estado de cada ticket, o incidente e o prazo", () => {
    render(<MapLegend zoomed />);

    expect(items().map((item) => item.textContent)).toEqual([
      "Prioridadetamanho do ponto, P1 maior",
      "Esperando humanoanel laranja",
      "Com humanoanel verde",
      "Com a IAsem anel",
      "Incidenteanel laranja tracejado",
      "Prazo em riscoanel vermelho pulsando",
    ]);
    expect(screen.getByText("Esc ou “Todos os grupos” volta.")).toBeInTheDocument();
  });

  it("o desenho de cada item é decorativo: o texto já diz tudo", () => {
    render(<MapLegend zoomed />);

    for (const item of items()) expect(item.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
  });
});
