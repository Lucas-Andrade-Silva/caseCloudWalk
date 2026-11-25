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

/** Pico de tickets parecidos da mesma marca, agrupados (ADR 0009, Modo Incidente). */
export interface Incident {
  id: string;
  key: string;
  label: string;
  brand: string;
  status: "open" | "resolved";
  title: string;
  draft_reply: string;
  /** "template" quando a LLM não escreveu; senão, a origem da resposta dela (stub, replay ou live). */
  title_source: string;
  model: string | null;
  opened_at: string;
  resolved_at: string | null;
  open_tickets: number;
  total_tickets: number;
}

export interface IncidentResolution {
  closed: number;
  skipped: { id: string; reason: string }[];
  incident: Incident;
}

export const fetchIncidents = (token: string) => request<{ incidents: Incident[] }>(token, "/api/incidents");

/** Responder a todos: assume, responde e fecha os tickets do incidente que não estão com outro analista. */
export const resolveIncident = (token: string, id: string, text: string, resolutionCode: ResolutionCode) =>
  request<IncidentResolution>(token, `/api/incidents/${id}/resolve`, {
    method: "POST",
    body: { text, resolution_code: resolutionCode },
  });

/** Um passo da cadeia de decisão de um ticket ("Por que a IA decidiu", ADR 0009). */
export type ExplanationStep = { at: string; actor: string } & (
  | { kind: "opened"; channel: string }
  | {
      kind: "rule";
      step: string;
      rule_set_version: number | null;
      rule: { id: string; name: string; when: unknown } | null;
      output: { queue: string | null; priority: string | null; tags: string[] };
      facts: Record<string, unknown>;
    }
  | {
      kind: "llm_facts";
      category: string | null;
      language: string;
      frustration: string;
      confidence: number;
      accepted: boolean;
      min_confidence: number;
      source: string;
      model: string;
      prompt_version: string;
    }
  | { kind: "llm_fallback" | "brief_fallback"; reason: string }
  | { kind: "escalated"; trigger: string; reason: string; priority: string }
  | { kind: "brief"; source: string; model: string; prompt_version: string }
  | { kind: "incident"; incident_id: string; key: string }
);

export interface Explanation {
  ticket_id: string;
  /** Primeira mensagem do cliente como a LLM a recebe: dados pessoais trocados por marcadores. */
  redacted_text: string;
  redactions: Record<string, number>;
  trace_id: string | null;
  steps: ExplanationStep[];
}

export const fetchExplanation = (token: string, id: string) => request<Explanation>(token, `/api/tickets/${id}/explanation`);

/** Números do Painel, todos lidos do banco (ADR 0009, W8). Janela de 7 dias contando hoje. */
export interface DashboardMetrics {
  generated_at: string;
  time_zone: string;
  open: { total: number; ai: number; pending_human: number; human: number; incidents: number };
  today: { created: number; closed: number };
  yesterday: { created: number; closed: number };
  daily: { date: string; created: number; closed: number }[];
  first_reply: {
    mean_seconds: number | null;
    answered: number;
    buckets: { key: "up_to_5m" | "5m_to_15m" | "15m_to_1h" | "over_1h" | "waiting"; count: number }[];
  };
  sla: { met: number; missed: number };
  resolution: { ai: number; human: number };
  channels: { channel: string; count: number }[];
  resolution_time: { median_seconds: number | null; ai_median_seconds: number | null; human_median_seconds: number | null; resolved: number };
  team: {
    active: number;
    total: number;
    agents: { id: string; name: string; resolved: number; open: number; reply_median_seconds: number | null; sla_percent: number | null }[];
  };
  operations: {
    stale: number;
    unassigned: number;
    tickets: { id: string; agent: string | null; agent_id: string | null; priority: string; brand: string; mode: string; subject: string }[];
  };
}

export const fetchDashboard = (token: string) => request<DashboardMetrics>(token, "/api/dashboard");

