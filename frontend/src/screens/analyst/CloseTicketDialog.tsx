import * as Dialog from "@radix-ui/react-dialog";
import { useState, type FormEvent } from "react";
import { RESOLUTION_CODES, type ResolutionCode } from "../../lib/api";
import { RESOLUTION_LABELS } from "../../lib/format";

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
        <button
          type="button"
          className="h-7 rounded-md border border-line px-2.5 text-xs text-text hover:bg-elevated"
        >
          Fechar ticket
        </button>
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/60" />
        <Dialog.Content className="fixed top-1/2 left-1/2 w-[min(28rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 rounded-lg border border-line bg-surface p-5 text-text shadow-2xl">
          <Dialog.Title className="text-sm font-semibold">Fechar ticket</Dialog.Title>
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
                    className={`flex h-9 cursor-pointer items-center gap-2 rounded-md border px-3 text-sm ${
                      code === value ? "border-accent bg-elevated" : "border-line hover:bg-elevated"
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
              <label htmlFor="resolution-note" className="text-xs text-muted">
                Nota (opcional)
              </label>
              <textarea
                id="resolution-note"
                value={note}
                maxLength={NOTE_MAX}
                onChange={(event) => setNote(event.target.value)}
                rows={3}
                className="mt-1 w-full resize-none rounded-md border border-line bg-bg px-3 py-2 text-sm outline-none focus:border-accent"
              />
            </div>

            {error && (
              <p role="alert" className="text-xs text-danger">
                {error}
              </p>
            )}

            <div className="flex justify-end gap-2">
              <Dialog.Close asChild>
                <button type="button" className="h-8 rounded-md px-3 text-sm text-muted hover:text-text">
                  Cancelar
                </button>
              </Dialog.Close>
              <button
                type="submit"
                disabled={!code || busy}
                className="h-8 rounded-md bg-accent px-3 text-sm font-medium text-white disabled:opacity-40"
              >
                Fechar
              </button>
            </div>
          </form>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
