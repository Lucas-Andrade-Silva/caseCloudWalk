// Prioridade P1–P4 (ADR 0004) como selo. P1 e P2 ganham cor; P3 e P4 ficam neutras.
const TONES: Record<string, string> = {
  p1: "bg-danger/10 text-danger",
  p2: "bg-warning/10 text-warning",
  p3: "bg-elevated text-muted",
  p4: "bg-elevated text-faint",
};

export function PriorityTag({ priority, className = "" }: { priority: string; className?: string }) {
  return (
    <span
      className={`shrink-0 rounded-full px-1.5 text-[10px] leading-4 font-semibold uppercase ${TONES[priority] ?? TONES.p3} ${className}`}
    >
      {priority}
    </span>
  );
}
