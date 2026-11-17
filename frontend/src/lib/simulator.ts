import { ApiError } from "./api";

// Canal simulado do chat do cliente (ADR 0007, I7). Sem token: o cliente não tem login.
export interface CustomerIdentity {
  brand: string;
  channel: string;
  external_id: string;
  name: string;
}

export interface CustomerMessage {
  seq: number;
  sender: "customer" | "bot" | "analyst";
  text: string;
  created_at: string;
}

export interface CustomerConversation {
  ticket_id: string | null;
  mode: "ai" | "pending_human" | "human" | "closed" | null;
  messages: CustomerMessage[];
}

async function parse<T>(response: Response): Promise<T> {
  const body: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const message = body && typeof body === "object" && "error" in body ? String(body.error) : response.statusText;
    throw new ApiError(response.status, message);
  }
  return body as T;
}

export async function fetchConversation(identity: CustomerIdentity): Promise<CustomerConversation> {
  const query = new URLSearchParams({
    brand: identity.brand,
    channel: identity.channel,
    external_id: identity.external_id,
  });
  return parse(await fetch(`/api/simulator/conversation?${query}`, { headers: { Accept: "application/json" } }));
}

export async function sendCustomerMessage(identity: CustomerIdentity, text: string): Promise<void> {
  await parse(
    await fetch("/api/simulator/messages", {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify({
        brand: identity.brand,
        channel: identity.channel,
        customer: { external_id: identity.external_id, name: identity.name },
        text,
      }),
    }),
  );
}

const KEY = "helpdesk.customer";

export function loadIdentity(): CustomerIdentity | null {
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as CustomerIdentity) : null;
  } catch {
    return null;
  }
}

export function saveIdentity(identity: CustomerIdentity): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(identity));
  } catch {
    // Sem armazenamento: o cliente vale só enquanto a página estiver aberta.
  }
}

export function clearIdentity(): void {
  try {
    window.localStorage.removeItem(KEY);
  } catch {
    // Nada a limpar.
  }
}

export function newExternalId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(3));
  return `cliente-${Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}
