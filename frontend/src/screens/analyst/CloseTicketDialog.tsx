import * as Dialog from "@radix-ui/react-dialog";
import { CheckCheck } from "lucide-react";
import { useState, type FormEvent } from "react";
import { RESOLUTION_CODES, type ResolutionCode } from "../../lib/api";
import { RESOLUTION_LABELS } from "../../lib/format";
import { Button } from "../../ui/Button";
import { fieldClass, labelClass } from "../../ui/field";

const NOTE_MAX = 2000;

interface CloseTicketDialogProps {
  onConfirm: (code: ResolutionCode, note: string) => Promise<void>;
}

// Fechar exige a resolução (ADR 0006, M2): o botão só libera com um código escolhido.
export function CloseTicketDialog({ onConfirm }: CloseTicketDialogProps) {
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState<ResolutionCode | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function reset(next: boolean) {
    setOpen(next);
    if (!next) {
      setCode(null);
      setNote("");
      setError(null);
    }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!code) return;
    setBusy(true);
    setError(null);
    try {
      await onConfirm(code, note.trim());
      reset(false);
    } catch {
      setError("Não foi possível fechar. Tente de novo.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog.Root open={open} onOpenChange={reset}>
      <Dialog.Trigger asChild>
        <Button size="sm">
          <CheckCheck aria-hidden className="size-3.5" strokeWidth={2} />
          Fechar ticket
        </Button>
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/70 backdrop-blur-[2px]" />
        <Dialog.Content className="fixed top-1/2 left-1/2 w-[min(28rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 animate-rise rounded-xl border border-line-strong bg-surface p-6 text-text shadow-[0_24px_64px_-12px_rgb(0_0_0/0.7)]">
          <Dialog.Title className="text-base font-semibold tracking-tight">Fechar ticket</Dialog.Title>
          <Dialog.Description className="mt-1 text-xs text-muted">
            Como foi resolvido? A resolução entra na memória do cliente.
          </Dialog.Description>

          <form onSubmit={submit} className="mt-4 space-y-4">
            <fieldset>
              <legend className="sr-only">Resolução</legend>
              <div className="grid grid-cols-2 gap-2">
                {RESOLUTION_CODES.map((value) => (
                  <label
                    key={value}
                    className={`flex h-10 cursor-pointer items-center gap-2.5 rounded-md border px-3 text-sm transition-colors duration-150 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-accent ${
                      code === value ? "border-accent bg-accent/8 text-text" : "border-line-strong text-muted hover:bg-elevated hover:text-text"
                    }`}
                  >
                    <input
                      type="radio"
                      name="resolution"
                      value={value}
                      checked={code === value}
                      onChange={() => setCode(value)}
                      className="accent-accent"
                    />
                    {RESOLUTION_LABELS[value]}
                  </label>
                ))}
              </div>
            </fieldset>

            <div>
              <label htmlFor="resolution-note" className={labelClass}>
                Nota (opcional)
              </label>
              <textarea
                id="resolution-note"
                value={note}
                maxLength={NOTE_MAX}
                onChange={(event) => setNote(event.target.value)}
                rows={3}
                className={`${fieldClass} mt-1.5 resize-none bg-bg py-2`}
              />
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
              <Button type="submit" variant="primary" disabled={!code} busy={busy}>
                Fechar
              </Button>
            </div>
          </form>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
