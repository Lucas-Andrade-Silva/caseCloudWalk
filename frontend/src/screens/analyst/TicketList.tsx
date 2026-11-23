import type { WorkItem } from "../../lib/api";
import { BRAND_LABELS, CHANNEL_LABELS, TONE_CLASSES, customerName, dueLabel } from "../../lib/format";
import { BrandDot } from "../../ui/BrandDot";
import { PriorityTag } from "../../ui/PriorityTag";

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
      <h2 className="flex items-center justify-between px-4 pt-4 pb-1.5 text-xs font-semibold text-muted">
        <span>{label}</span>
        {extra && <span className="rounded-full bg-elevated px-2 py-0.5 text-[11px] text-muted tabular">{extra}</span>}
      </h2>
      {items.length === 0 ? (
        <p className="px-4 pb-4 text-xs text-faint">{empty}</p>
      ) : (
        <ul className="px-2 pb-2">
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
        <BrandDot brand={item.brand} />
        <span className="truncate text-sm font-medium text-text">{customerName(item.customer)}</span>
        <PriorityTag priority={item.priority} className="ml-auto" />
      </span>
      {item.last_message && (
        <span className="mt-1 block truncate pl-3.5 text-xs text-muted">{item.last_message.text}</span>
      )}
      <span className="mt-1.5 flex items-center gap-2 pl-3.5 text-[11px]">
        <span className="truncate text-faint">
          {BRAND_LABELS[item.brand] ?? item.brand} · {CHANNEL_LABELS[item.channel] ?? item.channel}
          {item.queue && ` · ${item.queue}`}
        </span>
        <span className={`ml-auto shrink-0 font-medium tabular ${TONE_CLASSES[due.tone]}`}>{due.text}</span>
      </span>
    </>
  );

  const base = "block w-full rounded-lg px-2.5 py-2.5 text-left";
  if (!onSelect) return <div className={base}>{content}</div>;

  return (
    <button
      type="button"
      onClick={() => onSelect(item.id)}
      aria-current={selected ? "true" : undefined}
      className={`${base} transition-colors duration-150 ${selected ? "bg-accent/8 ring-1 ring-accent/25" : "hover:bg-elevated"}`}
    >
      {content}
    </button>
  );
}
