import { ChevronRight } from "lucide-react";
import { useCallback } from "react";
import { fetchTeamDetail } from "../../lib/api";
import { BRAND_LABELS, categoryLabel, timeOfDay } from "../../lib/format";
import { navigate } from "../../lib/useHashRoute";
import { usePolling } from "../../lib/usePolling";
import { Avatar } from "../../ui/Avatar";
import { LoadingScreen } from "../../ui/LoadingScreen";
import { durationText } from "../dashboard/Dashboard";
import { BarList, DayChart, DetailPage, Message, Section, Stat } from "../detail/parts";
import { SlaDial } from "../home/OpsCards";

const REFRESH_MS = 15_000;

const duration = (seconds: number | null) => (seconds === null ? "—" : durationText(seconds));
const share = (part: number, total: number) => (total > 0 ? Math.round((part / total) * 100) : 0);

// Detalhe do card "Desempenho do time" (ADR 0011): o time inteiro, com uma linha por analista. Clicar numa linha
// abre o detalhe do analista. Só números; nunca as conversas.
export function TeamDetail({ token }: { token: string }) {
  const load = useCallback(() => fetchTeamDetail(token), [token]);
  const detail = usePolling(load, REFRESH_MS);
  const data = detail.data;

  if (!data) return detail.error ? <Message>Não foi possível carregar o desempenho do time.</Message> : <LoadingScreen />;

  const { totals } = data;

  return (
    <DetailPage title="Desempenho do time" subtitle={`últimos 7 dias · atualizado às ${timeOfDay(data.generated_at)}`}>
      <section aria-label="Indicadores" className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-6">
        <Stat name="Recebidos" value={totals.received} detail="tickets escalados" />
        <Stat name="Respondidos" value={totals.answered} detail={`${share(totals.answered, totals.received)}% dos recebidos`} />
        <Stat name="Resolvidos" value={totals.resolved} detail="fechados por humanos" />
        <Stat name="Em atendimento agora" value={totals.open} detail="tickets abertos com o time" />
        <Stat name="SLA do time" value={totals.sla_percent === null ? "—" : `${totals.sla_percent}%`} detail="primeira resposta no prazo" />
        <Stat name="Tempo médio da primeira resposta" value={duration(totals.first_reply_mean_seconds)} detail="do escalonamento à resposta" />
      </section>

      <Section title="Analistas" label="Desempenho de cada analista">
        {data.agents.length === 0 ? (
          <p className="mt-4 text-sm text-faint">Nenhum analista nas suas marcas.</p>
        ) : (
          <>
            <div className="overflow-x-auto">
            <table aria-label="Analistas do time" className="mt-2 w-full min-w-[56rem] text-sm">
              <thead>
                <tr className="text-left text-xs text-faint">
                  <th className="py-2 font-normal">Analista</th>
                  <th className="py-2 font-normal">Marcas</th>
                  <th className="py-2 text-right font-normal">Recebidos</th>
                  <th className="py-2 text-right font-normal">Respondidos</th>
                  <th className="py-2 text-right font-normal">Resolvidos</th>
                  <th className="py-2 text-right font-normal">Em atendimento</th>
                  <th className="py-2 pl-6 font-normal">1ª resposta</th>
                  <th className="py-2 font-normal">SLA</th>
                  <th className="py-2 font-normal">Solução</th>
                  <th className="py-2 font-normal">Assunto principal</th>
                  <th className="w-6" />
                </tr>
              </thead>
              <tbody>
                {data.agents.map((agent) => (
                  <tr
                    key={agent.id}
                    onClick={() => navigate(`/analista/${agent.id}`)}
                    className="cursor-pointer border-t border-line/60 transition-colors hover:bg-elevated"
                  >
                    <td className="py-3 pl-1">
                      <a href={`#/analista/${agent.id}`} className="flex items-center gap-2.5 rounded-md hover:text-accent-ink">
                        <Avatar name={agent.name} />
                        <span className="truncate">{agent.name}</span>
                      </a>
                    </td>
                    <td className="py-3 text-muted">{agent.brands.map((brand) => BRAND_LABELS[brand] ?? brand).join(" · ") || "—"}</td>
                    <td className="py-3 text-right tabular">{agent.received}</td>
                    <td className="py-3 text-right tabular">{agent.answered}</td>
                    <td className="py-3 text-right tabular">{agent.resolved}</td>
                    <td className="py-3 text-right tabular">{agent.open}</td>
                    <td className="py-3 pl-6 tabular">{duration(agent.first_reply_mean_seconds)}</td>
                    <td className="py-3">
                      <SlaDial value={agent.sla_percent} />
                    </td>
                    <td className="py-3 tabular">{duration(agent.solution_mean_seconds)}</td>
                    <td className="py-3">{agent.top_subject ? categoryLabel(agent.top_subject) : <span className="text-faint">—</span>}</td>
                    <td className="py-3 text-faint">
                      <ChevronRight aria-hidden className="size-4" strokeWidth={1.8} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            </div>
            <p className="mt-3 text-xs text-faint">Clique num analista para ver os detalhes dele: SLA, assuntos mais tratados e o dia a dia.</p>
          </>
        )}
      </Section>

      <div className="grid gap-5 lg:grid-cols-2">
        <Section title="Assuntos mais tratados">
          <BarList
            label="Assuntos mais tratados"
            empty="Nenhum assunto ainda."
            items={data.subjects.map((subject) => ({
              key: subject.category ?? "none",
              label: categoryLabel(subject.category),
              value: subject.count,
              display: subject.count,
            }))}
          />
        </Section>
        <Section title="Recebidos e resolvidos por dia" label="Série diária">
          <DayChart
            label="Recebidos e resolvidos por dia"
            series={[
              { name: "Recebidos", color: "var(--color-accent)" },
              { name: "Resolvidos", color: "var(--color-info)" },
            ]}
            days={data.daily.map((day) => ({ date: day.date, values: [day.received, day.resolved] }))}
          />
        </Section>
      </div>
    </DetailPage>
  );
}
