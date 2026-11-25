import type { DashboardMetrics } from "../../lib/api";
import { navigate } from "../../lib/useHashRoute";
import { Avatar } from "../../ui/Avatar";

// Cards da tela inicial que olham para pessoas e tickets (ADR 0010): tempo de solução, desempenho do time e
// operação dos tickets. Só números que a plataforma registra; sem CSAT, a qualidade é o SLA da primeira resposta.

export const SOLUTION_TARGET_SECONDS = 8 * 3600;

export const PRIORITY: Record<string, { label: string; color: string }> = {
  p1: { label: "Urgente", color: "var(--color-danger)" },
  p2: { label: "Alta", color: "var(--color-warning)" },
  p3: { label: "Média", color: "var(--color-info)" },
  p4: { label: "Baixa", color: "var(--color-faint)" },
};

/** "33h32m", "5min", "40s": número grande e unidade pequena, como no resto da home. */
export function Duration({ seconds, className = "" }: { seconds: number | null; className?: string }) {
  if (seconds === null) return <span className={className}>—</span>;
  const unit = (text: string) => <span className="ml-0.5 text-[0.55em] font-medium text-muted">{text}</span>;
  if (seconds < 60) return <span className={`tabular ${className}`}>{seconds}{unit("s")}</span>;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return <span className={`tabular ${className}`}>{minutes}{unit("min")}</span>;
  const hours = Math.floor(minutes / 60);
  return (
    <span className={`tabular ${className}`}>
      {hours}{unit("h")}
      {minutes % 60 > 0 && <span className="ml-1">{minutes % 60}{unit("m")}</span>}
    </span>
  );
}

export function SolutionTime({ data }: { data: DashboardMetrics }) {
  const { resolution_time: time } = data;
  // A barra vai de 0 a 2× a meta: verde até a meta, amarelo até 1,5×, vermelho depois.
  const position = time.median_seconds === null ? 0 : Math.min(time.median_seconds / (2 * SOLUTION_TARGET_SECONDS), 1);
  return (
    <>
      <div className="mt-4 flex items-baseline justify-between gap-3">
        <Duration seconds={time.median_seconds} className="text-4xl font-semibold tracking-tight" />
        <span className="text-sm text-muted">Meta 8h</span>
      </div>
      <div aria-hidden className="relative mt-4 h-1.5">
        <span className="absolute inset-0 flex gap-[3px] overflow-hidden rounded-full">
          <span className="h-full w-1/2 bg-accent" />
          <span className="h-full w-1/4 bg-risk" />
          <span className="h-full w-1/4 bg-danger" />
        </span>
        <span
          className="absolute top-1/2 size-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-surface bg-text shadow transition-[left] duration-700"
          style={{ left: `${position * 100}%` }}
        />
      </div>
      <div className="mt-auto grid grid-cols-2 gap-3 pt-5">
        <div>
          <Duration seconds={time.ai_median_seconds} className="text-xl font-semibold" />
          <p className="text-xs text-muted">Pela IA</p>
        </div>
        <div className="text-right">
          <Duration seconds={time.human_median_seconds} className="text-xl font-semibold" />
          <p className="text-xs text-muted">Por humano</p>
        </div>
      </div>
    </>
  );
}

/** Barra de tracinhos, como no anexo: cada tracinho vale uma fração do maior número do time. */
function Ticks({ value, max }: { value: number; max: number }) {
  const lit = max > 0 ? Math.round((value / max) * 14) : 0;
  return (
    <span aria-hidden className="flex gap-[2px]">
      {Array.from({ length: 14 }, (_, index) => (
        <span key={index} className={`h-3.5 w-[3px] rounded-full ${index < lit ? "bg-accent" : "bg-line-strong"}`} />
      ))}
    </span>
  );
}

export function SlaDial({ value }: { value: number | null }) {
  if (value === null) return <span className="text-faint">—</span>;
  const color = value >= 80 ? "var(--color-accent)" : value >= 60 ? "var(--color-warning)" : "var(--color-danger)";
  const length = 2 * Math.PI * 6;
  return (
    <span className="inline-flex items-center gap-2 tabular">
      <svg aria-hidden viewBox="0 0 16 16" className="size-4 -rotate-90">
        <circle cx="8" cy="8" r="6" fill="none" stroke="var(--color-line-strong)" strokeWidth="2.2" />
        <circle cx="8" cy="8" r="6" fill="none" stroke={color} strokeWidth="2.2" strokeDasharray={`${(value / 100) * length} ${length}`} />
      </svg>
      {value}%
    </span>
  );
}

const replyTone = (seconds: number | null) =>
  seconds === null ? "text-faint" : seconds > 4 * 3600 ? "text-danger-ink" : seconds > 3600 ? "text-warning-ink" : "text-text";

