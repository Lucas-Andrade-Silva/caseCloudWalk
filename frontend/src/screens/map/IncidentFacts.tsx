import type { IncidentSummary } from "./model";

function Fact({ name, value, tone = "text-text" }: { name: string; value: number; tone?: string }) {
  return (
    <div role="group" aria-label={name} className="rounded-lg bg-elevated px-2.5 py-1.5">
      <p className="text-[11px] text-muted">{name}</p>
      <p className={`text-base font-semibold tabular ${tone}`}>{value}</p>
    </div>
  );
}

// Os números de um incidente aberto (ADR 0012, O5), no painel do mapa e no card da tela inicial. Só informa.
export function IncidentFacts({ stats, className = "grid-cols-3" }: { stats: IncidentSummary; className?: string }) {
  return (
    <div className={`grid gap-1.5 ${className}`}>
      <Fact name="Tickets abertos" value={stats.count} />
      <Fact name="Esperando humano" value={stats.pendingHuman} tone={stats.pendingHuman > 0 ? "text-warning-ink" : "text-text"} />
      <Fact name="Com humano" value={stats.human} />
      <Fact name="Com a IA" value={stats.ai} />
      <Fact name="Em risco de prazo" value={stats.atRisk} tone={stats.atRisk > 0 ? "text-danger-ink" : "text-text"} />
      <Fact name="Urgentes" value={stats.urgent} tone={stats.urgent > 0 ? "text-danger-ink" : "text-text"} />
    </div>
  );
}
