import { Inbox } from "lucide-react";
import { useCallback, useMemo, useState } from "react";
import {
  closeTicket,
  fetchTicket,
  fetchWork,
  sendMessage,
  takeNext,
  type ResolutionCode,
} from "../../lib/api";
import { navigate, useHashRoute } from "../../lib/useHashRoute";
import { usePolling } from "../../lib/usePolling";
import { Button } from "../../ui/Button";
import { ContextPanel } from "./ContextPanel";
import { Conversation } from "./Conversation";
import { IncidentBanner } from "./IncidentBanner";
import { TicketList } from "./TicketList";

const WORK_REFRESH_MS = 5_000;
const TICKET_REFRESH_MS = 3_000;

// Painel do analista: o que é dele, o que espera nas filas dele, a conversa aberta e o contexto
// (brief do handoff e memória do cliente). Quem escolhe o próximo é a plataforma (ADR 0004, H4).
export function AnalystWorkspace({ token }: { token: string }) {
  const route = useHashRoute();
  const selectedId = /^\/fila\/(.+)$/.exec(route)?.[1] ?? null;
  const [notice, setNotice] = useState<string | null>(null);
  const [taking, setTaking] = useState(false);

  const loadWork = useCallback(() => fetchWork(token), [token]);
  const work = usePolling(loadWork, WORK_REFRESH_MS);

  const loadTicket = useMemo(
    () => (selectedId ? () => fetchTicket(token, selectedId) : null),
    [token, selectedId],
  );
  const ticket = usePolling(loadTicket, TICKET_REFRESH_MS);
  const current = ticket.data && ticket.data.id === selectedId ? ticket.data : null;

  async function pickNext() {
    setTaking(true);
    setNotice(null);
    try {
      const next = await takeNext(token);
      if (next) navigate(`/fila/${next.id}`);
      else setNotice("Nada esperando nas suas filas.");
      await work.reload();
    } catch {
      setNotice("Não foi possível pegar o próximo. Tente de novo.");
    } finally {
      setTaking(false);
    }
  }

  async function send(text: string) {
    if (!selectedId) return;
    await sendMessage(token, selectedId, text);
    await Promise.all([ticket.reload(), work.reload()]);
  }

  async function close(code: ResolutionCode, note: string) {
    if (!selectedId) return;
    await closeTicket(token, selectedId, code, note);
    navigate("/fila");
    await work.reload();
  }

  const waitingCount = work.data?.waiting_count ?? 0;

  return (
    <div className="flex h-screen min-w-0 flex-1 flex-col">
      <IncidentBanner token={token} onResolved={() => void work.reload()} />
      <div className="flex min-h-0 min-w-0 flex-1">
        <aside className="flex w-80 shrink-0 flex-col border-r border-line bg-bg">
          <div className="border-b border-line p-3">
            <Button variant="primary" onClick={pickNext} busy={taking} className="w-full">
              Pegar o próximo
            </Button>
            {notice && (
              <p role="status" className="mt-2 text-xs text-muted">
                {notice}
              </p>
            )}
          </div>
          <div className="flex-1 overflow-y-auto">
            {work.data ? (
              <>
                <TicketList
                  label="Com você"
                  empty="Nenhum ticket com você."
                  items={work.data.mine}
                  selectedId={selectedId}
                  onSelect={(id) => navigate(`/fila/${id}`)}
                />
                <TicketList
                  label="Esperando nas suas filas"
                  empty="Fila vazia."
                  items={work.data.waiting}
                  selectedId={selectedId}
                  extra={waitingCount > 0 ? String(waitingCount) : undefined}
                />
              </>
            ) : (
              <p className="p-4 text-xs text-faint">{work.error ? "Não foi possível carregar a fila." : "Carregando…"}</p>
            )}
          </div>
        </aside>

        {current ? (
          <>
            <Conversation ticket={current} onSend={send} onClose={close} />
            <aside className="w-80 shrink-0 overflow-y-auto border-l border-line bg-bg">
              <ContextPanel ticket={current} />
            </aside>
          </>
        ) : (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 text-center">
            <Inbox aria-hidden className="size-6 text-faint" strokeWidth={1.5} />
            <p className="max-w-xs text-sm text-muted">
              {selectedId ? "Carregando a conversa…" : "Pegue o próximo ticket ou escolha um dos seus."}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
