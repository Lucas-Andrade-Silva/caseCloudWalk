import type { MapEvent } from "./model";

// Cliente mínimo do protocolo do ActionCable para o canal do mapa (ADR 0007, I13). O cliente oficial não deixa
// escolher o subprotocolo, e o token vai nele, nunca na URL.

export interface SocketLike {
  onopen: (() => void) | null;
  onmessage: ((event: { data: string }) => void) | null;
  onclose: (() => void) | null;
  send(data: string): void;
  close(): void;
}

export type SocketFactory = new (url: string, protocols: string[]) => SocketLike;

export type CableStatus = "connecting" | "live" | "offline";

interface Options {
  url: string;
  token: string;
  brands: string[];
  onEvent: (event: MapEvent) => void;
  onStatus: (status: CableStatus) => void;
  socket?: SocketFactory;
}

const PROTOCOL = "actioncable-v1-json";
const MAX_BACKOFF_MS = 30_000;

export function tokenProtocol(token: string): string {
  const bytes = new TextEncoder().encode(token);
  const base64 = btoa(String.fromCharCode(...bytes));
  return `helpdesk-token.${base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")}`;
}

export function connectMap({ url, token, brands, onEvent, onStatus, socket = WebSocket as unknown as SocketFactory }: Options) {
  let current: SocketLike | null = null;
  let attempts = 0;
  let closed = false;
  let retry: ReturnType<typeof setTimeout> | null = null;

  function open() {
    onStatus("connecting");
    const ws = new socket(url, [PROTOCOL, tokenProtocol(token)]);
    current = ws;

    ws.onmessage = (event) => {
      let frame: { type?: string; message?: unknown };
      try {
        frame = JSON.parse(event.data);
      } catch {
        return;
      }
      if (frame.type === "welcome") {
        for (const brand of brands) {
          ws.send(JSON.stringify({ command: "subscribe", identifier: JSON.stringify({ channel: "MapChannel", brand }) }));
        }
      } else if (frame.type === "confirm_subscription") {
        attempts = 0;
        onStatus("live");
      } else if (frame.type === undefined && frame.message && typeof frame.message === "object") {
        onEvent(frame.message as MapEvent);
      }
    };

    ws.onclose = () => {
      if (closed) return;
      onStatus("offline");
      attempts++;
      const wait = Math.min(1000 * 2 ** (attempts - 1), MAX_BACKOFF_MS);
      retry = setTimeout(open, wait);
    };
  }

  open();

  return {
    close() {
      closed = true;
      if (retry) clearTimeout(retry);
      current?.close();
    },
  };
}

/** URL do WebSocket na mesma origem da página (o Vite repassa /cable para o Rails). */
export function cableUrl(): string {
  const scheme = window.location.protocol === "https:" ? "wss" : "ws";
  return `${scheme}://${window.location.host}/cable`;
}
