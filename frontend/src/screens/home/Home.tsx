import { ArrowRight, Bot, Clock3, Headset, Inbox, Radar, Ticket, Timer, TrendingUp, TriangleAlert, Workflow, type LucideIcon } from "lucide-react";
import { useCallback, type ReactNode } from "react";
import { fetchDashboard, fetchIncidents, fetchMap, fetchWork, type DashboardMetrics, type Incident, type Me } from "../../lib/api";
import { BRAND_LABELS, timeOfDay } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { LoadingScreen } from "../../ui/LoadingScreen";
import type { MapTicket } from "../map/model";
import { curvePoints, peakIndex, smoothPath } from "./curve";
import { SolutionTime, TeamPerformance, TicketOperations } from "./OpsCards";

const REFRESH_MS = 10_000;
const percent = (part: number, total: number) => (total > 0 ? Math.round((part / total) * 100) : 0);
const weekday = (iso: string) =>
  ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"][new Date(`${iso}T12:00:00`).getDay()]!;

// Tela inicial em cards (ADR 0010): cada card resume uma parte da plataforma e abre a tela de detalhe dela.
function CardLink({
  label,
  href,
  icon: Icon,
  className = "",
  aside,
  children,
}: {
  label: string;
  href: string;
  icon: LucideIcon;
  className?: string;
  aside?: ReactNode;
  children: ReactNode;
}) {
  // O link é o título; o ::after dele cobre o card inteiro, então o card todo é clicável e o nome do link
  // continua sendo o texto visível (axe: label-content-name-mismatch).
  return (
    <article
      aria-label={label}
      className={`group relative flex min-h-0 flex-col rounded-2xl border border-line bg-surface p-5 transition-colors duration-200 hover:border-line-strong hover:bg-elevated/60 ${className}`}
    >
      <span className="flex items-center gap-2.5 text-sm text-muted">
        <span aria-hidden className="flex size-7 items-center justify-center rounded-lg border border-line text-faint transition-colors group-hover:text-accent">
          <Icon className="size-3.5" strokeWidth={1.6} />
        </span>
        <a href={href} className="after:absolute after:inset-0 after:z-10 after:rounded-2xl after:content-['']">
          {label}
        </a>
        {aside && <span className="ml-auto">{aside}</span>}
      </span>
      {children}
    </article>
  );
}

function SeeDetails() {
  return (
    <span className="flex items-center gap-1 text-xs text-faint transition-colors group-hover:text-accent-ink">
      Ver detalhes
      <ArrowRight aria-hidden className="size-3.5" strokeWidth={1.8} />
    </span>
  );
}

