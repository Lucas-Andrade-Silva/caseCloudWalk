import { useSyncExternalStore } from "react";

// Rotas por hash (#/fila/t1): sem biblioteca de roteamento, o app não precisa de mais que isso.
function subscribe(callback: () => void) {
  window.addEventListener("hashchange", callback);
  return () => window.removeEventListener("hashchange", callback);
}

const read = () => window.location.hash.replace(/^#/, "") || "/";

export function useHashRoute(): string {
  return useSyncExternalStore(subscribe, read);
}

export function navigate(path: string): void {
  if (read() === path) return;
  window.location.hash = path;
  // jsdom e alguns navegadores não disparam hashchange de forma síncrona.
  window.dispatchEvent(new HashChangeEvent("hashchange"));
}
