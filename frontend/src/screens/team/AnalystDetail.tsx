import { useCallback } from "react";
import { fetchAnalystDetail } from "../../lib/api";
import { BRAND_LABELS, categoryLabel, timeOfDay } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { Avatar } from "../../ui/Avatar";
import { LoadingScreen } from "../../ui/LoadingScreen";
import { durationText } from "../dashboard/Dashboard";
import { BarList, DayChart, DetailPage, Message, Section, Stat, plural } from "../detail/parts";

const REFRESH_MS = 15_000;

const duration = (seconds: number | null) => (seconds === null ? "—" : durationText(seconds));
const share = (part: number, total: number) => (total > 0 ? Math.round((part / total) * 100) : 0);

// Detalhe de um analista (ADR 0011): o que ele recebeu, respondeu e resolveu, SLA, assuntos e dias. Só números;
// nunca o texto das conversas dele.
export function AnalystDetail({ token, id }: { token: string; id: string }) {
  const load = useCallback(() => fetchAnalystDetail(token, id), [token, id]);
  const detail = usePolling(load, REFRESH_MS);
  const data = detail.data?.agent.id === id ? detail.data : null;

  if (!data) return detail.error ? <Message>Analista não encontrado.</Message> : <LoadingScreen />;

  const { sla, resolution_time: solution } = data;
  const brands = data.agent.brands.map((brand) => BRAND_LABELS[brand] ?? brand).join(" · ");

  return (
    <DetailPage
      title={data.agent.name}
      subtitle={`${brands || "Sem marcas em comum"} · últimos 7 dias · atualizado às ${timeOfDay(data.generated_at)}`}
      lead={<Avatar name={data.agent.name} className="size-14 rounded-full text-base" />}
    >
      <section aria-label="Indicadores" className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-5">
        <Stat name="Recebidos" value={data.received} detail="tickets escalados para ele" />
        <Stat name="Respondidos" value={data.answered} detail={`${share(data.answered, data.received)}% dos recebidos`} />
        <Stat name="Resolvidos" value={data.resolved} detail="fechados por ele" />
        <Stat name="Em atendimento agora" value={data.open} detail="tickets abertos com ele" />
        <Stat name="Mensagens enviadas" value={data.messages_sent} detail="aos clientes" />
      </section>

      {data.received === 0 && <p className="text-sm text-faint">Sem tickets recebidos nos últimos 7 dias.</p>}

      <div className="grid gap-5 lg:grid-cols-2">
        <Section title="SLA da primeira resposta">
          <p className="mt-3 text-4xl font-semibold tracking-tight tabular">
            {sla.percent === null ? "—" : `${sla.percent}%`}
          </p>
          <p className="mt-1 text-xs text-faint">
            {sla.met} no prazo · {sla.missed} fora do prazo
          </p>
          <p className="mt-5 text-sm text-muted">Tempo médio da primeira resposta</p>
          <p className="mt-1 text-2xl font-semibold tabular">{duration(data.first_reply.mean_seconds)}</p>
          <p className="mt-1 text-xs text-faint">{plural(data.first_reply.answered, "resposta", "respostas")} em 7 dias</p>
        </Section>

        <Section title="Tempo de solução">
          <p className="mt-3 text-4xl font-semibold tracking-tight tabular">{duration(solution.mean_seconds)}</p>
          <p className="mt-1 text-xs text-faint">tempo médio, da abertura ao fechamento</p>
          <p className="mt-5 text-sm text-muted">Mediana</p>
          <p className="mt-1 text-2xl font-semibold tabular">{duration(solution.median_seconds)}</p>
          <p className="mt-1 text-xs text-faint">{plural(solution.resolved, "ticket resolvido", "tickets resolvidos")} em 7 dias</p>
        </Section>
      </div>

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
        <Section title="Marcas atendidas">
          <BarList
            label="Marcas atendidas"
            empty="Nenhuma marca ainda."
            items={data.brands.map((brand) => ({
              key: brand.brand,
              label: BRAND_LABELS[brand.brand] ?? brand.brand,
              value: brand.count,
              display: brand.count,
              color: "var(--color-info)",
            }))}
          />
        </Section>
      </div>

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
    </DetailPage>
  );
}
