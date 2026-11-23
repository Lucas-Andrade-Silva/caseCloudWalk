import { Download, TrendingDown, TrendingUp } from "lucide-react";
import { useCallback, useState, type ReactNode } from "react";
import { fetchDashboard, type DashboardMetrics, type Me } from "../../lib/api";
import { CHANNEL_LABELS, timeOfDay } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { Button } from "../../ui/Button";

const REFRESH_MS = 15_000;

// Paletas validadas (skill de dataviz, superfície branca): criados × resolvidos e canais (água-marinha abaixo de
// 3:1, por isso todo canal leva rótulo e número visíveis).
const SERIES = { created: "#16a34a", closed: "#6250d6" };
const CHANNEL_COLORS: Record<string, string> = { whatsapp: "#2a78d6", email: "#eb6834", app_chat: "#1baf7a" };
const CHANNEL_ORDER = ["whatsapp", "email", "app_chat"];

const BUCKET_LABELS: Record<string, string> = {
  up_to_5m: "Até 5 min",
  "5m_to_15m": "5 a 15 min",
  "15m_to_1h": "15 min a 1 h",
  over_1h: "Mais de 1 h",
  waiting: "Ainda sem resposta",
};

const dayLabel = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
const percent = (part: number, total: number) => (total > 0 ? Math.round((part / total) * 100) : 0);

export function durationText(seconds: number): string {
  if (seconds < 60) return `${seconds} s`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest > 0 ? `${hours} h ${String(rest).padStart(2, "0")} min` : `${hours} h`;
}

function deltaText(today: number, yesterday: number): { text: string; short: string; direction: "up" | "down" | "same" } {
  const delta = today - yesterday;
  if (delta === 0) return { text: "igual a ontem", short: "0", direction: "same" };
  const short = `${delta > 0 ? "+" : "−"}${Math.abs(delta)}`;
  return { text: `${short} em relação a ontem`, short, direction: delta > 0 ? "up" : "down" };
}

function Card({ title, label, children, className = "" }: { title: string; label?: string; children: ReactNode; className?: string }) {
  return (
    <section aria-label={label ?? title} className={`rounded-xl border border-line bg-surface p-5 shadow-card ${className}`}>
      <h2 className="text-[15px] font-semibold tracking-tight">{title}</h2>
      {children}
    </section>
  );
}

function Kpi({ name, value, detail, trend }: { name: string; value: string; detail: string; trend?: ReturnType<typeof deltaText> }) {
  const Icon = trend?.direction === "down" ? TrendingDown : TrendingUp;
  return (
    <div role="group" aria-label={name} className="min-w-0 px-5 py-4 first:pl-0">
      <p className="text-sm text-muted">{name}</p>
      <p className="mt-1.5 flex items-center gap-2">
        <span className="text-[26px] leading-none font-semibold tracking-tight tabular">{value}</span>
        {trend && trend.direction !== "same" && (
          <span aria-hidden className="inline-flex items-center gap-0.5 rounded-full bg-elevated px-1.5 py-0.5 text-[11px] font-medium text-muted tabular">
            {trend.short}
            <Icon className="size-3" strokeWidth={2.2} />
          </span>
        )}
      </p>
      <p className="mt-1.5 truncate text-xs text-faint">{trend ? trend.text : detail}</p>
      {trend && <p className="truncate text-xs text-faint">{detail}</p>}
    </div>
  );
}

function niceMax(value: number): number {
  if (value <= 4) return 4;
  const magnitude = 10 ** Math.floor(Math.log10(value / 4));
  const step = [1, 2, 2.5, 5, 10].map((factor) => factor * magnitude).find((candidate) => candidate * 4 >= value)!;
  return step * 4;
}

