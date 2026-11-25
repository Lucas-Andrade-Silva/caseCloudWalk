import { History, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import type { TicketDetail } from "../../lib/api";
import { CHANNEL_LABELS, resolutionLabel, shortDate } from "../../lib/format";

function Heading({ icon, children, aside }: { icon: ReactNode; children: ReactNode; aside?: ReactNode }) {
  return (
    <h2 className="flex items-center gap-2 text-xs font-semibold text-text">
      {icon}
      {children}
      {aside && <span className="ml-auto text-[11px] font-normal text-faint">{aside}</span>}
    </h2>
  );
}

export function ContextPanel({ ticket }: { ticket: TicketDetail }) {
  const facts = ticket.llm_facts;
  return (
    <section aria-label="Contexto" className="flex flex-col gap-7 p-5">
      <div>
        <Heading icon={<Sparkles aria-hidden className="size-3.5 text-accent" strokeWidth={2} />}>Brief do handoff</Heading>
        {ticket.handoff_brief?.llm_summary ? (
          <>
            <p className="mt-2.5 text-sm leading-relaxed text-text">{ticket.handoff_brief.llm_summary}</p>
            <p className="mt-2 text-[11px] font-medium text-accent">Gerado por IA · {ticket.handoff_brief.llm_model}</p>
          </>
        ) : ticket.handoff_brief ? (
          <p className="mt-2.5 text-sm leading-relaxed text-text">{ticket.handoff_brief.summary}</p>
        ) : (
          <p className="mt-2.5 text-xs text-faint">Sem brief.</p>
        )}
        {(facts?.category || facts?.frustration || ticket.tags.length > 0) && (
          <ul aria-label="Fatos do ticket" className="mt-3 flex flex-wrap gap-1.5">
            {facts?.category && (
              <li className="rounded-full bg-accent/10 px-2 py-0.5 text-[11px] font-medium text-accent-ink">
                categoria: {facts.category}
              </li>
            )}
            {facts?.frustration && (
              <li
                className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${
                  facts.frustration === "alta" ? "bg-danger/10 text-danger-ink" : "bg-elevated text-muted"
                }`}
              >
                frustração: {facts.frustration}
              </li>
            )}
            {ticket.tags.map((tag) => (
              <li key={tag} className="rounded-full border border-line px-2 py-0.5 text-[11px] text-muted">
                {tag}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div>
        <Heading
          icon={<History aria-hidden className="size-3.5 text-muted" strokeWidth={2} />}
          aside={`últimos ${ticket.memory.window_days} dias`}
        >
          Memória do cliente
        </Heading>
        {ticket.memory.tickets.length === 0 ? (
          <p className="mt-2.5 text-xs text-faint">Primeiro contato nesta marca.</p>
        ) : (
          <ol className="mt-3 space-y-4 border-l border-line pl-4">
            {ticket.memory.tickets.map((past) => (
              <li key={past.ticket_id} className="relative">
                <span
                  aria-hidden
                  className={`absolute top-1.5 -left-[19px] size-[7px] rounded-full ring-2 ring-surface ${
                    past.resolution_code ? "bg-line-strong" : "bg-warning"
                  }`}
                />
                <p className="flex justify-between gap-2 text-[11px] text-faint">
                  <span>
                    {shortDate(past.opened_at)} · {CHANNEL_LABELS[past.channel] ?? past.channel}
                  </span>
                  <span>
                    {past.resolution_code ? resolutionLabel(past.resolution_code) : "em aberto"}
                  </span>
                </p>
                <p className="mt-1 text-xs leading-relaxed text-muted">{past.summary ?? "Resumo expirado."}</p>
              </li>
            ))}
          </ol>
        )}
      </div>
    </section>
  );
}
