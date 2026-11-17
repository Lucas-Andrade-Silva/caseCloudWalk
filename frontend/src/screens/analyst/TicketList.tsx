import type { WorkItem } from "../../lib/api";
import { BRAND_LABELS, CHANNEL_LABELS, TONE_CLASSES, customerName, dueLabel } from "../../lib/format";

interface TicketListProps {
  label: string;
  empty: string;
  items: WorkItem[];
  selectedId: string | null;
  onSelect?: (id: string) => void;
  extra?: string;
}

export function TicketList({ label, empty, items, selectedId, onSelect, extra }: TicketListProps) {
  return (
    <section aria-label={label} className="border-b border-line">
      <h2 className="flex items-center justify-between px-3 pt-3 pb-1 text-xs font-medium text-muted">
        <span>{label}</span>
        {extra && <span className="text-faint">{extra}</span>}
      </h2>
      {items.length === 0 ? (
        <p className="px-3 pb-3 text-xs text-faint">{empty}</p>
      ) : (
        <ul className="pb-2">
          {items.map((item) => (
            <li key={item.id}>
              <TicketRow item={item} selected={item.id === selectedId} onSelect={onSelect} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function TicketRow({ item, selected, onSelect }: { item: WorkItem; selected: boolean; onSelect?: (id: string) => void }) {
  const due = dueLabel(item.first_response_due_at, item.first_human_response_at);
  const content = (
    <>
      <span className="flex items-center gap-2">
        <span
          aria-hidden
          className={`size-1.5 shrink-0 rounded-full ${item.brand === "jim" ? "bg-brand-jim" : "bg-brand-infinitepay"}`}
        />
        <span className="truncate text-sm text-text">{customerName(item.customer)}</span>
        <span className="ml-auto shrink-0 font-mono text-[11px] text-muted uppercase">{item.priority}</span>
      </span>
      {item.last_message && <span className="mt-0.5 block truncate text-xs text-muted">{item.last_message.text}</span>}
      <span className="mt-1 flex items-center gap-2 text-[11px]">
        <span className="text-faint">
          {BRAND_LABELS[item.brand] ?? item.brand} · {CHANNEL_LABELS[item.channel] ?? item.channel}
          {item.queue && ` · ${item.queue}`}
        </span>
        <span className={`ml-auto shrink-0 ${TONE_CLASSES[due.tone]}`}>{due.text}</span>
      </span>
    </>
  );

  const base = "block w-full px-3 py-2 text-left";
  if (!onSelect) return <div className={base}>{content}</div>;

  return (
    <button
      type="button"
      onClick={() => onSelect(item.id)}
      aria-current={selected ? "true" : undefined}
      className={`${base} hover:bg-elevated ${selected ? "bg-elevated" : ""}`}
    >
      {content}
    </button>
  );
}