function DailyBars({ daily }: { daily: DashboardMetrics["daily"] }) {
  const [hovered, setHovered] = useState<number | null>(null);
  const max = niceMax(Math.max(...daily.flatMap((day) => [day.created, day.closed]), 1));
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((fraction) => Math.round(max * fraction));
  const totalCreated = daily.reduce((sum, day) => sum + day.created, 0);
  const totalClosed = daily.reduce((sum, day) => sum + day.closed, 0);

  return (
    <div className="mt-4 grid grid-cols-[9rem_1fr] gap-6">
      <div className="space-y-6 pt-4">
        <div>
          <p className="flex items-center gap-2 text-xs text-muted">
            <span aria-hidden className="size-2 rounded-full" style={{ background: SERIES.created }} /> Criados por dia
          </p>
          <p className="mt-1 text-2xl font-semibold tabular">{(totalCreated / daily.length).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}</p>
        </div>
        <div>
          <p className="flex items-center gap-2 text-xs text-muted">
            <span aria-hidden className="size-2 rounded-full" style={{ background: SERIES.closed }} /> Resolvidos por dia
          </p>
          <p className="mt-1 text-2xl font-semibold tabular">{(totalClosed / daily.length).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}</p>
        </div>
        <p className="text-[11px] leading-relaxed text-faint">Média dos últimos {daily.length} dias.</p>
      </div>

      <div className="relative" onMouseLeave={() => setHovered(null)}>
        <div aria-hidden className="relative h-52">
          {ticks.map((tick) => (
            <div key={tick} className="absolute inset-x-0 flex items-center gap-2" style={{ bottom: `${(tick / max) * 100}%` }}>
              <span className="w-6 shrink-0 translate-y-1/2 text-right text-[10px] text-faint tabular">{tick}</span>
              <span className="h-px flex-1 translate-y-1/2 bg-line" />
            </div>
          ))}
          <div className="absolute inset-y-0 right-0 left-8 flex items-end justify-around">
            {daily.map((day, index) => (
              <div
                key={day.date}
                className={`flex h-full w-full items-end justify-center gap-[2px] rounded-md transition-colors ${hovered === index ? "bg-elevated" : ""}`}
                onMouseEnter={() => setHovered(index)}
              >
                {(["created", "closed"] as const).map((series) => (
                  <span
                    key={series}
                    className="w-4 rounded-t-[4px] transition-[height] duration-300"
                    style={{ height: `${(day[series] / max) * 100}%`, background: SERIES[series], minHeight: day[series] > 0 ? 2 : 0 }}
                  />
                ))}
              </div>
            ))}
          </div>
          {hovered !== null && (
            <div
              className="pointer-events-none absolute top-0 z-10 w-36 -translate-x-1/2 rounded-lg border border-line bg-surface p-2.5 text-xs shadow-card"
              style={{ left: `calc(2rem + (100% - 2rem) * ${(hovered + 0.5) / daily.length})` }}
            >
              <p className="font-semibold">{dayLabel(daily[hovered]!.date)}</p>
              <p className="mt-1 flex justify-between text-muted">
                Criados <span className="font-medium text-text tabular">{daily[hovered]!.created}</span>
              </p>
              <p className="flex justify-between text-muted">
                Resolvidos <span className="font-medium text-text tabular">{daily[hovered]!.closed}</span>
              </p>
            </div>
          )}
        </div>
        <div aria-hidden className="mt-2 ml-8 flex justify-around">
          {daily.map((day, index) => (
            <span key={day.date} className={`text-[11px] tabular ${hovered === index ? "font-semibold text-text" : "text-faint"}`}>
              {dayLabel(day.date)}
            </span>
          ))}
        </div>
        <table aria-label="Tickets criados e resolvidos por dia" className="sr-only">
          <thead>
            <tr>
              <th>Dia</th>
              <th>Criados</th>
              <th>Resolvidos</th>
            </tr>
          </thead>
          <tbody>
            {daily.map((day) => (
              <tr key={day.date}>
                <td>{dayLabel(day.date)}</td>
                <td>{day.created}</td>
                <td>{day.closed}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function ChannelGauge({ channels }: { channels: DashboardMetrics["channels"] }) {
  const ordered = CHANNEL_ORDER.map((channel) => channels.find((item) => item.channel === channel)).filter(
    (item): item is { channel: string; count: number } => Boolean(item && item.count > 0),
  );
  const total = ordered.reduce((sum, item) => sum + item.count, 0);
  // Meia rosca: o arco de 180° é dividido pelos canais, com 2° de folga entre os segmentos.
  const radius = 80;
  const gap = ordered.length > 1 ? 2 : 0;
  const arcs = ordered.map((item, index) => {
    const before = ordered.slice(0, index).reduce((sum, previous) => sum + previous.count, 0);
    const start = 180 - (before / total) * 180;
    const end = start - (item.count / total) * 180;
    return { ...item, start: start - gap / 2, end: end + gap / 2 };
  });
  const point = (angle: number) => {
    const radians = (angle * Math.PI) / 180;
    return `${100 + radius * Math.cos(radians)} ${100 - radius * Math.sin(radians)}`;
  };

  return (
    <div className="mt-4 flex flex-col items-center">
      <svg viewBox="0 0 200 112" role="img" aria-label={`${total} tickets por canal nos últimos 7 dias`} className="w-full max-w-72">
        <path d={`M ${point(180)} A ${radius} ${radius} 0 0 1 ${point(0)}`} fill="none" stroke="var(--color-elevated)" strokeWidth="16" strokeLinecap="round" />
        {arcs.map((arc) => (
          <path
            key={arc.channel}
            d={`M ${point(arc.start)} A ${radius} ${radius} 0 0 1 ${point(arc.end)}`}
            fill="none"
            stroke={CHANNEL_COLORS[arc.channel] ?? "#64748b"}
            strokeWidth="16"
            strokeLinecap="butt"
          />
        ))}
        <text x="100" y="80" textAnchor="middle" className="fill-faint text-[9px]">
          Tickets nos últimos 7 dias
        </text>
        <text x="100" y="102" textAnchor="middle" className="fill-text text-[22px] font-semibold">
          {total}
        </text>
      </svg>
      <ul aria-label="Tickets por canal" className="mt-3 flex flex-wrap justify-center gap-x-5 gap-y-2">
        {ordered.map((item) => (
          <li key={item.channel} className="flex items-center gap-1.5 text-xs text-muted">
            <span aria-hidden className="size-2.5 rounded-sm" style={{ background: CHANNEL_COLORS[item.channel] }} />
            <span>{CHANNEL_LABELS[item.channel] ?? item.channel}</span>
            <span className="font-semibold text-text tabular">{item.count}</span>
            <span className="text-faint tabular">{percent(item.count, total)}%</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function ReplyBuckets({ firstReply }: { firstReply: DashboardMetrics["first_reply"] }) {
  const max = Math.max(...firstReply.buckets.map((bucket) => bucket.count), 1);
  return (
    <ul aria-label="Primeira resposta humana por faixa" className="mt-5 space-y-3.5">
      {firstReply.buckets.map((bucket) => (
        <li key={bucket.key} className="grid grid-cols-[7.5rem_1fr_2rem] items-center gap-3 text-xs">
          <span className="text-muted">{BUCKET_LABELS[bucket.key]}</span>
          <span aria-hidden className="h-2 overflow-hidden rounded-full bg-elevated">
            <span
              className={`block h-full rounded-full ${bucket.key === "waiting" ? "bg-warning/70" : "bg-accent"}`}
              style={{ width: `${(bucket.count / max) * 100}%`, opacity: bucket.key === "waiting" ? 1 : 0.35 + 0.65 * (1 - BUCKET_ORDER.indexOf(bucket.key) / 4) }}
            />
          </span>
          <span className="text-right font-semibold tabular">{bucket.count}</span>
        </li>
      ))}
    </ul>
  );
}

const BUCKET_ORDER = ["up_to_5m", "5m_to_15m", "15m_to_1h", "over_1h"];

function Share({ label, value, total, color }: { label: string; value: number; total: number; color: string }) {
  return (
    <div>
      <p className="text-sm text-muted">{label}</p>
      <p className="mt-1 flex items-baseline gap-2">
        <span className="text-2xl font-semibold tabular">{value}</span>
        <span className="text-sm font-medium text-muted tabular">{percent(value, total)}%</span>
      </p>
      <span aria-hidden className="mt-2 block h-1.5 overflow-hidden rounded-full bg-elevated">
        <span className={`block h-full rounded-full ${color}`} style={{ width: `${percent(value, total)}%` }} />
      </span>
    </div>
  );
}

function exportCsv(metrics: DashboardMetrics) {
  const lines = ["dia,criados,resolvidos", ...metrics.daily.map((day) => `${day.date},${day.created},${day.closed}`)];
  const url = URL.createObjectURL(new Blob([`${lines.join("\n")}\n`], { type: "text/csv" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `painel-${metrics.daily.at(-1)?.date ?? "helpdesk"}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

// Painel (ADR 0009, W8): a visão geral da operação, só com números reais da plataforma.
export function Dashboard({ token, me }: { token: string; me: Me }) {
  const load = useCallback(() => fetchDashboard(token), [token]);
  const dashboard = usePolling(load, REFRESH_MS);
  const data = dashboard.data;

  if (!data) {
    return (
      <div className="flex flex-1 items-center justify-center p-8 text-sm text-faint">
        {dashboard.error ? "Não foi possível carregar o painel." : "Carregando…"}
      </div>
    );
  }

  const windowTotal = data.daily.reduce((sum, day) => sum + day.created + day.closed, 0);
  const slaTotal = data.sla.met + data.sla.missed;
  const resolvedTotal = data.resolution.ai + data.resolution.human;

  return (
    <div className="h-screen flex-1 overflow-y-auto">
      <header className="flex items-center gap-4 border-b border-line bg-surface px-8 py-4">
        <h1 className="text-xl font-semibold tracking-tight">Painel</h1>
        <p className="text-xs text-faint">
          {me.role === "ops" ? "Todas as marcas" : "Suas marcas"} · atualizado às {timeOfDay(data.generated_at)}
        </p>
        <Button variant="primary" className="ml-auto" onClick={() => exportCsv(data)}>
          <Download aria-hidden className="size-4" strokeWidth={2} />
          Exportar CSV
        </Button>
      </header>

      <div className="space-y-5 p-8">
        <section
          aria-label="Indicadores"
          className="grid grid-cols-2 divide-line rounded-xl border border-line bg-surface px-5 shadow-card xl:grid-cols-4 xl:divide-x"
        >
          <Kpi
            name="Abertos agora"
            value={String(data.open.total)}
            detail={`${data.open.ai} com a IA · ${data.open.pending_human} na fila · ${data.open.human} com humano`}
          />
          <Kpi
            name="Criados hoje"
            value={String(data.today.created)}
            detail={`ontem: ${data.yesterday.created}`}
            trend={deltaText(data.today.created, data.yesterday.created)}
          />
          <Kpi
            name="Resolvidos hoje"
            value={String(data.today.closed)}
            detail={`ontem: ${data.yesterday.closed}`}
            trend={deltaText(data.today.closed, data.yesterday.closed)}
          />
          <Kpi
            name="Primeira resposta humana"
            value={data.first_reply.median_seconds === null ? "—" : durationText(data.first_reply.median_seconds)}
            detail={
              data.first_reply.answered > 0
                ? `mediana de ${data.first_reply.answered} respostas em 7 dias`
                : "sem respostas ainda"
            }
          />
        </section>

        <div className="grid gap-5 xl:grid-cols-[2fr_1fr]">
          <Card title="Tickets por dia" label="Tickets criados e resolvidos">
            {windowTotal === 0 ? (
              <p className="mt-6 text-sm text-faint">Nenhum ticket nos últimos 7 dias.</p>
            ) : (
              <DailyBars daily={data.daily} />
            )}
          </Card>
          <Card title="Primeira resposta humana">
            <p className="mt-1 text-xs text-faint">Tickets escalados nos últimos 7 dias, pelo tempo até a primeira resposta.</p>
            <ReplyBuckets firstReply={data.first_reply} />
          </Card>
        </div>

        <div className="grid gap-5 xl:grid-cols-2">
          <Card title="Tickets por canal">
            {data.channels.length === 0 ? (
              <p className="mt-6 text-sm text-faint">Nenhum canal recebeu tickets nos últimos 7 dias.</p>
            ) : (
              <ChannelGauge channels={data.channels} />
            )}
          </Card>
          <Card title="Quem resolveu">
            <p className="mt-1 text-xs text-faint">Tickets fechados nos últimos 7 dias.</p>
            <div className="mt-5 grid grid-cols-2 gap-6">
              <Share label="Resolvido pela IA" value={data.resolution.ai} total={resolvedTotal} color="bg-accent" />
              <Share label="Resolvido por humano" value={data.resolution.human} total={resolvedTotal} color="bg-info" />
            </div>
            <div className="mt-6 border-t border-line pt-5">
              <p className="text-sm text-muted">SLA da primeira resposta</p>
              <p className="mt-1 text-sm">
                <span className="text-2xl font-semibold tabular">{data.sla.met}</span>
                <span className="text-muted"> de {slaTotal} no prazo</span>
              </p>
              <span aria-hidden className="mt-2 flex h-1.5 gap-[2px] overflow-hidden rounded-full bg-elevated">
                <span className="h-full rounded-l-full bg-accent" style={{ width: `${percent(data.sla.met, slaTotal)}%` }} />
                <span className="h-full rounded-r-full bg-danger" style={{ width: `${percent(data.sla.missed, slaTotal)}%` }} />
              </span>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
