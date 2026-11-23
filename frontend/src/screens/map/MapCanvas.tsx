import {
  forceCollide,
  forceManyBody,
  forceSimulation,
  forceX,
  forceY,
  type ForceX,
  type ForceY,
  type Simulation,
  type SimulationNodeDatum,
} from "d3-force";
import { useEffect, useRef, useState } from "react";
import { BRAND_LABELS, CHANNEL_LABELS, dueLabel } from "../../lib/format";
import { atRisk, nodeRadius, type ClusterSummary, type MapTicket } from "./model";

interface Node extends SimulationNodeDatum {
  id: string;
  ticket: MapTicket;
  /** Quando entrou no mapa (ms do relógio de animação), para a entrada crescer em vez de surgir. */
  born: number;
}

const ENTRY_MS = 450;
const easeOut = (t: number) => 1 - (1 - t) ** 3;

const MODE_LABELS: Record<string, string> = {
  ai: "com a IA",
  pending_human: "esperando humano",
  human: "com humano",
};

// Mesmos valores dos tokens de index.css (o canvas não lê variáveis CSS a cada quadro).
const COLORS = { label: "#a8a6a1", count: "#8f8d88", pending: "#f0883e", human: "#24d332", risk: "#ff6b5a" };
const MONO = '"IBM Plex Mono", ui-monospace, monospace';

