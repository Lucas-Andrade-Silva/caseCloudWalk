import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { ApiError } from "../../lib/api";
import { BRAND_LABELS, CHANNEL_LABELS, timeOfDay } from "../../lib/format";
import {
  clearIdentity,
  fetchConversation,
  loadIdentity,
  newExternalId,
  saveIdentity,
  sendCustomerMessage,
  type CustomerConversation,
  type CustomerIdentity,
} from "../../lib/simulator";
import { usePolling } from "../../lib/usePolling";

const REFRESH_MS = 2_000;

const STATUS: Record<NonNullable<CustomerConversation["mode"]>, string> = {
  ai: "Atendimento automático",
  pending_human: "Aguardando uma pessoa da equipe",
  human: "Em atendimento com uma pessoa da equipe",
  closed: "Atendimento encerrado. Mande uma mensagem para abrir outro.",
};

const SENDER: Record<string, string> = { bot: "Assistente", analyst: "Equipe" };

// Chat do cliente simulado (ADR 0007, I7 a I9): faz o papel do app, do WhatsApp ou do e-mail do cliente.
export function CustomerChat() {
  const [identity, setIdentity] = useState<CustomerIdentity | null>(loadIdentity);

  if (!identity) {
    return (
      <Setup
        onStart={(next) => {
          saveIdentity(next);
          setIdentity(next);
        }}
      />
    );
  }

  return (
    <Chat
      identity={identity}
      onReset={() => {
        clearIdentity();
        setIdentity(null);
      }}
    />
  );
}

function Setup({ onStart }: { onStart: (identity: CustomerIdentity) => void }) {
  const [brand, setBrand] = useState("infinitepay");
  const [channel, setChannel] = useState("app_chat");
  const [name, setName] = useState("");

  function submit(event: FormEvent) {
    event.preventDefault();
    onStart({ brand, channel, name: name.trim(), external_id: newExternalId() });
  }

  const field = "mt-1 h-9 w-full rounded-md border border-line bg-surface px-3 text-sm text-text outline-none focus:border-accent";

  return (
    <main className="flex min-h-screen items-center justify-center bg-bg px-4 text-text">
      <form onSubmit={submit} className="w-full max-w-sm space-y-4">
        <div>
          <p className="text-xs font-medium tracking-widest text-muted uppercase">Canal simulado</p>
          <h1 className="mt-1 text-lg font-semibold">Falar com o atendimento</h1>
          <p className="mt-1 text-xs text-muted">Você faz o papel do cliente. Os dados são sintéticos.</p>
        </div>
        <div>
          <label htmlFor="brand" className="text-xs text-muted">
            Marca
          </label>
          <select id="brand" value={brand} onChange={(event) => setBrand(event.target.value)} className={field}>
            <option value="infinitepay">InfinitePay</option>
            <option value="jim">JIM</option>
          </select>
        </div>
        <div>
          <label htmlFor="channel" className="text-xs text-muted">
            Canal
          </label>
          <select id="channel" value={channel} onChange={(event) => setChannel(event.target.value)} className={field}>
            <option value="app_chat">App</option>
            <option value="whatsapp">WhatsApp</option>
            <option value="email">E-mail</option>
          </select>
        </div>
        <div>
          <label htmlFor="name" className="text-xs text-muted">
            Seu nome
          </label>
          <input id="name" value={name} onChange={(event) => setName(event.target.value)} className={field} />
        </div>
        <button
          type="submit"
          disabled={!name.trim()}
          className="h-9 w-full rounded-md bg-accent text-sm font-medium text-white disabled:opacity-40"
        >
          Começar conversa
        </button>
      </form>
    </main>
  );
}

function Chat({ identity, onReset }: { identity: CustomerIdentity; onReset: () => void }) {
  const load = useCallback(() => fetchConversation(identity), [identity]);
  const conversation = usePolling(load, REFRESH_MS);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const end = useRef<HTMLDivElement>(null);
  const count = conversation.data?.messages.length ?? 0;

  useEffect(() => {
    end.current?.scrollIntoView?.({ block: "end" });
  }, [count]);

  const disabled = conversation.error instanceof ApiError && conversation.error.status === 404;

  async function submit(event: FormEvent) {
    event.preventDefault();
    const value = text.trim();
    if (!value || sending) return;
    setSending(true);
    setSendError(null);
    try {
      await sendCustomerMessage(identity, value);
      setText("");
      await conversation.reload();
    } catch {
      setSendError("Sua mensagem não foi enviada. Tente de novo.");
    } finally {
      setSending(false);
    }
  }

  const mode = conversation.data?.mode ?? null;

  return (
    <main className="flex h-screen flex-col bg-bg text-text">
      <header className="flex items-center gap-3 border-b border-line px-4 py-3">
        <div className="min-w-0">
          <h1 className="text-sm font-semibold">Atendimento {BRAND_LABELS[identity.brand] ?? identity.brand}</h1>
          <p className="truncate text-xs text-muted">
            {identity.name} · {BRAND_LABELS[identity.brand] ?? identity.brand} ·{" "}
            {CHANNEL_LABELS[identity.channel] ?? identity.channel}
          </p>
        </div>
        <button type="button" onClick={onReset} className="ml-auto text-xs text-muted hover:text-text">
          Trocar cliente
        </button>
      </header>

      {disabled ? (
        <p role="alert" className="m-auto text-sm text-danger">
          O simulador de canal está desligado nesta instalação.
        </p>
      ) : (
        <>
          <p className="border-b border-line px-4 py-2 text-xs text-muted">
            {mode ? STATUS[mode] : "Escreva para começar."}
          </p>
          <div role="log" aria-label="Conversa" className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
            {conversation.data?.messages.map((message) => {
              const mine = message.sender === "customer";
              return (
                <div key={message.seq} className={`flex ${mine ? "justify-end" : "justify-start"}`}>
                  <div className={`max-w-[75%] rounded-lg px-3 py-2 ${mine ? "bg-accent/25" : "bg-elevated"}`}>
                    {!mine && <p className="text-[11px] text-muted">{SENDER[message.sender] ?? message.sender}</p>}
                    <p className="text-sm whitespace-pre-wrap">{message.text}</p>
                    <p className="mt-0.5 text-right text-[10px] text-faint">{timeOfDay(message.created_at)}</p>
                  </div>
                </div>
              );
            })}
            <div ref={end} />
          </div>
          <form onSubmit={submit} className="flex items-end gap-2 border-t border-line p-3">
            <label htmlFor="customer-message" className="sr-only">
              Sua mensagem
            </label>
            <textarea
              id="customer-message"
              rows={2}
              value={text}
              onChange={(event) => setText(event.target.value)}
              placeholder="Escreva sua mensagem…"
              className="flex-1 resize-none rounded-md border border-line bg-surface px-3 py-2 text-sm outline-none placeholder:text-faint focus:border-accent"
            />
            <button
              type="submit"
              disabled={sending || !text.trim()}
              className="h-9 rounded-md bg-accent px-4 text-sm font-medium text-white disabled:opacity-40"
            >
              Enviar
            </button>
          </form>
          {sendError && (
            <p role="alert" className="px-3 pb-3 text-xs text-danger">
              {sendError}
            </p>
          )}
        </>
      )}
    </main>
  );
}
