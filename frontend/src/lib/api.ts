// Cliente da API da plataforma. O Vite repassa /api para o Rails (ADR 0007, I6).
export type Role = "analyst" | "ops";

export interface Me {
  id: string;
  name: string;
  role: Role;
  brands: string[];
}

export interface Customer {
  external_id: string;
  name: string | null;
}

export type TicketMode = "ai" | "pending_human" | "human" | "closed";

export interface WorkItem {
  id: string;
  brand: string;
  channel: string;
  mode: TicketMode;
  priority: string;
  queue: string | null;
  tags: string[];
  customer: Customer;
  escalated_at: string | null;
  first_response_due_at: string | null;
  first_human_response_at: string | null;
  last_message: { sender: string; text: string; created_at: string } | null;
}

export interface Work {
  mine: WorkItem[];
  waiting: WorkItem[];
  waiting_count: number;
}

export interface Message {
  id: string;
  seq: number;
  sender: "customer" | "bot" | "analyst";
  text: string;
  stale: boolean;
  created_at: string;
}

export interface MemoryItem {
  ticket_id: string;
  channel: string;
  mode: TicketMode;
  opened_at: string;
  closed_at: string | null;
  priority: string;
  queue: string | null;
  tags: string[];
  escalation_reason: string | null;
  resolution_code: string | null;
  summary: string | null;
}

export interface TicketDetail extends Omit<WorkItem, "last_message"> {
  assignee_id: string | null;
  closed_at: string | null;
  resolution_code: string | null;
  handoff_brief: { summary: string; reason: string; trigger: string } | null;
  messages: Message[];
  memory: { window_days: number; tickets: MemoryItem[] };
}

export const RESOLUTION_CODES = ["resolved", "no_customer_response", "duplicate", "forwarded"] as const;
export type ResolutionCode = (typeof RESOLUTION_CODES)[number];

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function request<T>(token: string, path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json", Authorization: `Bearer ${token}` };
  const options: RequestInit = { headers };
  if (init.method) options.method = init.method;
  if (init.body !== undefined) {
    headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(init.body);
  }

  const response = await fetch(path, options);
  if (response.status === 204) return null as T;

  const body: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const message = body && typeof body === "object" && "error" in body ? String(body.error) : response.statusText;
    throw new ApiError(response.status, message);
  }
  return body as T;
}

export const fetchMe = (token: string) => request<Me>(token, "/api/me");
export const fetchWork = (token: string) => request<Work>(token, "/api/work");
export const fetchTicket = (token: string, id: string) => request<TicketDetail>(token, `/api/tickets/${id}`);

/** Pega o ticket de prazo mais próximo nas filas do analista. Devolve null se não há nada esperando. */
export const takeNext = (token: string) => request<{ id: string } | null>(token, "/api/work/next", { method: "POST" });

export const sendMessage = (token: string, id: string, text: string) =>
  request<{ message_id: string; seq: number; sla_met: boolean | null }>(token, `/api/tickets/${id}/messages`, {
    method: "POST",
    body: { text },
  });

export const closeTicket = (token: string, id: string, resolutionCode: ResolutionCode, resolutionNote: string) =>
  request<{ id: string }>(token, `/api/tickets/${id}/close`, {
    method: "POST",
    body: { resolution_code: resolutionCode, resolution_note: resolutionNote },
  });