// Desenha o grafo do mapa vivo em canvas, com a física do d3-force (ADR 0007, I3). Os grupos ficam em volta de
// um círculo; os nós de cada grupo são puxados para o centro dele e se empurram para não se sobrepor.
export function MapCanvas({
  tickets,
  clusters,
  colorFor,
  onOpen,
}: {
  tickets: MapTicket[];
  clusters: ClusterSummary[];
  colorFor: (clusterKey: string) => string;
  onOpen?: (id: string) => void;
}) {
  const colorRef = useRef(colorFor);
  useEffect(() => {
    colorRef.current = colorFor;
  }, [colorFor]);
  const wrapper = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const nodes = useRef<Map<string, Node>>(new Map());
  const simulation = useRef<Simulation<Node, undefined> | null>(null);
  const centers = useRef<Map<string, { x: number; y: number; label: string; count: number }>>(new Map());
  const size = useRef({ width: 800, height: 600 });
  // Alvo de cada nó: o centro do grupo dele (lido na hora, nunca durante a renderização).
  const targetX = (node: Node) => centers.current.get(node.ticket.cluster.key)?.x ?? size.current.width / 2;
  const targetY = (node: Node) => centers.current.get(node.ticket.cluster.key)?.y ?? size.current.height / 2;
  const [hover, setHover] = useState<{ node: Node; left: number; top: number } | null>(null);

  // Física: criada uma vez; os nós mantêm a posição entre atualizações (o mapa se move, não pisca).
  useEffect(() => {
    const sim = forceSimulation<Node>([])
      .force("charge", forceManyBody<Node>().strength(-4))
      .force("collide", forceCollide<Node>((node) => nodeRadius(node.ticket.priority) + 1.5))
      .force("x", forceX<Node>(targetX).strength(0.14))
      .force("y", forceY<Node>(targetY).strength(0.14))
      .alphaDecay(0.025)
      .stop();
    simulation.current = sim;
    return () => {
      sim.stop();
    };
  }, []);

  // Tamanho do canvas acompanha o espaço disponível, com nitidez em telas de alta densidade.
  useEffect(() => {
    const element = wrapper.current;
    if (!element || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(([entry]) => {
      if (!entry || !canvas.current) return;
      const { width, height } = entry.contentRect;
      size.current = { width, height };
      const ratio = window.devicePixelRatio || 1;
      canvas.current.width = Math.round(width * ratio);
      canvas.current.height = Math.round(height * ratio);
      layoutCenters.current();
      simulation.current?.alpha(0.8);
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  // Centros dos grupos em volta de um círculo, na ordem de tamanho; recalculados quando os grupos ou o tamanho
  // da área mudam.
  const clustersRef = useRef(clusters);
  const layoutCenters = useRef(() => {
    const list = clustersRef.current;
    const { width, height } = size.current;
    // Elipse que usa a largura e a altura reais: em telas estreitas, um círculo apertaria os grupos uns contra os outros.
    const radiusX = width * 0.33;
    const radiusY = height * 0.33;
    const next = new Map<string, { x: number; y: number; label: string; count: number }>();
    list.forEach((cluster, index) => {
      const angle = list.length === 1 ? 0 : (index / list.length) * Math.PI * 2 - Math.PI / 2;
      const spread = list.length === 1 ? 0 : 1;
      next.set(cluster.key, {
        x: width / 2 + Math.cos(angle) * radiusX * spread,
        y: height / 2 + Math.sin(angle) * radiusY * spread,
        label: cluster.label,
        count: cluster.count,
      });
    });
    centers.current = next;
    // O d3 guarda o alvo de cada nó quando a força inicializa: sem reler, os nós seguiriam os centros antigos.
    const sim = simulation.current;
    if (sim) {
      (sim.force("x") as ForceX<Node> | undefined)?.x(targetX);
      (sim.force("y") as ForceY<Node> | undefined)?.y(targetY);
    }
  });

  useEffect(() => {
    clustersRef.current = clusters;
    layoutCenters.current();
    simulation.current?.alpha(0.8);
  }, [clusters]);

  // Entra, muda e sai: reaproveita o nó (e a posição) de quem já estava no mapa.
  useEffect(() => {
    const previous = nodes.current;
    const next = new Map<string, Node>();
    for (const ticket of tickets) {
      const existing = previous.get(ticket.id);
      if (existing) {
        existing.ticket = ticket;
        next.set(ticket.id, existing);
      } else {
        const center = centers.current.get(ticket.cluster.key);
        next.set(ticket.id, {
          id: ticket.id,
          ticket,
          born: performance.now(),
          x: (center?.x ?? size.current.width / 2) + (Math.random() - 0.5) * 40,
          y: (center?.y ?? size.current.height / 2) + (Math.random() - 0.5) * 40,
        });
      }
    }
    nodes.current = next;
    simulation.current?.nodes([...next.values()]).alpha(0.4);
  }, [tickets]);

  // Laço de desenho: avança a física e redesenha; o pulso de risco anima só se o sistema permitir movimento.
  useEffect(() => {
    const context = canvas.current?.getContext("2d");
    if (!context) return;
    const reduceMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    let frame = 0;

    const draw = (time: number) => {
      const sim = simulation.current;
      const ratio = window.devicePixelRatio || 1;
      const { width, height } = size.current;
      if (sim && sim.alpha() > sim.alphaMin()) {
        sim.tick();
        // Nenhum nó sai da área visível (o empurra-empurra de grupos grandes os expulsaria pelas bordas).
        for (const node of nodes.current.values()) {
          const r = nodeRadius(node.ticket.priority) + 2;
          node.x = Math.min(Math.max(node.x ?? 0, r), width - r);
          node.y = Math.min(Math.max(node.y ?? 0, r + 24), height - r);
        }
      }
      const now = new Date();
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      context.clearRect(0, 0, width, height);

      // Rótulo acima do nó mais alto do grupo e no meio dos nós de verdade (o grupo se desloca com os empurrões).
      const extents = new Map<string, { top: number; sumX: number; count: number }>();
      for (const node of nodes.current.values()) {
        const key = node.ticket.cluster.key;
        const extent = extents.get(key) ?? { top: Infinity, sumX: 0, count: 0 };
        extent.top = Math.min(extent.top, (node.y ?? 0) - nodeRadius(node.ticket.priority));
        extent.sumX += node.x ?? 0;
        extent.count++;
        extents.set(key, extent);
      }
      context.textAlign = "center";
      for (const [key, center] of centers.current) {
        const extent = extents.get(key);
        const top = Math.max(extent?.top ?? center.y, 30);
        context.fillStyle = COLORS.label;
        context.font = `500 12px ${MONO}`;
        // O texto inteiro fica dentro da área, mesmo nos grupos da borda.
        const half = context.measureText(center.label).width / 2 + 4;
        const x = Math.min(Math.max(extent ? extent.sumX / extent.count : center.x, half), width - half);
        context.fillText(center.label, x, top - 20);
        context.fillStyle = COLORS.count;
        context.font = `11px ${MONO}`;
        context.fillText(String(center.count), x, top - 7);
      }

      const pulse = reduceMotion ? 0.6 : 0.5 + 0.5 * Math.sin(time / 300);
      for (const node of nodes.current.values()) {
        const { ticket } = node;
        const x = node.x ?? 0;
        const y = node.y ?? 0;
        const age = reduceMotion ? 1 : Math.min((time - node.born) / ENTRY_MS, 1);
        const r = nodeRadius(ticket.priority) * (age < 1 ? easeOut(Math.max(age, 0)) : 1);
        if (age < 1) {
          // Chegada: um anel que se abre e some, para o olho achar o ticket novo.
          context.beginPath();
          context.arc(x, y, nodeRadius(ticket.priority) + 14 * easeOut(Math.max(age, 0)), 0, Math.PI * 2);
          context.strokeStyle = colorRef.current(ticket.cluster.key);
          context.globalAlpha = 0.6 * (1 - age);
          context.lineWidth = 1.25;
          context.stroke();
          context.globalAlpha = 1;
        }

        if (atRisk(ticket, now)) {
          context.beginPath();
          context.arc(x, y, r + 3 + pulse * 4, 0, Math.PI * 2);
          context.strokeStyle = COLORS.risk;
          context.globalAlpha = 0.25 + 0.5 * (1 - pulse);
          context.lineWidth = 1.5;
          context.stroke();
          context.globalAlpha = 1;
        }

        context.beginPath();
        context.arc(x, y, r, 0, Math.PI * 2);
        context.fillStyle = colorRef.current(ticket.cluster.key);
        context.globalAlpha = hover?.node.id === node.id ? 1 : 0.85;
        context.fill();
        context.globalAlpha = 1;

        if (ticket.mode === "pending_human" || ticket.mode === "human") {
          context.lineWidth = 1.75;
          context.strokeStyle = ticket.mode === "human" ? COLORS.human : COLORS.pending;
          context.stroke();
        }
      }
      frame = requestAnimationFrame(draw);
    };
    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [hover]);

  // Chamado só em eventos do mouse; já devolve a posição da dica, limitada à área do mapa.
  function nodeAt(clientX: number, clientY: number): { node: Node; left: number; top: number } | null {
    const rect = canvas.current?.getBoundingClientRect();
    if (!rect) return null;
    const x = clientX - rect.left;
    const y = clientY - rect.top;
    let best: Node | null = null;
    let bestDistance = Infinity;
    for (const node of nodes.current.values()) {
      const distance = Math.hypot((node.x ?? 0) - x, (node.y ?? 0) - y);
      if (distance <= nodeRadius(node.ticket.priority) + 3 && distance < bestDistance) {
        best = node;
        bestDistance = distance;
      }
    }
    return best ? { node: best, left: Math.min(x + 14, size.current.width - 232), top: Math.max(y - 10, 8) } : null;
  }

  const hovered = hover?.node.ticket;
  const due = hovered ? dueLabel(hovered.first_response_due_at, hovered.first_human_response_at) : null;

  return (
    <div
      ref={wrapper}
      className="relative h-full w-full overflow-hidden bg-bg bg-[radial-gradient(circle,var(--color-line)_1px,transparent_1px)] bg-size-[24px_24px]"
    >
      <canvas
        ref={canvas}
        role="img"
        aria-label={`Mapa com ${tickets.length} tickets em ${clusters.length} grupos`}
        className={`h-full w-full ${hover && onOpen ? "cursor-pointer" : ""}`}
        onMouseMove={(event) => setHover(nodeAt(event.clientX, event.clientY))}
        onMouseLeave={() => setHover(null)}
        onClick={(event) => {
          const hit = nodeAt(event.clientX, event.clientY);
          if (hit && onOpen) onOpen(hit.node.id);
        }}
      />
      {hovered && hover && (
        <div
          className="pointer-events-none absolute z-10 w-60 rounded-lg border border-line-strong bg-surface/95 p-3 text-xs shadow-[0_12px_32px_-8px_rgb(0_0_0/0.8)] backdrop-blur-sm"
          style={{ left: hover.left, top: hover.top }}
        >
          <p className="font-medium text-text">
            {hovered.cluster.label} · <span className="font-mono uppercase">{hovered.priority}</span>
          </p>
          <p className="mt-1 text-muted">
            {BRAND_LABELS[hovered.brand] ?? hovered.brand} · {CHANNEL_LABELS[hovered.channel] ?? hovered.channel} ·{" "}
            {MODE_LABELS[hovered.mode] ?? hovered.mode}
          </p>
          {hovered.queue && <p className="font-mono text-[11px] text-faint">fila {hovered.queue}</p>}
          {hovered.mode !== "ai" && due && <p className="font-mono text-[11px] text-faint">{due.text}</p>}
          {onOpen && <p className="mt-1.5 text-accent">Clique para abrir</p>}
        </div>
      )}
    </div>
  );
}
