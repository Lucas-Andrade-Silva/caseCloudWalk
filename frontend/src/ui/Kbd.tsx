import type { ReactNode } from "react";

// Tecla de atalho, em mono, como na documentação de terminal.
export function Kbd({ children, tone = "default" }: { children: ReactNode; tone?: "default" | "on-accent" }) {
  const colors = tone === "on-accent" ? "border-on-accent/25 text-on-accent/80" : "border-line-strong text-muted";
  return (
    <kbd className={`rounded border px-1 font-mono text-[10px] leading-4 font-normal tracking-normal ${colors}`}>{children}</kbd>
  );
}
