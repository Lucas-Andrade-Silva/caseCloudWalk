import { useCallback, useEffect, useMemo, useState } from "react";
import { TriangleAlert } from "lucide-react";
import { fetchIncidents, fetchMap, type Incident, type Me } from "../../lib/api";
import { BRAND_LABELS } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { navigate } from "../../lib/useHashRoute";
import { LoadingScreen } from "../../ui/LoadingScreen";
import { durationText } from "../dashboard/Dashboard";
import { createBatcher } from "./batcher";
import { cableUrl, connectMap, type CableStatus, type SocketFactory } from "./cable";
import { IncidentFacts } from "./IncidentFacts";
import { MapCanvas } from "./MapCanvas";
import { MapLegend } from "./MapLegend";
import { applyEvents, capNodes, fromSnapshot, summarize, summarizeIncident, type IncidentSummary, type MapEvent, type MapState, type MapTicket } from "./model";
import { assignColors, PALETTE } from "./palette";

const BATCH_MS = 250;
const POLL_MS = 5_000;
const CLOCK_MS = 5_000;
const NODE_LIMIT = 500;
const ALL_BRANDS = ["infinitepay", "jim"];

const STATUS_TEXT: Record<CableStatus, string> = {
  connecting: "Conectando…",
  live: "Ao vivo",
  offline: "Sem conexão ao vivo · atualizando a cada 5 s",
};