function VolumeChart({ daily }: { daily: DashboardMetrics["daily"] }) {
  const width = 600;
  const height = 220;
  const created = daily.map((day) => day.created);
  const closed = daily.map((day) => day.closed);
  const max = Math.max(...created, ...closed, 1);
  const scale = (values: number[]) => curvePoints(values.map((value) => (value / max) * 100), width, height, 30);
  const createdPoints = scale(created);
  const line = smoothPath(createdPoints);
  const ghost = smoothPath(scale(closed));
  const peak = peakIndex(created);
  const peakPoint = createdPoints[peak]!;

  return (
    <div className="relative mt-4 flex min-h-0 flex-1 flex-col">
      <div className="relative min-h-44 flex-1">
        <svg aria-hidden viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" className="absolute inset-0 size-full overflow-visible">
          <defs>
            <linearGradient id="volume-fill" x1="0" x2="0" y1="0" y2="1">
              <stop offset="0" stopColor="var(--color-accent)" stopOpacity="0.28" />
              <stop offset="1" stopColor="var(--color-accent)" stopOpacity="0" />
            </linearGradient>
            <filter id="volume-glow" x="-20%" y="-50%" width="140%" height="200%">
              <feGaussianBlur stdDeviation="4" />
            </filter>
          </defs>
          <path d={`${line} L ${width} ${height} L 0 ${height} Z`} fill="url(#volume-fill)" />
          <path d={ghost} fill="none" stroke="var(--color-faint)" strokeWidth="1.5" strokeDasharray="3 5" vectorEffect="non-scaling-stroke" />
          <path d={line} fill="none" stroke="var(--color-accent)" strokeWidth="2.5" vectorEffect="non-scaling-stroke" />
          {/* A luz que percorre a linha: um trecho curto do traço, com brilho, andando da esquerda para a direita. */}
          <path d={line} pathLength={100} className="volume-sweep" fill="none" stroke="#c8f7e6" strokeWidth="6" strokeLinecap="round" filter="url(#volume-glow)" vectorEffect="non-scaling-stroke" />
          <path d={line} pathLength={100} className="volume-sweep" fill="none" stroke="#f0fffa" strokeWidth="2.5" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
          <line x1={peakPoint.x} x2={peakPoint.x} y1={peakPoint.y} y2={height} stroke="var(--color-accent)" strokeDasharray="3 4" vectorEffect="non-scaling-stroke" />
        </svg>
        <span
          aria-hidden
          className="absolute size-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-accent bg-surface shadow-[0_0_12px_var(--color-accent)]"
          style={{ left: `${(peakPoint.x / width) * 100}%`, top: `${(peakPoint.y / height) * 100}%` }}
        />
        <span
          className="absolute -translate-x-1/2 -translate-y-[calc(100%+14px)] rounded-md border border-line bg-elevated px-2 py-0.5 text-xs font-medium whitespace-nowrap tabular"
          style={{ left: `${(peakPoint.x / width) * 100}%`, top: `${(peakPoint.y / height) * 100}%` }}
        >
          {created[peak]} · Pico
        </span>
      </div>
      <div aria-hidden className="mt-3 flex justify-between text-[11px] text-faint">
        {daily.map((day) => (
          <span key={day.date}>{weekday(day.date)}</span>
        ))}
      </div>
      <table aria-label="Tickets criados por dia" className="sr-only">
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
              <td>{day.date}</td>
              <td>{day.created}</td>
              <td>{day.closed}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Ring({ value, tone }: { value: number; tone: string }) {
  const radius = 34;
  const length = 2 * Math.PI * radius;
  return (
    <svg aria-hidden viewBox="0 0 84 84" className="size-24 shrink-0 -rotate-90">
      <circle cx="42" cy="42" r={radius} fill="none" stroke="var(--color-elevated)" strokeWidth="7" />
      <circle
        cx="42"
        cy="42"
        r={radius}
        fill="none"
        stroke={tone}
        strokeWidth="7"
        strokeLinecap="round"
        strokeDasharray={`${(value / 100) * length} ${length}`}
        className="transition-[stroke-dasharray] duration-700"
      />
    </svg>
  );
}

const MODE_COLORS: Record<string, string> = {
  ai: "var(--color-accent)",
  pending_human: "var(--color-warning)",
  human: "var(--color-info)",
};

// Mapa vivo em miniatura: as bolhas atuais em órbitas, girando devagar.
function MiniMap({ tickets }: { tickets: MapTicket[] }) {
  const shown = tickets.slice(0, 80);
  return (
    <div className="relative mt-3 flex flex-1 items-center justify-center">
      <svg aria-hidden viewBox="-110 -110 220 220" className="size-full max-h-64">
        {[40, 70, 100].map((radius) => (
          <circle key={radius} r={radius} fill="none" stroke="var(--color-line)" strokeDasharray="2 5" />
        ))}
        <g className="map-orbit">
          {shown.map((ticket, index) => {
            const ring = [40, 70, 100][index % 3]!;
            const angle = index * 2.399963;
            const size = ticket.priority === "p1" ? 6 : ticket.priority === "p2" ? 5 : 3.5;
            return (
              <circle
                key={ticket.id}
                cx={Math.cos(angle) * ring}
                cy={Math.sin(angle) * ring}
                r={size}
                fill={MODE_COLORS[ticket.mode] ?? "var(--color-faint)"}
                opacity={0.9}
              />
            );
          })}
        </g>
        <circle r="14" fill="var(--color-accent)" opacity="0.15" className="map-pulse" />
        <circle r="5" fill="var(--color-accent)" />
      </svg>
    </div>
  );
}

function Legend({ items }: { items: { label: string; color: string; value: number | string }[] }) {
  return (
    <ul className="space-y-1.5 text-xs">
      {items.map((item) => (
        <li key={item.label} className="flex items-center gap-2 text-muted">
          <span aria-hidden className="size-2 rounded-full" style={{ background: item.color }} />
          {item.label}
          <span className="ml-auto pl-3 font-medium text-text tabular">{item.value}</span>
        </li>
      ))}
    </ul>
  );
}

function Loading() {
  return <p className="mt-4 text-sm text-faint">Carregando…</p>;
}

export function Home({ token, me }: { token: string; me: Me }) {
  const isOps = me.role === "ops";
  const loadDashboard = useCallback(() => fetchDashboard(token), [token]);
  const loadIncidents = useCallback(() => fetchIncidents(token), [token]);
  const loadMap = useCallback(() => fetchMap<MapTicket>(token), [token]);
  const dashboardPoll = usePolling(loadDashboard, REFRESH_MS);
  const incidentsPoll = usePolling(loadIncidents, REFRESH_MS);
  const mapPoll = usePolling(loadMap, REFRESH_MS);
  const dashboard = dashboardPoll.data;
  const incidents: Incident[] = incidentsPoll.data?.incidents ?? [];
  const map = mapPoll.data;
  const loadWork = useCallback(() => fetchWork(token), [token]);
  const work = usePolling(isOps ? null : loadWork, REFRESH_MS);

  // Enquanto algum dado ainda não chegou, a tela de carregamento. Um dado que falhou não segura a tela: ela abre
  // com o que houver, e o card do que faltou mostra "Carregando…" até a próxima tentativa.
  const polls = isOps ? [dashboardPoll, incidentsPoll, mapPoll] : [dashboardPoll, incidentsPoll, mapPoll, work];
  if (!polls.every((poll) => poll.data !== null || poll.error !== null)) return <LoadingScreen label="Montando a tela inicial…" />;

  const resolved = dashboard ? dashboard.resolution.ai + dashboard.resolution.human : 0;
  const slaTotal = dashboard ? dashboard.sla.met + dashboard.sla.missed : 0;
  const slaPercent = dashboard ? percent(dashboard.sla.met, slaTotal) : 0;

  return (
    <div className="h-full flex-1 overflow-y-auto">
      <div className="mx-auto max-w-[1440px] px-6 py-6">
        <div className="mb-5 flex items-baseline gap-3">
          <h1 className="text-xl font-semibold tracking-tight">Início</h1>
          <p className="text-xs text-faint">
            {isOps ? "Todas as marcas" : "Suas marcas"}
            {dashboard && ` · atualizado às ${timeOfDay(dashboard.generated_at)}`}
          </p>
        </div>

        <section aria-label="Atalhos" className="grid auto-rows-[minmax(13rem,auto)] gap-4 md:grid-cols-2 xl:grid-cols-4">
          <CardLink
            label="Volume de tickets"
            href="#/painel"
            icon={TrendingUp}
            className="md:col-span-2 xl:row-span-2"
            aside={<span className="rounded-md border border-line px-2 py-0.5 text-xs text-faint">Últimos 7 dias</span>}
          >
            {dashboard ? <VolumeChart daily={dashboard.daily} /> : <Loading />}
          </CardLink>

          <CardLink label="Resolvidos pela IA" href="#/painel" icon={Bot} className="xl:col-start-4 xl:row-start-1">
            {dashboard ? (
              <>
                <p className="mt-4 text-4xl font-semibold tracking-tight tabular">
                  {percent(dashboard.resolution.ai, resolved)}
                  <span className="text-lg text-muted">%</span>
                </p>
                <span aria-hidden className="mt-3 flex h-1.5 gap-[2px] overflow-hidden rounded-full bg-elevated">
                  <span className="h-full bg-accent transition-[width] duration-700" style={{ width: `${percent(dashboard.resolution.ai, resolved)}%` }} />
                  <span className="h-full bg-info" style={{ width: `${percent(dashboard.resolution.human, resolved)}%` }} />
                </span>
                <div className="mt-auto pt-4">
                  <Legend
                    items={[
                      { label: "Pela IA em 7 dias", color: "var(--color-accent)", value: dashboard.resolution.ai },
                      { label: "Por humano", color: "var(--color-info)", value: dashboard.resolution.human },
                      { label: "Handoff esperando humano", color: "var(--color-warning)", value: dashboard.open.pending_human },
                    ]}
                  />
                </div>
              </>
            ) : (
              <Loading />
            )}
          </CardLink>

          <CardLink label="SLA da primeira resposta" href="#/painel" icon={Timer} className="xl:col-start-4 xl:row-start-2">
            {dashboard ? (
              <div className="mt-3 flex flex-1 items-center gap-5">
                <div className="relative">
                  <Ring value={slaPercent} tone={slaPercent >= 80 ? "var(--color-accent)" : slaPercent >= 50 ? "var(--color-warning)" : "var(--color-danger)"} />
                  <span className="absolute inset-0 flex items-center justify-center text-2xl font-semibold tabular">
                    {slaPercent}
                    <span className="text-xs text-muted">%</span>
                  </span>
                </div>
                <Legend
                  items={[
                    { label: "No prazo", color: "var(--color-accent)", value: dashboard.sla.met },
                    { label: "Fora do prazo", color: "var(--color-danger)", value: dashboard.sla.missed },
                    {
                      label: "Tempo médio",
                      color: "var(--color-faint)",
                      value: dashboard.first_reply.mean_seconds === null ? "—" : `${Math.round(dashboard.first_reply.mean_seconds / 60)} min`,
                    },
                  ]}
                />
              </div>
            ) : (
              <Loading />
            )}
          </CardLink>

          <CardLink label="Mapa vivo" href="#/mapa" icon={Radar} className="xl:col-start-3 xl:row-span-2 xl:row-start-1">
            <MiniMap tickets={map?.tickets ?? []} />
            <div className="mt-2 flex items-end justify-between gap-3">
              <p>
                <span className="text-3xl font-semibold tabular">{map?.total ?? dashboard?.open.total ?? 0}</span>
                <span className="ml-1.5 text-xs text-muted">tickets ativos</span>
              </p>
              <Legend
                items={[
                  { label: "Com a IA", color: MODE_COLORS.ai!, value: dashboard?.open.ai ?? "—" },
                  { label: "Esperando humano", color: MODE_COLORS.pending_human!, value: dashboard?.open.pending_human ?? "—" },
                  { label: "Com humano", color: MODE_COLORS.human!, value: dashboard?.open.human ?? "—" },
                ]}
              />
            </div>
          </CardLink>

          <CardLink label="Tempo de solução" href="#/solucao" icon={Clock3}>
            {dashboard ? <SolutionTime data={dashboard} /> : <Loading />}
          </CardLink>

          <CardLink
            label="Modo Incidente"
            href={isOps ? "#/mapa" : "#/fila"}
            icon={TriangleAlert}
            className={`md:col-span-2 ${incidents.length > 0 ? "border-incident/60" : ""}`}
            aside={
              incidents.length > 0 && (
                <span className="flex items-center gap-1.5 text-xs font-medium text-incident-text">
                  <span aria-hidden className="size-2 animate-pulse rounded-full bg-incident" />
                  {incidents.length} {incidents.length === 1 ? "aberto" : "abertos"}
                </span>
              )
            }
          >
            {incidents.length === 0 ? (
              <p className="mt-4 text-sm text-faint">Nenhum incidente aberto. A plataforma agrupa sozinha picos de tickets parecidos.</p>
            ) : (
              <ul aria-label="Incidentes abertos" className="mt-4 grid gap-3 sm:grid-cols-2">
                {incidents.slice(0, 4).map((incident) => (
                  <li key={incident.id} className="flex items-center gap-3 rounded-xl bg-elevated px-4 py-3">
                    <span aria-hidden className="size-2.5 shrink-0 rounded-sm bg-incident" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium">{incident.title}</span>
                      <span className="block text-xs text-faint">{BRAND_LABELS[incident.brand] ?? incident.brand}</span>
                    </span>
                    <span className="text-2xl font-semibold tabular">{incident.open_tickets}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardLink>

          {isOps ? (
            <CardLink label="Filas e regras" href="#/operacao" icon={Workflow}>
              <p className="mt-4 max-w-md text-sm text-muted">
                Crie filas e equipes e edite as regras versionadas que decidem prioridade e destino de cada ticket.
              </p>
            </CardLink>
          ) : (
            <CardLink label="Fila" href="#/fila" icon={Inbox}>
              <div className="mt-4 grid gap-3">
                <div className="rounded-xl bg-elevated px-4 py-3">
                  <p className="text-sm">Esperando nas suas filas</p>
                  <p className="mt-1 text-3xl font-semibold tabular">{work.data?.waiting_count ?? "—"}</p>
                </div>
                <div className="rounded-xl bg-elevated px-4 py-3">
                  <p className="text-sm">Com você</p>
                  <p className="mt-1 text-3xl font-semibold tabular">{work.data?.mine.length ?? "—"}</p>
                </div>
              </div>
            </CardLink>
          )}

          <CardLink label="Desempenho do time" href="#/time" icon={Headset} className="md:col-span-2" aside={<SeeDetails />}>
            {dashboard ? <TeamPerformance data={dashboard} /> : <Loading />}
          </CardLink>

          <CardLink label="Operação dos tickets" href="#/tickets" icon={Ticket} className="md:col-span-2" aside={<SeeDetails />}>
            {dashboard ? <TicketOperations data={dashboard} /> : <Loading />}
          </CardLink>
        </section>
      </div>
    </div>
  );
}

