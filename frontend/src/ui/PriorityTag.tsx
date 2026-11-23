// Prioridade P1–P4 (ADR 0004) em mono. P1 e P2 ganham cor; P3 e P4 ficam neutras.
const TONES: Record<string, string> = {
  p1: "border-danger/40 text-danger",
  p2: "border-warning/40 text-warning",
  p3: "border-line-strong text-muted",
  p4: "border-line text-faint",
};

export function PriorityTag({ priority, className = "" }: { priority: string; className?: string }) {
  return (
    <span
      className={`shrink-0 rounded border px-1 font-mono text-[10px] leading-4 uppercase ${TONES[priority] ?? TONES.p3} ${className}`}
    >
      {priority}
    </span>
  );
}
