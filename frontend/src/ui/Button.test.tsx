import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { Button } from "./Button";

describe("Button", () => {
  it("é um botão comum por padrão, que não envia formulário sem pedir", async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Pegar o próximo</Button>);

    const button = screen.getByRole("button", { name: "Pegar o próximo" });
    expect(button).toHaveAttribute("type", "button");
    await userEvent.click(button);
    expect(onClick).toHaveBeenCalledOnce();
  });

  it("ocupado: fica desabilitado, avisa leitores de tela e não dispara de novo", async () => {
    const onClick = vi.fn();
    render(
      <Button busy onClick={onClick}>
        Enviar
      </Button>,
    );

    const button = screen.getByRole("button", { name: "Enviar" });
    expect(button).toBeDisabled();
    expect(button).toHaveAttribute("aria-busy", "true");
    await userEvent.click(button);
    expect(onClick).not.toHaveBeenCalled();
  });

  it("mostra o atalho de teclado quando recebe um", () => {
    render(<Button shortcut="Ctrl Enter">Enviar</Button>);

    expect(screen.getByRole("button", { name: /Enviar/ })).toHaveTextContent("Ctrl Enter");
  });
});
