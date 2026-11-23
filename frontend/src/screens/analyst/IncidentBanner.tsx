import * as Dialog from "@radix-ui/react-dialog";
import { Sparkles, TriangleAlert } from "lucide-react";
import { useCallback, useState, type FormEvent } from "react";
import {
  fetchIncidents,
  RESOLUTION_CODES,
  resolveIncident,
  type Incident,
  type IncidentResolution,
  type ResolutionCode,
} from "../../lib/api";
import { BRAND_LABELS, RESOLUTION_LABELS } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { Button } from "../../ui/Button";
import { fieldClass, labelClass } from "../../ui/field";

const REFRESH_MS = 5_000;

function minutesSince(iso: string): string {
  const minutes = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60_000));
  return minutes === 0 ? "agora" : `há ${minutes} min`;
}

function describe(result: IncidentResolution): string {
  const closed = `${result.closed} ${result.closed === 1 ? "ticket fechado" : "tickets fechados"}`;
  const skipped = result.skipped.length;
  return skipped > 0 ? `${closed} · ${skipped} com outro analista` : closed;
}

// Modo Incidente no painel do analista (ADR 0009, W1): o pico aparece no topo e se resolve de uma vez.
export function IncidentBanner({ token, onResolved }: { token: string; onResolved?: () => void }) {
  const load = useCallback(() => fetchIncidents(token), [token]);
  const incidents = usePolling(load, REFRESH_MS);
  const [notice, setNotice] = useState<string | null>(null);
  const open = incidents.data?.incidents ?? [];

  if (open.length === 0 && !notice) return null;

  return (
    <div className="border-b border-incident/30 bg-incident/6">
      {open.map((incident) => (
        <section
          key={incident.id}
          aria-label="Incidente aberto"
          className="flex animate-rise items-center gap-4 px-5 py-3"
        >
          <span aria-hidden className="relative flex size-8 shrink-0 items-center justify-center rounded-md bg-incident/15">
            <span className="absolute inset-0 rounded-md ring-1 ring-incident/50 motion-safe:animate-ping" />
            <TriangleAlert className="size-4 text-incident-text" strokeWidth={2} />
          </span>
          <div className="min-w-0 flex-1">
            <p className="flex items-center gap-2 text-xs font-medium text-incident-text">
              Incidente · {BRAND_LABELS[incident.brand] ?? incident.brand} · {incident.label}
              {incident.title_source !== "template" && (
                <span className="flex items-center gap-1 text-faint">
                  · <Sparkles aria-hidden className="size-3" strokeWidth={2} /> título pela IA
                </span>
              )}
            </p>
            <p className="mt-0.5 truncate text-sm font-semibold text-text">{incident.title}</p>
          </div>
          <p className="shrink-0 text-xs text-muted tabular">
            {incident.open_tickets} tickets · {minutesSince(incident.opened_at)}
          </p>
          <ResolveDialog
            token={token}
            incident={incident}
            onDone={(message) => {
              setNotice(message);
              void incidents.reload();
              onResolved?.();
            }}
          />
        </section>
      ))}
      {notice && (
        <p role="status" className="px-5 py-2 text-xs font-medium text-success">
          {notice}
        </p>
      )}
    </div>
  );
}

function ResolveDialog({
  token,
  incident,
  onDone,
}: {
  token: string;
  incident: Incident;
  onDone: (message: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [text, setText] = useState(incident.draft_reply);
  const [code, setCode] = useState<ResolutionCode>("resolved");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function toggle(next: boolean) {
    setOpen(next);
    if (next) {
      setText(incident.draft_reply);
      setCode("resolved");
      setError(null);
    }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!text.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const result = await resolveIncident(token, incident.id, text.trim(), code);
      setOpen(false);
      onDone(describe(result));
    } catch {
      setError("Não foi possível fechar os tickets do incidente. Tente de novo.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog.Root open={open} onOpenChange={toggle}>
      <Dialog.Trigger asChild>
        <Button variant="primary" size="sm">
          Responder a todos
        </Button>
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/40 backdrop-blur-[2px]" />
        <Dialog.Content className="fixed top-1/2 left-1/2 w-[min(34rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 animate-rise rounded-xl border border-line-strong bg-surface p-6 text-text shadow-[0_24px_64px_-12px_rgb(16_24_40/0.25)]">
          <Dialog.Title className="text-base font-semibold tracking-tight">Responder a todos</Dialog.Title>
          <Dialog.Description className="mt-1.5 text-xs leading-relaxed text-muted">
            {incident.title}. A mesma resposta vai para os {incident.open_tickets} clientes; os tickets com a IA ou
            na fila passam para você e fecham com a resolução. Tickets com outro analista ficam de fora.
          </Dialog.Description>

          <form onSubmit={submit} className="mt-5 space-y-4">
            <div>
              <label htmlFor={`incident-reply-${incident.id}`} className={labelClass}>
                Resposta para os {incident.open_tickets} clientes
              </label>
              <textarea
                id={`incident-reply-${incident.id}`}
                value={text}
                maxLength={2000}
                onChange={(event) => setText(event.target.value)}
                rows={5}
                className={`${fieldClass} mt-1.5 resize-none bg-bg py-2.5 leading-relaxed`}
              />
              {incident.title_source !== "template" && (
                <p className="mt-1.5 text-[11px] font-medium text-accent">Rascunho gerado por IA · {incident.model}</p>
              )}
            </div>
            <div>
              <label htmlFor={`incident-code-${incident.id}`} className={labelClass}>
                Resolução
              </label>
              <select
                id={`incident-code-${incident.id}`}
                value={code}
                onChange={(event) => setCode(event.target.value as ResolutionCode)}
                className={`${fieldClass} mt-1.5 h-9 bg-bg`}
              >
                {RESOLUTION_CODES.map((value) => (
                  <option key={value} value={value}>
                    {RESOLUTION_LABELS[value]}
                  </option>
                ))}
              </select>
            </div>

            {error && (
              <p role="alert" className="text-xs text-danger">
                {error}
              </p>
            )}

            <div className="flex justify-end gap-2">
              <Dialog.Close asChild>
                <Button variant="ghost">Cancelar</Button>
              </Dialog.Close>
              <Button type="submit" variant="primary" busy={busy} disabled={!text.trim()}>
                Responder e fechar
              </Button>
            </div>
          </form>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
