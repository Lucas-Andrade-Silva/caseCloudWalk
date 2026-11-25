import { useCallback } from "react";
import { fetchTicketsDetail } from "../../lib/api";
import { BRAND_LABELS, categoryLabel, dueLabel, timeOfDay, TONE_CLASSES } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { Avatar } from "../../ui/Avatar";
import { LoadingScreen } from "../../ui/LoadingScreen";
import { durationText } from "../dashboard/Dashboard";
import { BarList, DetailPage, Message, Section, Stat } from "../detail/parts";
import { PRIORITY } from "../home/OpsCards";

const REFRESH_MS = 10_000;

const MODE_LABELS: Record<string, string> = { ai: "Com a IA", pending_human: "Esperando humano", human: "Com humano" };
const days = (seconds: number) => {
  const count = Math.floor(seconds / 86_400);
  return `${count} ${count === 1 ? "dia" : "dias"}`;
};

function Priority({ priority }: { priority: string }) {
  const item = PRIORITY[priority] ?? PRIORITY.p3!;
  return (
    <span className="flex items-center gap-1.5">
      <span aria-hidden className="size-2 rounded-sm" style={{ background: item.color }} />
      {item.label}
    </span>
  );
}

function Agent({ name, id }: { name: string | null; id: string | null }) {
  if (!name || !id) return <span className="text-faint">—</span>;
  return (
    <a href={`#/analista/${id}`} className="flex items-center gap-2 rounded-md hover:text-accent-ink">
      <Avatar name={name} />
      <span className="truncate">{name}</span>
    </a>
  );
}

// Detalhe do card "Operação dos tickets" (ADR 0011): tudo o que pede gente agora, com prioridade, quem está com o
// ticket, há quanto tempo espera e o prazo da primeira resposta; e o que está parado há mais de 3 dias.
export function TicketsDetail({ token }: { token: string }) {
  const load = useCallback(() => fetchTicketsDetail(token), [token]);
  const detail = usePolling(load, REFRESH_MS);
  const data = detail.data;

  if (!data) return detail.error ? <Message>Não foi possível carregar os tickets.</Message> : <LoadingScreen />;

  const { counts } = data;

  return (
    <DetailPage title="Operação dos tickets" subtitle={`o que pede gente agora · atualizado às ${timeOfDay(data.generated_at)}`}>
      <section aria-label="Indicadores" className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <Stat name="Pedem gente" value={counts.attention} detail="esperando humano ou com humano" />
        <Stat name="Sem analista" value={counts.unassigned} detail="esperando humano, ninguém pegou" tone={counts.unassigned > 0 ? "text-danger-ink" : "text-text"} />
        <Stat name="Fora do prazo" value={counts.overdue} detail="primeira resposta atrasada" tone={counts.overdue > 0 ? "text-danger-ink" : "text-text"} />
        <Stat name="Parados" value={counts.stale} detail="abertos há mais de 3 dias" tone={counts.stale > 0 ? "text-warning-ink" : "text-text"} />
      </section>

      <div className="grid gap-5 lg:grid-cols-2">
        <Section title="Por prioridade">
          <BarList
            label="Tickets por prioridade"
            items={(["p1", "p2", "p3", "p4"] as const).map((priority) => ({
              key: priority,
              label: PRIORITY[priority]!.label,
              value: counts.by_priority[priority],
              display: counts.by_priority[priority],
              color: PRIORITY[priority]!.color,
            }))}
          />
        </Section>
        <Section title="Por marca">
          <BarList
            label="Tickets por marca"
            empty="Nenhum ticket pedindo gente."
            items={counts.by_brand.map((brand) => ({
              key: brand.brand,
              label: BRAND_LABELS[brand.brand] ?? brand.brand,
              value: brand.count,
              display: brand.count,
              color: "var(--color-info)",
            }))}
          />
        </Section>
      </div>

      <Section title="Tickets que pedem gente" label="Tickets pedindo gente">
        {data.tickets.length === 0 ? (
          <p className="mt-4 text-sm text-faint">Nenhum ticket pedindo gente agora.</p>
        ) : (
          <table aria-label="Tickets que pedem gente" className="mt-2 w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-faint">
                <th className="py-2 font-normal">Ticket</th>
                <th className="py-2 font-normal">Marca</th>
                <th className="py-2 font-normal">Assunto</th>
                <th className="py-2 font-normal">Prioridade</th>
                <th className="py-2 font-normal">Situação</th>
                <th className="py-2 font-normal">Analista</th>
                <th className="py-2 font-normal">Espera</th>
                <th className="py-2 font-normal">Prazo</th>
              </tr>
            </thead>
            <tbody>
              {data.tickets.map((ticket) => {
                const due = dueLabel(ticket.first_response_due_at, ticket.first_human_response_at);
                return (
                  <tr key={ticket.id} className="border-t border-line/60">
                    <td className="py-2.5 font-mono text-xs text-muted">#{ticket.id.slice(0, 6).toUpperCase()}</td>
                    <td className="py-2.5">{BRAND_LABELS[ticket.brand] ?? ticket.brand}</td>
                    <td className="max-w-72 py-2.5 pr-3">
                      <span className="block truncate" title={ticket.subject}>
                        {ticket.subject || "Sem mensagem"}
                      </span>
                      {ticket.category && <span className="text-xs text-faint">{categoryLabel(ticket.category)}</span>}
                    </td>
                    <td className="py-2.5">
                      <Priority priority={ticket.priority} />
                    </td>
                    <td className="py-2.5">{MODE_LABELS[ticket.mode] ?? ticket.mode}</td>
                    <td className="py-2.5">
                      <Agent name={ticket.agent} id={ticket.agent_id} />
                    </td>
                    <td className="py-2.5 tabular">{ticket.waiting_seconds === null ? "—" : durationText(ticket.waiting_seconds)}</td>
                    <td className={`py-2.5 ${TONE_CLASSES[due.tone]}`}>{due.text}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </Section>

      <Section title="Parados há mais de 3 dias" label="Tickets parados">
        {data.stale_tickets.length === 0 ? (
          <p className="mt-4 text-sm text-faint">Nenhum ticket parado há mais de 3 dias.</p>
        ) : (
          <table aria-label="Tickets parados há mais de 3 dias" className="mt-2 w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-faint">
                <th className="py-2 font-normal">Ticket</th>
                <th className="py-2 font-normal">Marca</th>
                <th className="py-2 font-normal">Assunto</th>
                <th className="py-2 font-normal">Prioridade</th>
                <th className="py-2 font-normal">Situação</th>
                <th className="py-2 font-normal">Analista</th>
                <th className="py-2 font-normal">Aberto há</th>
              </tr>
            </thead>
            <tbody>
              {data.stale_tickets.map((ticket) => (
                <tr key={ticket.id} className="border-t border-line/60">
                  <td className="py-2.5 font-mono text-xs text-muted">#{ticket.id.slice(0, 6).toUpperCase()}</td>
                  <td className="py-2.5">{BRAND_LABELS[ticket.brand] ?? ticket.brand}</td>
                  <td className="max-w-72 truncate py-2.5 pr-3" title={ticket.subject}>
                    {ticket.subject || "Sem mensagem"}
                  </td>
                  <td className="py-2.5">
                    <Priority priority={ticket.priority} />
                  </td>
                  <td className="py-2.5">{MODE_LABELS[ticket.mode] ?? ticket.mode}</td>
                  <td className="py-2.5">
                    <Agent name={ticket.agent} id={ticket.agent_id} />
                  </td>
                  <td className="py-2.5 font-medium tabular">{days(ticket.age_seconds)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Section>
    </DetailPage>
  );
}
