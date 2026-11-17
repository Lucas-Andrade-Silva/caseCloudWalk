import type { ResolutionCode } from "./api";

export type Tone = "neutral" | "warning" | "danger" | "success";

const WARNING_MINUTES = 10;

/** Situação do prazo da primeira resposta humana (ADR 0004, H3). */
export function dueLabel(due: string | null, respondedAt: string | null, now: Date = new Date()): { text: string; tone: Tone } {
  if (respondedAt) return { text: "respondido", tone: "success" };
  if (!due) return { text: "sem prazo", tone: "neutral" };

  const minutes = Math.round((Date.parse(due) - now.getTime()) / 60_000);
  if (minutes < 0) return { text: `atrasou ${-minutes} min`, tone: "danger" };
  return { text: `vence em ${minutes} min`, tone: minutes <= WARNING_MINUTES ? "warning" : "neutral" };
}

export const TONE_CLASSES: Record<Tone, string> = {
  neutral: "text-muted",
  warning: "text-warning",
  danger: "text-danger",
  success: "text-success",
};

export const BRAND_LABELS: Record<string, string> = { infinitepay: "InfinitePay", jim: "JIM" };
export const CHANNEL_LABELS: Record<string, string> = { app_chat: "App", whatsapp: "WhatsApp", email: "E-mail" };
export const SENDER_LABELS: Record<string, string> = { customer: "Cliente", bot: "Agente de IA", analyst: "Analista" };

export const RESOLUTION_LABELS: Record<ResolutionCode, string> = {
  resolved: "Resolvido",
  no_customer_response: "Cliente não respondeu",
  duplicate: "Duplicado",
  forwarded: "Encaminhado",
};

export function customerName(customer: { external_id: string; name: string | null }): string {
  return customer.name ?? customer.external_id;
}

export function timeOfDay(iso: string): string {
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
}

export function shortDate(iso: string): string {
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
}
