import { useCallback } from "react";
import { fetchResolutionDetail, type ResolutionDetailData } from "../../lib/api";
import { BRAND_LABELS, categoryLabel, timeOfDay } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { LoadingScreen } from "../../ui/LoadingScreen";
import { durationText } from "../dashboard/Dashboard";
import { BarList, DayChart, DetailPage, Message, Section, Stat, plural } from "../detail/parts";

const REFRESH_MS = 15_000;

const duration = (seconds: number | null) => (seconds === null ? "—" : durationText(seconds));

const BUCKET_LABELS: Record<ResolutionDetailData["buckets"][number]["key"], string> = {
  up_to_15m: "Até 15 min",
  "15m_to_1h": "15 min a 1 h",
  "1h_to_8h": "1 a 8 h",
  "8h_to_24h": "8 a 24 h",
  over_24h: "Mais de 24 h",
};

function Resolver({ name, data }: { name: string; data: ResolutionDetailData["by_resolver"]["ai"] }) {
  return (
    <div role="group" aria-label={name} className="rounded-xl bg-elevated p-4">
      <p className="text-sm text-muted">{name}</p>
      <p className="mt-1.5 text-2xl font-semibold tabular">{duration(data.median_seconds)}</p>
      <p className="mt-1 text-xs text-faint">
        mediana · {plural(data.count, "ticket", "tickets")}
        {data.mean_seconds !== null && ` · média ${duration(data.mean_seconds)}`}
      </p>
    </div>
  );
}

// Detalhe do tempo de solução (ADR 0011): da abertura ao fechamento dos tickets fechados nos últimos 7 dias.
export function ResolutionDetail({ token }: { token: string }) {
  const load = useCallback(() => fetchResolutionDetail(token), [token]);
  const detail = usePolling(load, REFRESH_MS);
  const data = detail.data;

  if (!data) return detail.error ? <Message>Não foi possível carregar o tempo de solução.</Message> : <LoadingScreen />;

  return (
    <DetailPage title="Tempo de solução" subtitle={`da abertura ao fechamento · últimos 7 dias · atualizado às ${timeOfDay(data.generated_at)}`}>
      <section aria-label="Indicadores" className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <Stat name="Mediana" value={duration(data.median_seconds)} detail="metade dos tickets fecha antes disso" />
        <Stat name="Média" value={duration(data.mean_seconds)} detail="puxada para cima pelos mais lentos" />
        <Stat name="Resolvidos" value={data.resolved} detail="fechados nos últimos 7 dias" />
        <Stat
          name="Dentro da meta"
          value={data.within_target_percent === null ? "—" : `${data.within_target_percent}%`}
          detail={`meta de ${durationText(data.target_seconds)}`}
        />
      </section>

      {data.resolved === 0 ? (
        <p className="text-sm text-faint">Nenhum ticket resolvido nos últimos 7 dias.</p>
      ) : (
        <>
          <div className="grid gap-5 lg:grid-cols-2">
            <Section title="Distribuição">
              <BarList
                label="Resolvidos por faixa de tempo"
                items={data.buckets.map((bucket) => ({
                  key: bucket.key,
                  label: BUCKET_LABELS[bucket.key],
                  value: bucket.count,
                  display: bucket.count,
                  color: bucket.key === "over_24h" ? "var(--color-danger)" : bucket.key === "8h_to_24h" ? "var(--color-risk)" : "var(--color-accent)",
                }))}
              />
            </Section>
            <Section title="IA contra humano">
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <Resolver name="Pela IA" data={data.by_resolver.ai} />
                <Resolver name="Por humano" data={data.by_resolver.human} />
              </div>
            </Section>
          </div>

          <div className="grid gap-5 lg:grid-cols-2">
            <Section title="Por marca" label="Tempo de solução por marca">
              <BarList
                label="Por marca"
                items={data.brands.map((brand) => ({
                  key: brand.brand,
                  label: BRAND_LABELS[brand.brand] ?? brand.brand,
                  value: brand.median_seconds ?? 0,
                  display: `${duration(brand.median_seconds)} · ${brand.resolved}`,
                  color: "var(--color-info)",
                }))}
              />
              <p className="mt-3 text-xs text-faint">Mediana e quantidade de tickets resolvidos.</p>
            </Section>
            <Section title="Por assunto" label="Tempo de solução por assunto">
              <BarList
                label="Por assunto"
                items={data.categories.map((category) => ({
                  key: category.category ?? "none",
                  label: categoryLabel(category.category),
                  value: category.median_seconds ?? 0,
                  display: `${duration(category.median_seconds)} · ${category.resolved}`,
                  color: "var(--color-warning)",
                }))}
              />
              <p className="mt-3 text-xs text-faint">Mediana e quantidade de tickets resolvidos.</p>
            </Section>
          </div>

          <Section title="Mediana por dia" label="Série diária">
            <DayChart
              label="Mediana por dia"
              series={[{ name: "Mediana", color: "var(--color-accent)" }]}
              days={data.daily.map((day) => ({ date: day.date, values: [day.median_seconds] }))}
              format={durationText}
            />
          </Section>

          <Section title="Tickets mais lentos" label="Mais lentos">
            <table aria-label="Tickets mais lentos" className="mt-2 w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-faint">
                  <th className="py-2 font-normal">Ticket</th>
                  <th className="py-2 font-normal">Marca</th>
                  <th className="py-2 font-normal">Assunto</th>
                  <th className="py-2 font-normal">Tempo</th>
                  <th className="py-2 font-normal">Resolvido por</th>
                </tr>
              </thead>
              <tbody>
                {data.slowest.map((ticket) => (
                  <tr key={ticket.id} className="border-t border-line/60">
                    <td className="py-2.5 font-mono text-xs text-muted">#{ticket.id.slice(0, 6).toUpperCase()}</td>
                    <td className="py-2.5">{BRAND_LABELS[ticket.brand] ?? ticket.brand}</td>
                    <td className="py-2.5">{categoryLabel(ticket.category)}</td>
                    <td className="py-2.5 font-medium tabular">{durationText(ticket.seconds)}</td>
                    <td className="py-2.5">{ticket.resolved_by === "ai" ? "IA" : (ticket.agent ?? "Humano")}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Section>
        </>
      )}
    </DetailPage>
  );
}
