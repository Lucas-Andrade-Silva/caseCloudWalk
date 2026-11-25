// Situação da operação em uma palavra (card "Modo Incidente", ADR 0012, O6). Função pura sobre os tickets abertos.
import { atRisk, type MapTicket } from "../map/model";

export type Level = "estavel" | "atencao" | "critico";

const WORDS: Record<Level, string> = { estavel: "Estável", atencao: "Atenção", critico: "Crítico" };
const HOUR_MS = 60 * 60_000;
/** A partir daqui a entrada da última hora já é um pico, mesmo sem incidente. */
const BUSY_HOUR = 10;
const CRITICAL_RISK = 10;

export function situation(tickets: MapTicket[], incidents: number, now: Date) {
  const risky = tickets.filter((ticket) => atRisk(ticket, now)).length;
  const lastHour = tickets.filter((ticket) => now.getTime() - Date.parse(ticket.created_at) <= HOUR_MS).length;

  const level: Level =
    (incidents > 0 && risky > 0) || risky >= CRITICAL_RISK ? "critico" : incidents > 0 || risky > 0 || lastHour >= BUSY_HOUR ? "atencao" : "estavel";

  const reason =
    level === "critico"
      ? `${risky} ${risky === 1 ? "ticket perto" : "tickets perto"} de estourar o prazo${incidents > 0 ? " com incidente aberto" : ""}.`
      : level === "atencao"
        ? incidents > 0
          ? "Incidente aberto: um pico de tickets parecidos."
          : risky > 0
            ? `${risky} ${risky === 1 ? "ticket perto" : "tickets perto"} de estourar o prazo.`
            : `${lastHour} tickets entraram na última hora.`
        : "Sem incidente e nenhum prazo em risco.";

  return { level, word: WORDS[level], reason, risky, lastHour };
}
