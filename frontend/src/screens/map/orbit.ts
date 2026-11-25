// Geometria do mapa vivo em órbita (ADR 0012). Funções puras: o SVG só desenha o que sai daqui.
//
// Visão geral: cada grupo de tickets é um círculo que gira numa de três órbitas em volta do centro; o círculo
// cresce com a quantidade de tickets. Zoom num grupo: os tickets dele giram em órbitas em volta do grupo.

import { nodeRadius, type MapTicket } from "./model";

/** Raios das órbitas da visão geral, em unidades do desenho. */
export const ORBIT_RADII = [95, 185, 275];
export const BUBBLE_MIN = 14;
export const BUBBLE_MAX = 40;
const BUBBLE_GAP = 14;
/** Quanto da circunferência de uma órbita os círculos podem ocupar antes de sobrar para a próxima. */
const ORBIT_FILL = 0.9;

/** Raio do círculo de um grupo: cresce com a raiz da quantidade (a área segue o número de tickets). */
export function bubbleRadius(count: number): number {
  return Math.min(BUBBLE_MAX, BUBBLE_MIN + 5.2 * Math.sqrt(Math.max(count, 1)));
}

/** Ponto de uma órbita, com o ângulo em radianos (0 à direita, crescendo no sentido horário na tela). */
export function position(orbit: number, angle: number): [number, number] {
  return [Math.cos(angle) * orbit, Math.sin(angle) * orbit];
}

export interface ClusterSlot {
  key: string;
  ring: number;
  orbit: number;
  angle: number;
  radius: number;
}

/**
 * Reparte os grupos (já ordenados do maior para o menor) pelas órbitas, um de cada vez, começando pela de dentro,
 * para o desenho usar as três órbitas mesmo com poucos grupos. Uma órbita cheia passa o grupo para a próxima que
 * tenha espaço; se nenhuma tiver, ele vai para a menos ocupada. Em cada órbita os círculos ficam espaçados por igual.
 */
export function layoutClusters(clusters: { key: string; count: number }[]): ClusterSlot[] {
  const rings: { key: string; radius: number }[][] = ORBIT_RADII.map(() => []);
  const used = ORBIT_RADII.map(() => 0);
  const room = ORBIT_RADII.map((orbit) => 2 * Math.PI * orbit * ORBIT_FILL);
  clusters.forEach((cluster, index) => {
    const radius = bubbleRadius(cluster.count);
    const need = 2 * radius + BUBBLE_GAP;
    const order = ORBIT_RADII.map((_, offset) => (index + offset) % ORBIT_RADII.length);
    const ring =
      order.find((candidate) => used[candidate]! + need <= room[candidate]!) ??
      order.reduce((best, candidate) => (used[candidate]! / room[candidate]! < used[best]! / room[best]! ? candidate : best));
    rings[ring]!.push({ key: cluster.key, radius });
    used[ring]! += need;
  });

  return rings.flatMap((members, index) =>
    members.map((member, position) => ({
      key: member.key,
      ring: index,
      orbit: ORBIT_RADII[index]!,
      // Começa no alto e escalona cada órbita, para os círculos de órbitas vizinhas não alinharem.
      angle: -Math.PI / 2 + index * 0.9 + (position * 2 * Math.PI) / members.length,
      radius: member.radius,
    })),
  );
}

/** Raio do grupo no zoom, no centro, e a primeira órbita de tickets em volta dele. */
export const ZOOM_CORE = 30;
/** No zoom os tickets são desenhados bem maiores que no mapa antigo: são o alvo do clique. */
const TICKET_SCALE = 2;

/** Raio de um ticket no zoom, pela prioridade. */
export function ticketRadius(priority: string): number {
  return nodeRadius(priority) * TICKET_SCALE;
}

const FIRST_ORBIT = 80;
const ORBIT_STEP = 46;
/** Espaço de um ticket numa órbita: o maior ponto (P1) mais folga. */
const TICKET_SPACE = 2 * ticketRadius("p1") + 8;

export interface TicketSlot {
  id: string;
  ring: number;
  orbit: number;
  angle: number;
}

/** Tickets de um grupo em órbitas em volta do centro; os mais urgentes e antigos ficam mais perto. */
export function layoutTickets(tickets: MapTicket[]): { slots: TicketSlot[]; rings: number; extent: number } {
  const sorted = [...tickets].sort(
    (a, b) => a.priority.localeCompare(b.priority) || a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id),
  );
  const slots: TicketSlot[] = [];
  let ring = 0;
  for (let start = 0; start < sorted.length; ring++) {
    const orbit = FIRST_ORBIT + ring * ORBIT_STEP;
    const members = sorted.slice(start, start + Math.max(1, Math.floor((2 * Math.PI * orbit) / TICKET_SPACE)));
    members.forEach((member, index) => {
      slots.push({ id: member.id, ring, orbit, angle: ring * 0.5 + (index * 2 * Math.PI) / members.length });
    });
    start += members.length;
  }
  const lastOrbit = FIRST_ORBIT + Math.max(ring - 1, 0) * ORBIT_STEP;
  return { slots, rings: ring, extent: lastOrbit + ticketRadius("p1") + 16 };
}
