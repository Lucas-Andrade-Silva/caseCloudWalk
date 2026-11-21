import type { ResolutionCode, TicketDetail } from "../../lib/api";
import { CHANNEL_LABELS, RESOLUTION_LABELS, shortDate } from "../../lib/format";

export function ContextPanel({ ticket }: { ticket: TicketDetail }) {
  return (
    <section aria-label="Contexto" className="flex flex-col gap-5 overflow-y-auto p-4">
      <div>
        <h2 className="text-xs font-medium text-muted">Brief do handoff</h2>
        {ticket.handoff_brief?.llm_summary ? (
          <>
            <p className="mt-1.5 text-sm leading-relaxed text-text">{ticket.handoff_brief.llm_summary}</p>
            <p className="mt-1 text-[11px] text-accent">Gerado por IA · {ticket.handoff_brief.llm_model}</p>
            <details className="mt-2">
              <summary className="cursor-pointer text-[11px] text-faint">Resumo por template</summary>
              <p className="mt-1 text-xs leading-relaxed text-muted">{ticket.handoff_brief.summary}</p>
            </details>
          </>
        ) : ticket.handoff_brief ? (
          <p className="mt-1.5 text-sm leading-relaxed text-text">{ticket.handoff_brief.summary}</p>
        ) : (
          <p className="mt-1.5 text-xs text-faint">Sem brief.</p>
        )}
        {(ticket.llm_facts?.category || ticket.llm_facts?.frustration) && (
          <ul aria-label="Fatos da IA" className="mt-2 flex flex-wrap gap-1">
            {ticket.llm_facts.category && (
              <li className="rounded bg-accent/15 px-1.5 py-0.5 text-[11px] text-text">categoria: {ticket.llm_facts.category}</li>
            )}
            {ticket.llm_facts.frustration && (
              <li
                className={`rounded px-1.5 py-0.5 text-[11px] ${
                  ticket.llm_facts.frustration === "alta" ? "bg-danger/15 text-danger" : "bg-elevated text-muted"
                }`}
              >
                frustração: {ticket.llm_facts.frustration}
              </li>
            )}
          </ul>
        )}
        {ticket.tags.length > 0 && (
          <ul className="mt-2 flex flex-wrap gap-1">
            {ticket.tags.map((tag) => (
              <li key={tag} className="rounded border border-line px-1.5 py-0.5 font-mono text-[11px] text-muted">
                {tag}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div>
        <h2 className="flex items-baseline justify-between text-xs font-medium text-muted">
          <span>Memória do cliente</span>
          <span className="text-faint">últimos {ticket.memory.window_days} dias</span>
        </h2>
        {ticket.memory.tickets.length === 0 ? (
          <p className="mt-1.5 text-xs text-faint">Primeiro contato nesta marca.</p>
        ) : (
          <ol className="mt-2 space-y-2">
            {ticket.memory.tickets.map((past) => (
              <li key={past.ticket_id} className="rounded-md border border-line bg-surface p-2.5">
                <p className="flex justify-between text-[11px] text-faint">
                  <span>
                    {shortDate(past.opened_at)} · {CHANNEL_LABELS[past.channel] ?? past.channel}
                  </span>
                  <span>
                    {past.resolution_code ? RESOLUTION_LABELS[past.resolution_code as ResolutionCode] : "em aberto"}
                  </span>
                </p>
                <p className="mt-1 text-xs leading-relaxed text-muted">
                  {past.summary ?? "Resumo expirado."}
                </p>
              </li>
            ))}
          </ol>
        )}
      </div>
    </section>
  );
}
