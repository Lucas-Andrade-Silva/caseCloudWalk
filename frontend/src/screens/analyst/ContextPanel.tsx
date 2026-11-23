import { History, Sparkles } from "lucide-react";
import type { ReactNode } from "react";
import type { ResolutionCode, TicketDetail } from "../../lib/api";
import { CHANNEL_LABELS, RESOLUTION_LABELS, shortDate } from "../../lib/format";

function Heading({ icon, children, aside }: { icon: ReactNode; children: ReactNode; aside?: ReactNode }) {
  return (
    <h2 className="flex items-center gap-2 text-xs font-semibold text-text">
      {icon}
      {children}
      {aside && <span className="ml-auto font-mono text-[11px] font-normal text-faint">{aside}</span>}
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
            <p className="mt-2 font-mono text-[11px] text-accent">Gerado por IA · {ticket.handoff_brief.llm_model}</p>
            <details className="group mt-2">
              <summary className="cursor-pointer text-[11px] text-faint hover:text-muted">Resumo por template</summary>
              <p className="mt-1.5 text-xs leading-relaxed text-muted">{ticket.handoff_brief.summary}</p>
            </details>
          </>
        ) : ticket.handoff_brief ? (
          <p className="mt-2.5 text-sm leading-relaxed text-text">{ticket.handoff_brief.summary}</p>
        ) : (
          <p className="mt-2.5 text-xs text-faint">Sem brief.</p>
        )}
        {(facts?.category || facts?.frustration || ticket.tags.length > 0) && (
          <ul aria-label="Fatos do ticket" className="mt-3 flex flex-wrap gap-1.5">
            {facts?.category && (
              <li className="rounded bg-accent/12 px-1.5 py-0.5 font-mono text-[11px] text-accent">
                categoria: {facts.category}
              </li>
            )}
            {facts?.frustration && (
              <li
                className={`rounded px-1.5 py-0.5 font-mono text-[11px] ${
                  facts.frustration === "alta" ? "bg-danger/12 text-danger" : "bg-elevated text-muted"
                }`}
              >
                frustração: {facts.frustration}
              </li>
            )}
            {ticket.tags.map((tag) => (
              <li key={tag} className="rounded border border-line-strong px-1.5 py-0.5 font-mono text-[11px] text-muted">
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
                  className={`absolute top-1.5 -left-[19px] size-[7px] rounded-full ring-2 ring-bg ${
                    past.resolution_code ? "bg-line-strong" : "bg-warning"
                  }`}
                />
                <p className="flex justify-between gap-2 font-mono text-[11px] text-faint">
                  <span>
                    {shortDate(past.opened_at)} · {CHANNEL_LABELS[past.channel] ?? past.channel}
                  </span>
                  <span>
                    {past.resolution_code ? RESOLUTION_LABELS[past.resolution_code as ResolutionCode] : "em aberto"}
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
