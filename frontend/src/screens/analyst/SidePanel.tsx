import { useRef, useState, type KeyboardEvent } from "react";
import type { TicketDetail } from "../../lib/api";
import { ContextPanel } from "./ContextPanel";
import { DecisionTrail } from "./DecisionTrail";

const TABS = [
  { id: "context", label: "Contexto" },
  { id: "why", label: "Por que a IA decidiu" },
] as const;

type Tab = (typeof TABS)[number]["id"];

// Painel lateral do ticket: o contexto para atender e a cadeia de decisão da IA (ADR 0009). Abas no padrão
// WAI-ARIA: setas trocam a aba e o foco.
export function SidePanel({ token, ticket }: { token: string; ticket: TicketDetail }) {
  const [tab, setTab] = useState<Tab>("context");
  const refs = useRef<Record<Tab, HTMLButtonElement | null>>({ context: null, why: null });

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    const index = TABS.findIndex((item) => item.id === tab);
    const next = TABS[(index + (event.key === "ArrowRight" ? 1 : TABS.length - 1)) % TABS.length]!.id;
    setTab(next);
    refs.current[next]?.focus();
  }

  return (
    <aside className="flex w-80 shrink-0 flex-col border-l border-line bg-bg">
      <div role="tablist" aria-label="Painel do ticket" onKeyDown={onKeyDown} className="flex gap-1 border-b border-line px-3">
        {TABS.map((item) => {
          const selected = item.id === tab;
          return (
            <button
              key={item.id}
              ref={(element) => {
                refs.current[item.id] = element;
              }}
              type="button"
              role="tab"
              id={`tab-${item.id}`}
              aria-selected={selected}
              aria-controls={`panel-${item.id}`}
              tabIndex={selected ? 0 : -1}
              onClick={() => setTab(item.id)}
              className={`-mb-px border-b-2 px-2 py-3 text-xs font-medium transition-colors duration-150 ${
                selected ? "border-accent text-text" : "border-transparent text-muted hover:text-text"
              }`}
            >
              {item.label}
            </button>
          );
        })}
      </div>
      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`} className="min-h-0 flex-1 overflow-y-auto">
        {tab === "context" ? <ContextPanel ticket={ticket} /> : <DecisionTrail token={token} ticketId={ticket.id} />}
      </div>
    </aside>
  );
}
