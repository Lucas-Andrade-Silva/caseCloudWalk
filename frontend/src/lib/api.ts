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
  handoff_brief: {
    summary: string;
    reason: string;
    trigger: string;
    /** Resumo do LLM (ADR 0008); o `summary` por template fica de reserva. */
    llm_summary?: string;
    llm_model?: string;
  } | null;
  /** Fatos que o LLM deu ao ticket (categoria, idioma, frustração, confiança); vazio sem enriquecimento. */
  llm_facts?: { category?: string | null; language?: string; frustration?: string; confidence?: number; source?: string };
  messages: Message[];
  memory: { window_days: number; tickets: MemoryItem[] };
}

export const RESOLUTION_CODES = ["resolved", "no_customer_response", "duplicate", "forwarded"] as const;
export type ResolutionCode = (typeof RESOLUTION_CODES)[number];

export interface FieldError {
  path: string;
  message: string;
}

export class ApiError extends Error {
  readonly status: number;
  /** Erros de validação com o caminho do campo (respostas 422 da operação). */
  readonly details: FieldError[];

  constructor(status: number, message: string, details: FieldError[] = []) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

function errorFrom(status: number, statusText: string, body: unknown): ApiError {
  if (body && typeof body === "object") {
    if ("errors" in body && Array.isArray(body.errors)) {
      const details = body.errors as FieldError[];
      return new ApiError(status, details.map((error) => `${error.path}: ${error.message}`).join("; "), details);
    }
    if ("error" in body) return new ApiError(status, String(body.error));
  }
  return new ApiError(status, statusText);
}

export async function request<T>(token: string, path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
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
  if (!response.ok) throw errorFrom(response.status, response.statusText, body);
  return body as T;
}

export const fetchMe = (token: string) => request<Me>(token, "/api/me");

/** Retrato inicial do mapa vivo: tickets abertos das marcas que a pessoa enxerga. */
export const fetchMap = <T>(token: string) => request<{ total: number; limit: number; tickets: T[] }>(token, "/api/map");
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
