import { Bot, Send } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from "react";
import type { ResolutionCode, TicketDetail } from "../../lib/api";
import {
  BRAND_LABELS,
  CHANNEL_LABELS,
  SENDER_LABELS,
  TONE_CLASSES,
  customerName,
  dueLabel,
  timeOfDay,
} from "../../lib/format";
import { BrandDot } from "../../ui/BrandDot";
import { Button } from "../../ui/Button";
import { Kbd } from "../../ui/Kbd";
import { PriorityTag } from "../../ui/PriorityTag";
import { fieldClass } from "../../ui/field";
import { CloseTicketDialog } from "./CloseTicketDialog";

interface ConversationProps {
  ticket: TicketDetail;
  onSend: (text: string) => Promise<void>;
  onClose: (code: ResolutionCode, note: string) => Promise<void>;
}

const BUBBLES: Record<string, string> = {
  analyst: "bg-accent/12 text-text ring-1 ring-accent/25",
  bot: "bg-surface text-text ring-1 ring-line",
  customer: "bg-elevated text-text",
  // Fundo do quadro da conversa: cinza bem claro, para os balões brancos se destacarem.
};

export function Conversation({ ticket, onSend, onClose }: ConversationProps) {
  const due = dueLabel(ticket.first_response_due_at, ticket.first_human_response_at);
  const end = useRef<HTMLLIElement>(null);
  const count = ticket.messages.length;

  useEffect(() => {
    end.current?.scrollIntoView?.({ block: "end" });
  }, [count]);

  return (
    <section aria-label="Conversa" className="flex min-w-0 flex-1 flex-col overflow-hidden rounded-xl border border-line bg-surface shadow-card">
      <header className="flex min-h-14 items-center gap-3 border-b border-line px-5 py-2.5">
        <div className="min-w-0">
          <h1 className="flex items-center gap-2 truncate text-[15px] font-semibold tracking-tight">
            <BrandDot brand={ticket.brand} />
            {customerName(ticket.customer)}
            <PriorityTag priority={ticket.priority} />
          </h1>
          <p className="mt-0.5 truncate text-xs text-faint">
            {BRAND_LABELS[ticket.brand] ?? ticket.brand} · {CHANNEL_LABELS[ticket.channel] ?? ticket.channel}
            {ticket.queue && ` · ${ticket.queue}`}
          </p>
        </div>
        <span className={`ml-auto shrink-0 text-xs font-medium whitespace-nowrap tabular ${TONE_CLASSES[due.tone]}`}>
          {due.text}
        </span>
        {ticket.mode === "human" && <CloseTicketDialog onConfirm={onClose} />}
      </header>

      <ol className="flex-1 space-y-4 overflow-y-auto bg-bg/60 px-5 py-5">
        {ticket.messages.map((message) => {
          const ours = message.sender !== "customer";
          return (
            <li key={message.id} className={`flex animate-rise ${ours ? "justify-end" : "justify-start"}`}>
              <div className={`max-w-[68%] rounded-lg px-3.5 py-2.5 ${BUBBLES[message.sender] ?? BUBBLES.customer}`}>
                <p className="flex items-center gap-1.5 text-[11px] text-faint">
                  {message.sender === "bot" && <Bot aria-hidden className="size-3 text-accent" strokeWidth={2} />}
                  {SENDER_LABELS[message.sender]} · <time className="tabular">{timeOfDay(message.created_at)}</time>
                  {message.stale && <span className="text-warning"> · atrasada</span>}
                </p>
                <p className="mt-1 text-sm leading-relaxed whitespace-pre-wrap">{message.text}</p>
              </div>
            </li>
          );
        })}
        {/* Marcador para rolar até a última mensagem; filho de <ol> precisa ser <li>. */}
        <li ref={end} aria-hidden className="h-0" />
      </ol>

      {ticket.mode === "human" ? (
        <Composer onSend={onSend} />
      ) : (
        <p className="border-t border-line px-5 py-4 text-xs text-faint">Pegue o ticket para responder.</p>
      )}
    </section>
  );
}

function Composer({ onSend }: { onSend: (text: string) => Promise<void> }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event?: FormEvent) {
    event?.preventDefault();
    const value = text.trim();
    if (!value || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSend(value);
      setText("");
    } catch {
      setError("A mensagem não foi enviada. Tente de novo.");
    } finally {
      setBusy(false);
    }
  }

  // Ctrl+Enter (ou Cmd+Enter) envia, como nas ferramentas de atendimento.
  function onKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) void submit();
  }

  return (
    <form onSubmit={submit} className="border-t border-line px-5 py-4">
      <label htmlFor="reply" className="sr-only">
        Resposta ao cliente
      </label>
      <textarea
        id="reply"
        value={text}
        onChange={(event) => setText(event.target.value)}
        onKeyDown={onKeyDown}
        rows={3}
        placeholder="Escreva para o cliente…"
        className={`${fieldClass} resize-none py-2.5 leading-relaxed`}
      />
      <div className="mt-2.5 flex items-center gap-3">
        {error && (
          <p role="alert" className="text-xs text-danger">
            {error}
          </p>
        )}
        <span className="ml-auto flex items-center gap-1 text-[11px] text-faint">
          <Kbd>Ctrl</Kbd>
          <Kbd>Enter</Kbd>
        </span>
        <Button type="submit" variant="primary" size="sm" busy={busy} disabled={!text.trim()}>
          <Send aria-hidden className="size-3.5" strokeWidth={2} />
          Enviar
        </Button>
      </div>
    </form>
  );
}
