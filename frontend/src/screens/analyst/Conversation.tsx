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
import { CloseTicketDialog } from "./CloseTicketDialog";

interface ConversationProps {
  ticket: TicketDetail;
  onSend: (text: string) => Promise<void>;
  onClose: (code: ResolutionCode, note: string) => Promise<void>;
}

export function Conversation({ ticket, onSend, onClose }: ConversationProps) {
  const due = dueLabel(ticket.first_response_due_at, ticket.first_human_response_at);
  const end = useRef<HTMLDivElement>(null);
  const count = ticket.messages.length;

  useEffect(() => {
    end.current?.scrollIntoView?.({ block: "end" });
  }, [count]);

  return (
    <section aria-label="Conversa" className="flex min-w-0 flex-1 flex-col">
      <header className="flex items-center gap-3 border-b border-line px-4 py-3">
        <div className="min-w-0">
          <h1 className="truncate text-sm font-semibold">{customerName(ticket.customer)}</h1>
          <p className="text-xs text-muted">
            {BRAND_LABELS[ticket.brand] ?? ticket.brand} · {CHANNEL_LABELS[ticket.channel] ?? ticket.channel}
            {ticket.queue && ` · ${ticket.queue}`} · <span className="font-mono uppercase">{ticket.priority}</span>
          </p>
        </div>
        <span className={`ml-auto text-xs ${TONE_CLASSES[due.tone]}`}>{due.text}</span>
        {ticket.mode === "human" && <CloseTicketDialog onConfirm={onClose} />}
      </header>

      <ol className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
        {ticket.messages.map((message) => {
          const ours = message.sender !== "customer";
          return (
            <li key={message.id} className={`flex ${ours ? "justify-end" : "justify-start"}`}>
              <div
                className={`max-w-[70%] rounded-lg px-3 py-2 ${
                  message.sender === "analyst"
                    ? "bg-accent/20 text-text"
                    : message.sender === "bot"
                      ? "border border-line bg-surface text-text"
                      : "bg-elevated text-text"
                }`}
              >
                <p className="text-[11px] text-muted">
                  {SENDER_LABELS[message.sender]} · {timeOfDay(message.created_at)}
                  {message.stale && " · atrasada"}
                </p>
                <p className="mt-0.5 text-sm whitespace-pre-wrap">{message.text}</p>
              </div>
            </li>
          );
        })}
        <div ref={end} />
      </ol>

      {ticket.mode === "human" ? (
        <Composer onSend={onSend} />
      ) : (
        <p className="border-t border-line px-4 py-3 text-xs text-faint">Pegue o ticket para responder.</p>
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
    <form onSubmit={submit} className="border-t border-line p-3">
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
        className="w-full resize-none rounded-md border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-faint focus:border-accent"
      />
      <div className="mt-2 flex items-center gap-3">
        {error && (
          <p role="alert" className="text-xs text-danger">
            {error}
          </p>
        )}
        <span className="ml-auto text-[11px] text-faint">Ctrl + Enter</span>
        <button
          type="submit"
          disabled={busy || !text.trim()}
          className="h-8 rounded-md bg-accent px-3 text-sm font-medium text-white disabled:opacity-40"
        >
          Enviar
        </button>
      </div>
    </form>
  );
}