export function TeamPerformance({ data }: { data: DashboardMetrics }) {
  const { team } = data;
  const max = Math.max(...team.agents.map((agent) => agent.resolved), 1);
  const slaTotal = data.sla.met + data.sla.missed;
  return (
    <>
      <div className="mt-4 flex items-end justify-between border-b border-line pb-4">
        <div>
          <p className="flex items-center gap-1.5 text-xs text-muted">
            <span aria-hidden className="size-1.5 rounded-full bg-accent" /> Em atendimento agora
          </p>
          <p className="mt-1 text-3xl font-semibold tabular">
            {team.active}
            <span className="text-base font-normal text-muted">/{team.total}</span>
          </p>
        </div>
        <div className="text-right">
          <p className="text-xs text-muted">SLA do time</p>
          <p className="mt-1 text-3xl font-semibold tabular">
            {slaTotal > 0 ? Math.round((data.sla.met / slaTotal) * 100) : "—"}
            {slaTotal > 0 && <span className="text-base font-normal text-muted">%</span>}
          </p>
        </div>
      </div>
      {team.agents.length === 0 ? (
        <p className="mt-4 text-sm text-faint">Nenhum analista nas suas marcas.</p>
      ) : (
        <table aria-label="Desempenho por analista" className="mt-2 w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-faint">
              <th className="py-2 font-normal">Analista</th>
              <th className="py-2 font-normal">Resolvidos</th>
              <th className="py-2 font-normal">Resposta</th>
              <th className="py-2 text-right font-normal">SLA</th>
            </tr>
          </thead>
          <tbody>
            {team.agents.slice(0, 6).map((agent) => (
              // A linha fica acima do link do card (z-20 contra z-10) e abre o detalhe do analista (ADR 0011).
              <tr
                key={agent.id}
                onClick={() => navigate(`/analista/${agent.id}`)}
                className="relative z-20 cursor-pointer border-t border-line/60 transition-colors hover:bg-elevated"
              >
                <td className="py-2.5 pl-1">
                  <a href={`#/analista/${agent.id}`} className="flex items-center gap-2.5 rounded-md hover:text-accent-ink">
                    <Avatar name={agent.name} />
                    <span className="truncate">{agent.name}</span>
                  </a>
                </td>
                <td className="py-2.5">
                  <span className="flex items-center gap-2.5">
                    <Ticks value={agent.resolved} max={max} />
                    <span className="tabular">{agent.resolved}</span>
                  </span>
                </td>
                <td className={`py-2.5 ${replyTone(agent.reply_median_seconds)}`}>
                  <Duration seconds={agent.reply_median_seconds} />
                </td>
                <td className="py-2.5 text-right">
                  <SlaDial value={agent.sla_percent} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <p className="mt-auto pt-3 text-xs text-faint">Clique num analista para ver os detalhes dele.</p>
    </>
  );
}

function Exception({ label, detail, value, color }: { label: string; detail: string; value: number; color: string }) {
  return (
    <div role="group" aria-label={label} className="flex items-center gap-3 rounded-xl bg-elevated px-4 py-3">
      <span aria-hidden className="size-2.5 shrink-0 rounded-sm" style={{ background: color }} />
      <span className="min-w-0 flex-1">
        <span className="block text-sm">{label}</span>
        <span className="block text-xs text-faint">{detail}</span>
      </span>
      <span className="text-3xl font-semibold tabular">{value}</span>
    </div>
  );
}

export function TicketOperations({ data }: { data: DashboardMetrics }) {
  const { operations } = data;
  return (
    <>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Exception label="Tickets parados" detail="Abertos há mais de 3 dias" value={operations.stale} color="var(--color-warning)" />
        <Exception label="Sem analista" detail="Esperando humano, ninguém pegou" value={operations.unassigned} color="var(--color-danger)" />
      </div>
      {operations.tickets.length === 0 ? (
        <p className="mt-4 text-sm text-faint">Nenhum ticket pedindo gente agora.</p>
      ) : (
        <table aria-label="Tickets que pedem gente" className="mt-2 w-full table-fixed text-sm">
          <thead>
            <tr className="text-left text-xs text-faint">
              <th className="w-24 py-2 font-normal">Ticket</th>
              <th className="w-32 py-2 font-normal">Analista</th>
              <th className="py-2 font-normal">Assunto</th>
              <th className="w-24 py-2 font-normal">Prioridade</th>
            </tr>
          </thead>
          <tbody>
            {operations.tickets.map((ticket) => {
              const priority = PRIORITY[ticket.priority] ?? PRIORITY.p3!;
              return (
                <tr key={ticket.id} className="border-t border-line/60">
                  <td className="py-2.5 font-mono text-xs text-muted">#{ticket.id.slice(0, 6).toUpperCase()}</td>
                  <td className="py-2.5">
                    {ticket.agent && ticket.agent_id ? (
                      <a href={`#/analista/${ticket.agent_id}`} className="relative z-20 flex items-center gap-2 rounded-md hover:text-accent-ink">
                        <Avatar name={ticket.agent} />
                        <span className="truncate">{ticket.agent}</span>
                      </a>
                    ) : (
                      <span className="text-faint">—</span>
                    )}
                  </td>
                  <td className="truncate py-2.5 pr-3" title={ticket.subject}>
                    {ticket.subject || "Sem mensagem"}
                  </td>
                  <td className="py-2.5">
                    <span className="flex items-center gap-1.5">
                      <span aria-hidden className="size-2 rounded-sm" style={{ background: priority.color }} />
                      {priority.label}
                    </span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </>
  );
}