/** Detalhe de um analista (ADR 0011): só números, nunca o texto das conversas dele. */
export interface AnalystDetailData {
  generated_at: string;
  time_zone: string;
  agent: { id: string; name: string; brands: string[] };
  open: number;
  received: number;
  answered: number;
  resolved: number;
  messages_sent: number;
  first_reply: { mean_seconds: number | null; answered: number };
  sla: { met: number; missed: number; percent: number | null };
  resolution_time: { mean_seconds: number | null; median_seconds: number | null; resolved: number };
  subjects: { category: string | null; count: number }[];
  brands: { brand: string; count: number }[];
  daily: { date: string; received: number; resolved: number }[];
}

export const fetchAnalystDetail = (token: string, id: string) => request<AnalystDetailData>(token, `/api/dashboard/analysts/${id}`);

/** Detalhe do tempo de solução (ADR 0011): da abertura ao fechamento dos tickets fechados nos últimos 7 dias. */
export interface ResolutionDetailData {
  generated_at: string;
  time_zone: string;
  target_seconds: number;
  resolved: number;
  median_seconds: number | null;
  mean_seconds: number | null;
  within_target_percent: number | null;
  by_resolver: Record<"ai" | "human", { count: number; median_seconds: number | null; mean_seconds: number | null }>;
  buckets: { key: "up_to_15m" | "15m_to_1h" | "1h_to_8h" | "8h_to_24h" | "over_24h"; count: number }[];
  brands: { brand: string; resolved: number; median_seconds: number | null }[];
  categories: { category: string | null; resolved: number; median_seconds: number | null }[];
  slowest: { id: string; brand: string; category: string | null; seconds: number; resolved_by: "ai" | "human"; agent: string | null }[];
  daily: { date: string; resolved: number; median_seconds: number | null }[];
}

export const fetchResolutionDetail = (token: string) => request<ResolutionDetailData>(token, "/api/dashboard/resolution");

/** Detalhe do card "Desempenho do time" (ADR 0011): o time todo nos últimos 7 dias, só números. */
export interface TeamDetailData {
  generated_at: string;
  time_zone: string;
  totals: {
    received: number;
    answered: number;
    resolved: number;
    open: number;
    messages_sent: number;
    first_reply_mean_seconds: number | null;
    sla_percent: number | null;
    solution_mean_seconds: number | null;
  };
  agents: {
    id: string;
    name: string;
    brands: string[];
    received: number;
    answered: number;
    resolved: number;
    open: number;
    first_reply_mean_seconds: number | null;
    sla_percent: number | null;
    solution_mean_seconds: number | null;
    top_subject: string | null;
  }[];
  subjects: { category: string | null; count: number }[];
  daily: { date: string; received: number; resolved: number }[];
}

export const fetchTeamDetail = (token: string) => request<TeamDetailData>(token, "/api/dashboard/team");

/** Detalhe do card "Operação dos tickets" (ADR 0011): o que pede gente agora e o que está parado. */
export interface TicketsDetailData {
  generated_at: string;
  time_zone: string;
  counts: {
    attention: number;
    unassigned: number;
    overdue: number;
    stale: number;
    by_priority: Record<"p1" | "p2" | "p3" | "p4", number>;
    by_brand: { brand: string; count: number }[];
  };
  tickets: {
    id: string;
    brand: string;
    priority: string;
    mode: "pending_human" | "human";
    agent: string | null;
    agent_id: string | null;
    category: string | null;
    subject: string;
    waiting_seconds: number | null;
    first_response_due_at: string | null;
    first_human_response_at: string | null;
    overdue: boolean;
  }[];
  stale_tickets: { id: string; brand: string; priority: string; mode: string; agent: string | null; agent_id: string | null; subject: string; age_seconds: number }[];
}

export const fetchTicketsDetail = (token: string) => request<TicketsDetailData>(token, "/api/dashboard/tickets");
