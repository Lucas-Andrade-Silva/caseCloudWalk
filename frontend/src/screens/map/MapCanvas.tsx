import { ArrowLeft } from "lucide-react";
import { useEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent, type MouseEvent } from "react";
import { BRAND_LABELS, CHANNEL_LABELS, dueLabel } from "../../lib/format";
import { atRisk, type ClusterSummary, type MapTicket } from "./model";
import { bubbleRadius, layoutClusters, layoutTickets, ORBIT_RADII, position, ticketRadius, ZOOM_CORE } from "./orbit";

const MODE_LABELS: Record<string, string> = {
  ai: "com a IA",
  pending_human: "esperando humano",
  human: "com humano",
};

const MODE_RING: Record<string, string> = { pending_human: "var(--color-warning)", human: "var(--color-accent)" };
const OVERVIEW_BOX = "-440 -330 880 660";
const LABEL_MAX = 20;

const plural = (count: number) => `${count} ${count === 1 ? "ticket" : "tickets"}`;
const short = (label: string) => (label.length > LABEL_MAX ? `${label.slice(0, LABEL_MAX - 1)}…` : label);

// Cada órbita gira num ritmo e, de uma para a outra, em sentido contrário. O ângulo sai do relógio (e não de uma
// animação CSS por elemento): assim a órbita e o conteúdo dos círculos, que gira ao contrário para o texto ficar de
// pé, nunca saem de compasso, mesmo montados em momentos diferentes.
function spin(ring: number, base: number, step: number) {
  return { "data-spin": base + ring * step, "data-dir": ring % 2 === 1 ? -1 : 1 };
}

const place = (orbit: number, angle: number): CSSProperties => {
  const [x, y] = position(orbit, angle);
  return { transform: `translate(${x}px, ${y}px)` };
};

type Hover = { kind: "cluster"; cluster: ClusterSummary; left: number; top: number } | { kind: "ticket"; ticket: MapTicket; left: number; top: number };

