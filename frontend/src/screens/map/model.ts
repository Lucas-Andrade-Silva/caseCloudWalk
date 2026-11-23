// Estado e regras visuais do mapa vivo (playbook §7; ADR 0007, I12 e I13). Funções puras: o canvas só desenha
// o que sai daqui.

export interface MapTicket {
  id: string;
  brand: string;
  channel: string;
  mode: "ai" | "pending_human" | "human" | "closed";
  priority: string;
  queue: string | null;
  tags: string[];
  cluster: { key: string; label: string };
  assignee_id: string | null;
  created_at: string;
  escalated_at: string | null;
  first_response_due_at: string | null;
  first_human_response_at: string | null;
  awaiting_agent_since: string | null;
  /** Incidente que agrupa o ticket (ADR 0009); ausente em retratos antigos. */
  incident_id?: string | null;
}

export type MapEvent = { type: "ticket.upsert"; ticket: MapTicket } | { type: "ticket.removed"; id: string };

export type MapState = ReadonlyMap<string, MapTicket>;

export interface ClusterSummary {
  key: string;
  label: string;
  count: number;
  atRisk: number;
}

const SLA_WARNING_MS = 10 * 60_000;
// O vigia escala aos 30 s de silêncio do agente (ADR 0004, H6); a partir de 20 s o nó já avisa.
const AGENT_SILENCE_WARNING_MS = 20_000;
const RADIUS: Record<string, number> = { p1: 9, p2: 7, p3: 5.5, p4: 4.5 };

export function fromSnapshot(tickets: MapTicket[]): MapState {
  return new Map(tickets.map((ticket) => [ticket.id, ticket]));
}

/** Devolve um estado novo; o anterior não muda (o React compara por referência). */
export function applyEvents(state: MapState, events: MapEvent[]): MapState {
  const next = new Map(state);
  for (const event of events) {
    if (event.type === "ticket.upsert") next.set(event.ticket.id, event.ticket);
    else next.delete(event.id);
  }
  return next;
}

export function atRisk(ticket: MapTicket, now: Date): boolean {
  const human = ticket.mode === "pending_human" || ticket.mode === "human";
  if (human && ticket.first_response_due_at && !ticket.first_human_response_at) {
    return Date.parse(ticket.first_response_due_at) - now.getTime() <= SLA_WARNING_MS;
  }
  if (ticket.mode === "ai" && ticket.awaiting_agent_since) {
    return now.getTime() - Date.parse(ticket.awaiting_agent_since) >= AGENT_SILENCE_WARNING_MS;
  }
  return false;
}

export function nodeRadius(priority: string): number {
  return RADIUS[priority] ?? RADIUS.p3!;
}

export function summarize(tickets: Iterable<MapTicket>, now: Date): ClusterSummary[] {
  const byKey = new Map<string, ClusterSummary>();
  for (const ticket of tickets) {
    const summary = byKey.get(ticket.cluster.key) ?? { key: ticket.cluster.key, label: ticket.cluster.label, count: 0, atRisk: 0 };
    summary.count++;
    if (atRisk(ticket, now)) summary.atRisk++;
    byKey.set(summary.key, summary);
  }
  return [...byKey.values()].sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

/** Teto de nós desenhados (~500): os de prioridade mais alta ficam; o resto vira a contagem "+N". */
export function capNodes(tickets: MapTicket[], limit: number): { visible: MapTicket[]; hidden: number } {
  const sorted = [...tickets].sort((a, b) => a.priority.localeCompare(b.priority) || b.created_at.localeCompare(a.created_at));
  return { visible: sorted.slice(0, limit), hidden: Math.max(0, sorted.length - limit) };
}