// Mapa vivo (playbook §7; ADR 0007, I3, I12 e I13): os tickets abertos agrupados, entrando e saindo em tempo real.
export function LiveMap({ token, me, socket }: { token: string; me: Me; socket?: SocketFactory }) {
  const [state, setState] = useState<MapState>(() => new Map());
  const [snapshotTotal, setSnapshotTotal] = useState<number | null>(null);
  const [status, setStatus] = useState<CableStatus>("connecting");
  const [now, setNow] = useState(() => new Date());
  const [error, setError] = useState<string | null>(null);
  const brands = useMemo(() => (me.role === "ops" ? ALL_BRANDS : me.brands), [me]);
  // Modo Incidente (ADR 0009): os incidentes abertos chegam por polling; os tickets dizem a qual pertencem.
  const loadIncidents = useCallback(() => fetchIncidents(token), [token]);
  const incidentData = usePolling(loadIncidents, POLL_MS).data;
  const incidents = useMemo(() => incidentData?.incidents ?? [], [incidentData]);
  const incidentIds = useMemo(() => new Set(incidents.map((incident) => incident.id)), [incidents]);

  const loadSnapshot = useCallback(async () => {
    try {
      const snapshot = await fetchMap<MapTicket>(token);
      setState(fromSnapshot(snapshot.tickets));
      setSnapshotTotal(snapshot.total);
      setError(null);
    } catch {
      setError("Não foi possível carregar o mapa.");
    }
  }, [token]);

  // Retrato inicial; depois, eventos ao vivo agrupados a cada 250 ms.
  useEffect(() => {
    const first = setTimeout(() => void loadSnapshot(), 0);
    const batcher = createBatcher<MapEvent>((events) => setState((current) => applyEvents(current, events)), BATCH_MS);
    const connection = connectMap({
      url: socket ? "/cable" : cableUrl(),
      token,
      brands,
      onEvent: (event) => batcher.push(event),
      onStatus: (next) => {
        setStatus(next);
        // Ao (re)conectar, o retrato fecha o buraco dos eventos perdidos enquanto estava fora.
        if (next === "live") void loadSnapshot();
      },
      socket,
    });
    return () => {
      clearTimeout(first);
      batcher.stop();
      connection.close();
    };
  }, [token, brands, socket, loadSnapshot]);

  // Sem conexão ao vivo, o retrato vira o tempo real.
  useEffect(() => {
    if (status !== "offline") return;
    const timer = setInterval(() => void loadSnapshot(), POLL_MS);
    return () => clearInterval(timer);
  }, [status, loadSnapshot]);

  // O risco depende da hora: a legenda se atualiza mesmo sem eventos.
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), CLOCK_MS);
    return () => clearInterval(timer);
  }, []);

  // Os tickets de um incidente aberto saem dos grupos em órbita e viram o centro do mapa (ADR 0012, O5).
  const all = useMemo(() => [...state.values()], [state]);
  const tickets = useMemo(() => all.filter((ticket) => !ticket.incident_id || !incidentIds.has(ticket.incident_id)), [all, incidentIds]);
  const clusters = useMemo(() => summarize(tickets, now), [tickets, now]);
  const incidentStats = useMemo(
    () =>
      incidents
        .map((incident) => ({ incident, stats: summarizeIncident(all, incident.id, now) }))
        .filter((entry) => entry.stats.count > 0),
    [incidents, all, now],
  );
  const incidentCount = incidentStats.reduce((sum, entry) => sum + entry.stats.count, 0);

  // Cores estáveis: só recalcula quando o conjunto de grupos muda (estado derivado de renderizações anteriores).
  const clusterKeys = clusters.map((cluster) => cluster.key).sort().join("|");
  const [colorKeys, setColorKeys] = useState("");
  const [colors, setColors] = useState<Map<string, string>>(() => new Map());
  if (clusterKeys !== colorKeys) {
    setColorKeys(clusterKeys);
    setColors(assignColors(clusters.map((cluster) => cluster.key), colors));
  }
  // Zoom num grupo (ADR 0012): se o grupo esvaziar, volta aos grupos em vez de ficar numa tela vazia.
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  if (selectedKey && !clusters.some((cluster) => cluster.key === selectedKey)) setSelectedKey(null);
  useEffect(() => {
    if (!selectedKey) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setSelectedKey(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [selectedKey]);
  const colorFor = (key: string) => colors.get(key) ?? PALETTE[0]!;
  const { visible, hidden } = useMemo(() => capNodes(tickets, NODE_LIMIT), [tickets]);
  const total = snapshotTotal !== null && snapshotTotal > NODE_LIMIT ? Math.max(snapshotTotal, all.length) : all.length;
  const atRiskTotal = clusters.reduce((sum, cluster) => sum + cluster.atRisk, 0) + incidentStats.reduce((sum, entry) => sum + entry.stats.atRisk, 0);

  // Até o retrato chegar (ou falhar), a tela de carregamento: o mapa vazio pareceria "nenhum ticket aberto".
  if (snapshotTotal === null && !error) return <LoadingScreen label="Abrindo o mapa vivo…" />;

  return (
    <div className="flex h-full min-w-0 flex-1 gap-4 p-4">
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden rounded-xl border border-line bg-surface shadow-card">
        <header className="flex min-h-14 items-center gap-4 border-b border-line px-5 py-2.5">
          <h1 className="text-[15px] font-semibold tracking-tight">Mapa vivo</h1>
          <p className="text-sm text-muted tabular">{total} tickets abertos</p>
          {hidden > 0 && <p className="text-xs text-faint">+{hidden} fora do desenho</p>}
          <p className={`ml-auto flex items-center gap-2 text-xs font-medium ${status === "live" ? "text-success" : "text-warning"}`}>
            <span aria-hidden className="relative flex size-2">
              {status === "live" && <span className="absolute inset-0 rounded-full bg-success opacity-60 motion-safe:animate-ping" />}
              <span className={`relative size-2 rounded-full ${status === "live" ? "bg-success" : "bg-warning"}`} />
            </span>
            {STATUS_TEXT[status]}
          </p>
        </header>
        {error && (
          <p role="alert" className="px-5 py-2 text-xs text-danger">
            {error}
          </p>
        )}
        <div className="relative min-h-0 flex-1">
          <MapCanvas
            tickets={visible}
            clusters={clusters}
            colorFor={colorFor}
            incidentCore={incidentCount > 0 ? { incidents: incidentStats.length, count: incidentCount } : null}
            now={now}
            selectedKey={selectedKey}
            onSelect={setSelectedKey}
            onOpen={me.role === "analyst" ? (id) => navigate(`/fila/${id}`) : undefined}
          />
          {incidentStats.length > 0 && <IncidentPanel entries={incidentStats} now={now} />}
        </div>
      </div>

      <aside className="w-72 shrink-0 overflow-y-auto p-5 rounded-xl border border-line bg-surface shadow-card">
        <h2 className="text-xs font-semibold text-text">Grupos</h2>
        {clusters.length === 0 && incidentStats.length === 0 ? (
          <p className="mt-2 text-xs text-faint">Nenhum ticket aberto.</p>
        ) : (
          <ul aria-label="Grupos do mapa" className="mt-3 space-y-0.5">
            {incidentStats.map(({ incident, stats }) => (
              <li key={incident.id} className="flex h-7 items-center gap-2.5 rounded-md px-1.5 text-xs hover:bg-elevated">
                <span aria-hidden className="size-2 shrink-0 rounded-full bg-incident" />
                <span className="min-w-0 flex-1 truncate text-incident-text">incidente · {incident.label}</span>
                <span className="w-6 text-right font-medium text-muted tabular">{stats.count}</span>
              </li>
            ))}
            {clusters.map((cluster) => (
              <li key={cluster.key} className="flex h-7 items-center gap-2.5 rounded-md px-1.5 text-xs hover:bg-elevated">
                <span aria-hidden className="size-2 shrink-0 rounded-full" style={{ background: colorFor(cluster.key) }} />
                <span className="min-w-0 flex-1 truncate text-text">{cluster.label}</span>
                {cluster.atRisk > 0 && <span className="text-[11px] font-medium text-danger">{cluster.atRisk} em risco</span>}
                <span className="w-6 text-right font-medium text-muted tabular">{cluster.count}</span>
              </li>
            ))}
          </ul>
        )}
        {atRiskTotal > 0 && <p className="mt-3 px-1.5 text-xs text-danger">{atRiskTotal} tickets em risco de prazo</p>}

        <MapLegend zoomed={selectedKey !== null} />
      </aside>
    </div>
  );
}

// Detalhes do(s) incidente(s) que estão no centro do mapa. Só informa: nada aqui é clicável (ADR 0012, O5).
function IncidentPanel({ entries, now }: { entries: { incident: Incident; stats: IncidentSummary }[]; now: Date }) {
  return (
    <section
      aria-label="Incidentes abertos"
      className="pointer-events-none absolute bottom-3 left-3 max-h-[60%] w-[22rem] space-y-2 overflow-hidden rounded-xl border border-incident/40 bg-surface/95 p-3.5 shadow-card"
    >
      {entries.map(({ incident, stats }) => {
        const openFor = Math.max(0, Math.round((now.getTime() - Date.parse(incident.opened_at)) / 1000));
        return (
          <article key={incident.id} className="animate-rise space-y-2.5 [&:not(:first-child)]:border-t [&:not(:first-child)]:border-line [&:not(:first-child)]:pt-2.5">
            <header className="flex items-center gap-2 text-xs font-medium text-incident-text">
              <TriangleAlert aria-hidden className="size-4 shrink-0" strokeWidth={2} />
              <span className="min-w-0 truncate">
                Incidente · {BRAND_LABELS[incident.brand] ?? incident.brand} · {incident.label}
              </span>
            </header>
            <p className="text-sm font-semibold text-text">{incident.title}</p>
            <p className="text-[11px] text-muted">
              aberto há {durationText(openFor)}
              {stats.oldestAt && ` · o mais antigo espera há ${durationText(Math.max(0, Math.round((now.getTime() - Date.parse(stats.oldestAt)) / 1000)))}`}
            </p>
            <IncidentFacts stats={stats} />
          </article>
        );
      })}
    </section>
  );
}