// Mapa vivo em órbita (ADR 0012): cada grupo é um círculo que cresce com os tickets e gira em volta do centro;
// clicar num grupo dá zoom e abre os tickets dele, também girando.
export function MapCanvas({
  tickets,
  clusters,
  colorFor,
  incidentCore,
  now,
  selectedKey,
  onSelect,
  onOpen,
}: {
  tickets: MapTicket[];
  clusters: ClusterSummary[];
  colorFor: (clusterKey: string) => string;
  /** Incidentes abertos: viram o centro do mapa (não clicável), no lugar do ponto central. */
  incidentCore?: { incidents: number; count: number } | null;
  now: Date;
  selectedKey: string | null;
  onSelect: (clusterKey: string | null) => void;
  onOpen?: (id: string) => void;
}) {
  const [hover, setHover] = useState<Hover | null>(null);
  const svg = useRef<SVGSVGElement>(null);
  const selected = selectedKey ? (clusters.find((cluster) => cluster.key === selectedKey) ?? null) : null;
  const slots = useMemo(() => layoutClusters(clusters), [clusters]);
  const members = useMemo(
    () => (selected ? tickets.filter((ticket) => ticket.cluster.key === selected.key) : []),
    [tickets, selected],
  );
  const zoom = useMemo(() => layoutTickets(members), [members]);
  const byId = useMemo(() => new Map(tickets.map((ticket) => [ticket.id, ticket])), [tickets]);

  const extent = Math.max(zoom.extent, 130);
  const viewBox = selected ? `${-extent} ${-extent} ${extent * 2} ${extent * 2}` : OVERVIEW_BOX;

  // Gira as órbitas: cada uma vira o ângulo do relógio; quem tem data-upright gira ao contrário da órbita dele.
  // Com "reduzir movimento" no sistema, nada gira.
  useEffect(() => {
    const root = svg.current;
    if (!root || window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
    let frame = 0;
    const tick = (time: number) => {
      for (const ring of root.querySelectorAll<SVGGElement>("[data-spin]")) {
        const angle = (((time / 1000 / Number(ring.dataset.spin)) * 360 * Number(ring.dataset.dir)) % 360) || 0;
        ring.style.transform = `rotate(${angle}deg)`;
        for (const content of ring.querySelectorAll<SVGGElement>("[data-upright]")) content.style.transform = `rotate(${-angle}deg)`;
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);

  // Um só tratador para o SVG inteiro: descobre pelo alvo se o mouse está num grupo ou num ticket.
  function pointer(event: MouseEvent<SVGSVGElement>) {
    const box = event.currentTarget.getBoundingClientRect();
    const left = Math.min(event.clientX - box.left + 14, box.width - 244);
    const top = Math.max(event.clientY - box.top - 10, 8);
    const target = event.target as Element;
    const ticketId = target.closest("[data-ticket]")?.getAttribute("data-ticket");
    const clusterKey = target.closest("[data-cluster]")?.getAttribute("data-cluster");
    return { left, top, ticket: ticketId ? byId.get(ticketId) : undefined, cluster: clusterKey ? clusters.find((item) => item.key === clusterKey) : undefined };
  }

  function onMove(event: MouseEvent<SVGSVGElement>) {
    const { left, top, ticket, cluster } = pointer(event);
    if (ticket) setHover({ kind: "ticket", ticket, left, top });
    else if (cluster) setHover({ kind: "cluster", cluster, left, top });
    else setHover(null);
  }

  function onClick(event: MouseEvent<SVGSVGElement>) {
    const { ticket, cluster } = pointer(event);
    setHover(null);
    if (ticket && onOpen) onOpen(ticket.id);
    else if (cluster && !selected) onSelect(cluster.key);
  }

  function onKey(event: KeyboardEvent<SVGGElement>, key: string) {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    onSelect(key);
  }

  const showTip = hover && (hover.kind === "cluster" ? !selected : true);

  return (
    <div className="relative h-full w-full overflow-hidden bg-bg bg-[radial-gradient(circle,var(--color-line)_1px,transparent_1px)] bg-size-[24px_24px]">
      <svg
        ref={svg}
        role="group"
        aria-label={`Mapa com ${tickets.length} tickets em ${clusters.length} grupos`}
        viewBox={viewBox}
        className="size-full"
        onMouseMove={onMove}
        onMouseLeave={() => setHover(null)}
        onClick={onClick}
      >
        {selected ? (
          <g key={selected.key} className="map-zoom-in">
            {Array.from({ length: zoom.rings }, (_, ring) => (
              <circle key={ring} r={zoom.slots.find((slot) => slot.ring === ring)!.orbit} fill="none" stroke="var(--color-line)" strokeDasharray="2 6" />
            ))}
            {Array.from({ length: zoom.rings }, (_, ring) => (
              <g key={ring} className="orbit-spin" {...spin(ring, 150, 40)}>
                {zoom.slots
                  .filter((slot) => slot.ring === ring)
                  .map((slot) => {
                    const ticket = byId.get(slot.id)!;
                    const radius = ticketRadius(ticket.priority);
                    return (
                      <g key={slot.id} data-ticket={slot.id} className={onOpen ? "cursor-pointer" : ""} style={{ ...place(slot.orbit, slot.angle), transition: "transform 0.7s ease" }}>
                        <g className="ticket-in">
                          {/* Área de clique maior que o desenho: o ticket é fácil de acertar mesmo girando. */}
                          <circle r={radius + 10} fill="transparent" />
                          {atRisk(ticket, now) && <circle r={radius + 3} fill="none" stroke="var(--color-danger)" strokeWidth="1.5" className="risk-ring" />}
                          <circle
                            r={radius}
                            fill={colorFor(ticket.cluster.key)}
                            fillOpacity={hover?.kind === "ticket" && hover.ticket.id === slot.id ? 1 : 0.88}
                            stroke={MODE_RING[ticket.mode] ?? "none"}
                            strokeWidth="3"
                          />
                        </g>
                      </g>
                    );
                  })}
              </g>
            ))}
            <circle r={ZOOM_CORE + 8} fill={colorFor(selected.key)} fillOpacity="0.08" className="map-pulse" />
            <circle r={ZOOM_CORE} fill={colorFor(selected.key)} fillOpacity="0.22" stroke={colorFor(selected.key)} strokeWidth="2" />
            <text textAnchor="middle" dy=".35em" fontSize="22" fontWeight="700" fill="var(--color-text)">
              {selected.count}
            </text>
          </g>
        ) : (
          <g className="map-zoom-out">
            {ORBIT_RADII.map((radius) => (
              <circle key={radius} r={radius} fill="none" stroke="var(--color-line-strong)" strokeDasharray="2 7" />
            ))}
            {incidentCore ? (
              <IncidentCore incidents={incidentCore.incidents} count={incidentCore.count} />
            ) : (
              <>
                <circle r="26" fill="var(--color-accent)" opacity="0.14" className="map-pulse" />
                <circle r="9" fill="var(--color-accent)" />
              </>
            )}
            {clusters.length === 0 && (
              <text y="60" textAnchor="middle" fontSize="15" fill="var(--color-faint)">
                Nenhum ticket aberto
              </text>
            )}
            {ORBIT_RADII.map((_, ring) => (
              <g key={ring} className="orbit-spin" {...spin(ring, 170, 50)}>
                {slots
                  .filter((slot) => slot.ring === ring)
                  .map((slot) => {
                    const cluster = clusters.find((item) => item.key === slot.key)!;
                    const color = colorFor(cluster.key);
                    const radius = bubbleRadius(cluster.count);
                    return (
                      <g key={slot.key} style={{ ...place(slot.orbit, slot.angle), transition: "transform 0.7s ease" }}>
                        <g className="orbit-upright" data-upright>
                          <g
                            role="button"
                            tabIndex={0}
                            aria-label={`${cluster.label}, ${plural(cluster.count)}`}
                            data-cluster={cluster.key}
                            className="map-bubble cursor-pointer"
                            onKeyDown={(event) => onKey(event, cluster.key)}
                          >
                            {cluster.atRisk > 0 && <circle r={radius + 4} fill="none" stroke="var(--color-danger)" strokeWidth="2" className="risk-ring" />}
                            <circle
                              r={radius}
                              fill={color}
                              fillOpacity="0.2"
                              stroke={color}
                              strokeWidth="2"
                              style={{ transition: "r 0.6s ease, fill-opacity 0.2s" }}
                              className="map-bubble-body"
                            />
                          </g>
                          {/* O texto fica fora do botão: o nome do botão já diz grupo e quantidade (axe: label-content-name-mismatch). */}
                          <text aria-hidden textAnchor="middle" dy=".35em" fontSize="19" fontWeight="700" fill="var(--color-text)" pointerEvents="none">
                            {cluster.count}
                          </text>
                          <text aria-hidden y={radius + 17} textAnchor="middle" fontSize="13" fontWeight="500" fill="var(--color-muted)" pointerEvents="none">
                            {short(cluster.label)}
                          </text>
                        </g>
                      </g>
                    );
                  })}
              </g>
            ))}
          </g>
        )}
      </svg>

      {selected && (
        <div className="absolute top-3 left-3 flex items-center gap-3">
          <button
            type="button"
            onClick={() => onSelect(null)}
            className="flex h-9 items-center gap-1.5 rounded-lg border border-line bg-surface px-3 text-sm font-medium text-muted transition-colors hover:bg-elevated hover:text-text"
          >
            <ArrowLeft aria-hidden className="size-4" strokeWidth={2} />
            Todos os grupos
          </button>
          <p className="flex items-center gap-2 text-sm font-semibold">
            <span aria-hidden className="size-2.5 rounded-full" style={{ background: colorFor(selected.key) }} />
            <span>
              {selected.label} · {plural(selected.count)}
            </span>
          </p>
        </div>
      )}

      {showTip && (
        <div
          className="pointer-events-none absolute z-10 w-60 rounded-lg border border-line bg-surface p-3 text-xs shadow-card"
          style={{ left: hover.left, top: hover.top }}
        >
          {hover.kind === "cluster" ? (
            <>
              <p className="font-medium text-text">{hover.cluster.label}</p>
              <p className="mt-1 text-muted">{plural(hover.cluster.count)}</p>
              {hover.cluster.atRisk > 0 && <p className="text-[11px] text-danger-ink">{hover.cluster.atRisk} em risco de prazo</p>}
              <p className="mt-1.5 text-accent">Clique para ver os tickets</p>
            </>
          ) : (
            <TicketTip ticket={hover.ticket} canOpen={Boolean(onOpen)} />
          )}
        </div>
      )}
    </div>
  );
}

// Centro do mapa em Modo Incidente (ADR 0012, O5): só informa, não recebe clique nem foco. Os detalhes ficam no
// painel "Incidentes abertos".
function IncidentCore({ incidents, count }: { incidents: number; count: number }) {
  const name = incidents === 1 ? "Incidente aberto" : `${incidents} incidentes abertos`;
  return (
    <g role="img" aria-label={`${name}, ${plural(count)}`} pointerEvents="none">
      <circle r="46" fill="var(--color-incident)" opacity="0.16" className="map-pulse" />
      <circle r="54" fill="none" stroke="var(--color-incident)" strokeWidth="1.5" strokeDasharray="4 4" className="dash-spin" />
      <circle r="46" fill="var(--color-incident)" fillOpacity="0.22" stroke="var(--color-incident)" strokeWidth="2" />
      <text aria-hidden y="-18" textAnchor="middle" fontSize="10" fontWeight="700" letterSpacing="1.5" fill="var(--color-incident-text)">
        {incidents === 1 ? "INCIDENTE" : `${incidents} INCIDENTES`}
      </text>
      <text aria-hidden y="9" textAnchor="middle" fontSize="30" fontWeight="700" fill="var(--color-text)">
        {count}
      </text>
      <text aria-hidden y="25" textAnchor="middle" fontSize="11" fill="var(--color-muted)">
        {count === 1 ? "ticket" : "tickets"}
      </text>
    </g>
  );
}

function TicketTip({ ticket, canOpen }: { ticket: MapTicket; canOpen: boolean }) {
  const due = dueLabel(ticket.first_response_due_at, ticket.first_human_response_at);
  return (
    <>
      <p className="font-medium text-text">
        {ticket.cluster.label} · <span className="font-mono uppercase">{ticket.priority}</span>
      </p>
      <p className="mt-1 text-muted">
        {BRAND_LABELS[ticket.brand] ?? ticket.brand} · {CHANNEL_LABELS[ticket.channel] ?? ticket.channel} · {MODE_LABELS[ticket.mode] ?? ticket.mode}
      </p>
      {ticket.queue && <p className="text-[11px] text-faint">fila {ticket.queue}</p>}
      {ticket.mode !== "ai" && <p className="text-[11px] text-faint">{due.text}</p>}
      {canOpen && <p className="mt-1.5 text-accent">Clique para abrir</p>}
    </>
  );
}
