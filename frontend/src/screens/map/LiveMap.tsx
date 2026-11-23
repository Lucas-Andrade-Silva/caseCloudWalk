import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchMap, type Me } from "../../lib/api";
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

  const tickets = useMemo(() => [...state.values()], [state]);
  const clusters = useMemo(() => summarize(tickets, now), [tickets, now]);

  // Cores estáveis: só recalcula quando o conjunto de grupos muda (estado derivado de renderizações anteriores).
  const clusterKeys = clusters.map((cluster) => cluster.key).sort().join("|");
  const [colorKeys, setColorKeys] = useState("");
  const [colors, setColors] = useState<Map<string, string>>(() => new Map());
  if (clusterKeys !== colorKeys) {
    setColorKeys(clusterKeys);
    setColors(assignColors(clusters.map((cluster) => cluster.key), colors));
  }
  const colorFor = (key: string) => colors.get(key) ?? PALETTE[0]!;
  const { visible, hidden } = useMemo(() => capNodes(tickets, NODE_LIMIT), [tickets]);
  const total = snapshotTotal !== null && snapshotTotal > NODE_LIMIT ? Math.max(snapshotTotal, tickets.length) : tickets.length;
  const atRiskTotal = clusters.reduce((sum, cluster) => sum + cluster.atRisk, 0);

  return (
    <div className="flex h-screen min-w-0 flex-1">
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex min-h-14 items-center gap-4 border-b border-line px-5 py-2.5">
          <h1 className="text-[15px] font-semibold tracking-tight">Mapa vivo</h1>
          <p className="font-mono text-xs text-muted tabular">{total} tickets abertos</p>
          {hidden > 0 && <p className="font-mono text-xs text-faint">+{hidden} fora do desenho</p>}
          <p className={`ml-auto flex items-center gap-2 font-mono text-xs ${status === "live" ? "text-success" : "text-warning"}`}>
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
        <div className="min-h-0 flex-1">
          <MapCanvas
            tickets={visible}
            clusters={clusters}
            colorFor={colorFor}
            onOpen={me.role === "analyst" ? (id) => navigate(`/fila/${id}`) : undefined}
          />
        </div>
      </div>

      <aside className="w-72 shrink-0 overflow-y-auto border-l border-line p-5">
        <h2 className="text-xs font-semibold text-text">Grupos</h2>
        {clusters.length === 0 ? (
          <p className="mt-2 text-xs text-faint">Nenhum ticket aberto.</p>
        ) : (
          <ul aria-label="Grupos do mapa" className="mt-3 space-y-0.5">
            {clusters.map((cluster) => (
              <li key={cluster.key} className="flex h-7 items-center gap-2.5 rounded-md px-1.5 text-xs hover:bg-surface">
                <span aria-hidden className="size-2 shrink-0 rounded-full" style={{ background: colorFor(cluster.key) }} />
                <span className="min-w-0 flex-1 truncate text-text">{cluster.label}</span>
                {cluster.atRisk > 0 && <span className="font-mono text-[11px] text-danger">{cluster.atRisk} em risco</span>}
                <span className="w-6 text-right font-mono text-muted tabular">{cluster.count}</span>
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
            Pulso <span className="text-danger">vermelho</span>: prazo humano perto de vencer, ou agente calado há 20 s
          </li>
        </ul>
      </aside>
    </div>
  );
}
