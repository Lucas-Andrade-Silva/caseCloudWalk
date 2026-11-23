import { useCallback, useEffect, useMemo, useState } from "react";
import { TriangleAlert } from "lucide-react";
import { fetchIncidents, fetchMap, type Me } from "../../lib/api";
import { BRAND_LABELS } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";
import { navigate } from "../../lib/useHashRoute";
import { createBatcher } from "./batcher";
import { cableUrl, connectMap, type CableStatus, type SocketFactory } from "./cable";
import { MapCanvas } from "./MapCanvas";
import { applyEvents, capNodes, fromSnapshot, summarize, type MapEvent, type MapState, type MapTicket } from "./model";
import { assignColors, PALETTE } from "./palette";

const BATCH_MS = 250;
const POLL_MS = 5_000;
const CLOCK_MS = 5_000;
const NODE_LIMIT = 500;
const ALL_BRANDS = ["infinitepay", "jim"];
// Laranja da CloudWalk (token --color-incident): reservado ao Modo Incidente, fora da paleta dos grupos.
const INCIDENT_COLOR = "#e25813";

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

  // Os tickets de um incidente aberto saem do grupo de origem e formam o grupo do incidente: no mapa, eles se
  // desprendem e se juntam, e o pico fica visível na hora.
  const incidentLabels = useMemo(() => new Map(incidents.map((incident) => [incident.id, incident.label])), [incidents]);
  const tickets = useMemo(
    () =>
      [...state.values()].map((ticket) => {
        const label = ticket.incident_id ? incidentLabels.get(ticket.incident_id) : undefined;
        return label ? { ...ticket, cluster: { key: `incidente:${ticket.incident_id}`, label: `incidente · ${label}` } } : ticket;
      }),
    [state, incidentLabels],
  );
  const clusters = useMemo(() => summarize(tickets, now), [tickets, now]);

  // Cores estáveis: só recalcula quando o conjunto de grupos muda (estado derivado de renderizações anteriores).
  const clusterKeys = clusters.map((cluster) => cluster.key).sort().join("|");
  const [colorKeys, setColorKeys] = useState("");
  const [colors, setColors] = useState<Map<string, string>>(() => new Map());
  if (clusterKeys !== colorKeys) {
    setColorKeys(clusterKeys);
    setColors(assignColors(clusters.map((cluster) => cluster.key), colors));
  }
  const colorFor = (key: string) => (key.startsWith("incidente:") ? INCIDENT_COLOR : (colors.get(key) ?? PALETTE[0]!));
  const { visible, hidden } = useMemo(() => capNodes(tickets, NODE_LIMIT), [tickets]);
  const total = snapshotTotal !== null && snapshotTotal > NODE_LIMIT ? Math.max(snapshotTotal, tickets.length) : tickets.length;
  const atRiskTotal = clusters.reduce((sum, cluster) => sum + cluster.atRisk, 0);

  return (
    <div className="flex h-screen min-w-0 flex-1 gap-4 p-4">
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
        {incidents.length > 0 && (
          <section aria-label="Incidentes abertos" className="border-b border-incident/30 bg-incident/6 px-5 py-2.5">
            <ul className="space-y-1">
              {incidents.map((incident) => (
                <li key={incident.id} className="flex animate-rise items-center gap-3 text-sm">
                  <TriangleAlert aria-hidden className="size-4 shrink-0 text-incident-text" strokeWidth={2} />
                  <span className="text-xs font-medium text-incident-text">
                    Incidente · {BRAND_LABELS[incident.brand] ?? incident.brand} · {incident.label}
                  </span>
                  <span className="min-w-0 truncate font-semibold text-text">{incident.title}</span>
                  <span className="ml-auto shrink-0 text-xs text-muted tabular">{incident.open_tickets} tickets</span>
                </li>
              ))}
            </ul>
          </section>
        )}
        {error && (
          <p role="alert" className="px-5 py-2 text-xs text-danger">
            {error}
          </p>
        )}
        <div className="min-h-0 flex-1">
          <MapCanvas
            tickets={visible}
            clusters={clusters}
            colorFor={colorFor}
            incidentIds={incidentIds}
            onOpen={me.role === "analyst" ? (id) => navigate(`/fila/${id}`) : undefined}
          />
        </div>
      </div>

      <aside className="w-72 shrink-0 overflow-y-auto p-5 rounded-xl border border-line bg-surface shadow-card">
        <h2 className="text-xs font-semibold text-text">Grupos</h2>
        {clusters.length === 0 ? (
          <p className="mt-2 text-xs text-faint">Nenhum ticket aberto.</p>
        ) : (
          <ul aria-label="Grupos do mapa" className="mt-3 space-y-0.5">
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

        <h2 className="mt-8 text-xs font-semibold text-text">Como ler</h2>
        <ul className="mt-3 space-y-1.5 text-[11px] leading-relaxed text-faint">
          <li>Cor: o grupo (primeira tag; sem tag, a fila)</li>
          <li>Tamanho: a prioridade (P1 maior)</li>
          <li>
            Anel: <span className="text-warning">esperando humano</span> ou <span className="text-success">com humano</span>; sem anel, com a IA
          </li>
          <li>
            Anel <span className="text-incident-text">laranja tracejado</span>: ticket de um incidente aberto
          </li>
          <li>
            Pulso <span className="text-danger">vermelho</span>: prazo humano perto de vencer, ou agente calado há 20 s
          </li>
        </ul>
      </aside>
    </div>
  );
}
