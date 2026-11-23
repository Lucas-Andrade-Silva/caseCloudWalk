import { RefreshCw, Send, Zap } from "lucide-react";
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
import { BrandDot } from "../../ui/BrandDot";
import { BrandMark } from "../../ui/BrandMark";
import { Button } from "../../ui/Button";
import { fieldClass, labelClass } from "../../ui/field";

const REFRESH_MS = 2_000;

const STATUS: Record<NonNullable<CustomerConversation["mode"]>, string> = {
  ai: "Atendimento automático",
  pending_human: "Aguardando uma pessoa da equipe",
  human: "Em atendimento com uma pessoa da equipe",
  closed: "Atendimento encerrado. Mande uma mensagem para abrir outro.",
};

const SENDER: Record<string, string> = { bot: "Assistente", analyst: "Equipe" };

// Pico para demonstrar o Modo Incidente (ADR 0009): clientes sintéticos com a mesma reclamação ao mesmo tempo.
const BURST_SIZE = 6;
const BURST_TEXT: Record<string, string> = {
  infinitepay: "minha maquininha não liga",
  jim: "my card reader won't turn on",
};

const STATUS_DOT: Record<NonNullable<CustomerConversation["mode"]>, string> = {
  ai: "bg-accent",
  pending_human: "bg-warning motion-safe:animate-pulse",
  human: "bg-accent",
  closed: "bg-faint",
};

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

  const field = `${fieldClass} mt-1.5 h-10`;
  const [bursting, setBursting] = useState(false);
  const [burstNotice, setBurstNotice] = useState<{ tone: "ok" | "error"; text: string } | null>(null);

  async function burst() {
    setBursting(true);
    setBurstNotice(null);
    const text = BURST_TEXT[brand] ?? BURST_TEXT.infinitepay!;
    const results = await Promise.allSettled(
      Array.from({ length: BURST_SIZE }, (_, index) =>
        sendCustomerMessage({ brand, channel, name: `Cliente sintético ${index + 1}`, external_id: newExternalId() }, text),
      ),
    );
    const sent = results.filter((result) => result.status === "fulfilled").length;
    setBurstNotice(
      sent > 0
        ? { tone: "ok", text: `${sent} clientes enviaram “${text}”. Veja o incidente no painel e no mapa.` }
        : { tone: "error", text: "O pico não foi enviado. O simulador está ligado?" },
    );
    setBursting(false);
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-bg px-4 text-text">
      <form onSubmit={submit} className="w-full max-w-sm animate-rise space-y-5">
        <div>
          <BrandMark size="lg" />
          <h1 className="mt-8 text-2xl font-semibold tracking-tight">Falar com o atendimento</h1>
          <p className="mt-1.5 text-sm text-muted">Canal simulado: você faz o papel do cliente. Os dados são sintéticos.</p>
        </div>
        <div>
          <label htmlFor="brand" className={labelClass}>
            Marca
          </label>
          <select id="brand" value={brand} onChange={(event) => setBrand(event.target.value)} className={field}>
            <option value="infinitepay">InfinitePay</option>
            <option value="jim">JIM</option>
          </select>
        </div>
        <div>
          <label htmlFor="channel" className={labelClass}>
            Canal
          </label>
          <select id="channel" value={channel} onChange={(event) => setChannel(event.target.value)} className={field}>
            <option value="app_chat">App</option>
            <option value="whatsapp">WhatsApp</option>
            <option value="email">E-mail</option>
          </select>
        </div>
        <div>
          <label htmlFor="name" className={labelClass}>
            Seu nome
          </label>
          <input id="name" value={name} onChange={(event) => setName(event.target.value)} className={field} />
        </div>
        <Button type="submit" variant="primary" disabled={!name.trim()} className="h-10 w-full">
          Começar conversa
        </Button>

        <div className="border-t border-line pt-5">
          <Button onClick={() => void burst()} busy={bursting} className="h-10 w-full">
            <Zap aria-hidden className="size-3.5 text-warning" strokeWidth={2} />
            Simular pico
          </Button>
          <p className="mt-2 text-xs leading-relaxed text-faint">
            {BURST_SIZE} clientes sintéticos da marca escolhida mandam a mesma reclamação de uma vez.
          </p>
          {burstNotice && (
            <p
              role={burstNotice.tone === "ok" ? "status" : "alert"}
              className={`mt-2 text-xs ${burstNotice.tone === "ok" ? "text-success" : "text-danger"}`}
            >
              {burstNotice.text}
            </p>
          )}
        </div>
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
    <main className="flex h-screen justify-center bg-bg text-text">
      <div className="flex w-full max-w-xl flex-col border-x border-line">
        <header className="flex min-h-14 items-center gap-3 border-b border-line px-5 py-2.5">
          <div className="min-w-0">
            <h1 className="flex items-center gap-2 text-[15px] font-semibold tracking-tight">
              <BrandDot brand={identity.brand} />
              Atendimento {BRAND_LABELS[identity.brand] ?? identity.brand}
            </h1>
            <p className="mt-0.5 truncate font-mono text-[11px] text-faint">
              {identity.name} · {BRAND_LABELS[identity.brand] ?? identity.brand} ·{" "}
              {CHANNEL_LABELS[identity.channel] ?? identity.channel}
            </p>
          </div>
          <Button variant="ghost" size="sm" onClick={onReset} className="ml-auto">
            <RefreshCw aria-hidden className="size-3.5" strokeWidth={2} />
            Trocar cliente
          </Button>
        </header>

        {disabled ? (
          <p role="alert" className="m-auto text-sm text-danger">
            O simulador de canal está desligado nesta instalação.
          </p>
        ) : (
          <>
            <p className="flex items-center gap-2 border-b border-line px-5 py-2 text-xs text-muted">
              <span aria-hidden className={`size-1.5 rounded-full ${mode ? STATUS_DOT[mode] : "bg-faint"}`} />
              {mode ? STATUS[mode] : "Escreva para começar."}
            </p>
            <div role="log" aria-label="Conversa" className="flex-1 space-y-3 overflow-y-auto px-5 py-5">
              {conversation.data?.messages.map((message) => {
                const mine = message.sender === "customer";
                return (
                  <div key={message.seq} className={`flex animate-rise ${mine ? "justify-end" : "justify-start"}`}>
                    <div
                      className={`max-w-[78%] rounded-2xl px-3.5 py-2 ${
                        mine ? "rounded-br-md bg-accent text-on-accent" : "rounded-bl-md bg-elevated text-text"
                      }`}
                    >
                      {!mine && <p className="font-mono text-[11px] text-faint">{SENDER[message.sender] ?? message.sender}</p>}
                      <p className="text-sm leading-relaxed whitespace-pre-wrap">{message.text}</p>
                      <p className={`mt-0.5 text-right font-mono text-[10px] tabular ${mine ? "text-on-accent/75" : "text-faint"}`}>
                        {timeOfDay(message.created_at)}
                      </p>
                    </div>
                  </div>
                );
              })}
              <div ref={end} />
            </div>
            <form onSubmit={submit} className="flex items-end gap-2 border-t border-line px-5 py-4">
              <label htmlFor="customer-message" className="sr-only">
                Sua mensagem
              </label>
              <textarea
                id="customer-message"
                rows={2}
                value={text}
                onChange={(event) => setText(event.target.value)}
                placeholder="Escreva sua mensagem…"
                className={`${fieldClass} flex-1 resize-none py-2`}
              />
              <Button type="submit" variant="primary" busy={sending} disabled={!text.trim()} className="h-[3.25rem]">
                <Send aria-hidden className="size-3.5" strokeWidth={2} />
                Enviar
              </Button>
            </form>
            {sendError && (
              <p role="alert" className="px-5 pb-4 text-xs text-danger">
                {sendError}
              </p>
            )}
          </>
        )}
      </div>
    </main>
  );
}
