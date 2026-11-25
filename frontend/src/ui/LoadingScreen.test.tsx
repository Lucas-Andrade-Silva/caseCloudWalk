import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { LoadingScreen } from "./LoadingScreen";

describe("tela de carregamento", () => {
  it("avisa que está carregando, como status para leitor de tela", () => {
    render(<LoadingScreen />);

    expect(screen.getByRole("status")).toHaveTextContent("Carregando…");
  });

  it("aceita um texto próprio, e o desenho é só decorativo", () => {
    const { container } = render(<LoadingScreen label="Montando o painel…" />);

    expect(screen.getByRole("status")).toHaveTextContent("Montando o painel…");
    expect(container.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
  });

  it("ocupa a tela toda quando não há nada atrás dela", () => {
    const { container } = render(<LoadingScreen full />);

    expect(container.firstElementChild).toHaveClass("min-h-screen");
  });
});
