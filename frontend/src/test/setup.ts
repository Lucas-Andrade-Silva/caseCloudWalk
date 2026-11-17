import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// O jsdom não desenha canvas. O mapa vivo trata contexto nulo (não testamos pixels, playbook §7).
Object.defineProperty(HTMLCanvasElement.prototype, "getContext", { value: () => null });

afterEach(() => {
  cleanup();
  window.localStorage.clear();
});
