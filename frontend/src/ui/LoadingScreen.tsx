import { BrandMark } from "./BrandMark";

// Tela de carregamento: mostrada enquanto os dados de uma tela ainda não chegaram. O desenho lembra o mapa vivo
// (um ponto no centro e dois anéis com pontos em órbita) e para com `prefers-reduced-motion`.
// `full` ocupa a janela inteira (antes de a plataforma abrir); sem ele, preenche só a área da tela.
export function LoadingScreen({ label = "Carregando…", full = false }: { label?: string; full?: boolean }) {
  return (
    <div role="status" aria-live="polite" className={`flex flex-1 flex-col items-center justify-center gap-6 ${full ? "min-h-screen bg-bg" : "h-full min-h-72"}`}>
      <svg aria-hidden="true" viewBox="-60 -60 120 120" className="size-28">
        <circle r="24" fill="none" stroke="var(--color-line-strong)" strokeDasharray="2 5" />
        <circle r="46" fill="none" stroke="var(--color-line-strong)" strokeDasharray="2 5" />
        <g className="map-orbit" style={{ animationDuration: "2.6s" }}>
          <circle cx="24" r="4.5" fill="var(--color-accent)" />
        </g>
        <g className="map-orbit" style={{ animationDuration: "4.4s", animationDirection: "reverse" }}>
          <circle cx="-46" r="5.5" fill="var(--color-info)" />
        </g>
        <circle r="14" fill="var(--color-accent)" opacity="0.15" className="map-pulse" />
        <circle r="5" fill="var(--color-accent)" />
      </svg>
      <div className="flex flex-col items-center gap-2">
        <BrandMark />
        <p className="text-sm text-muted">{label}</p>
      </div>
    </div>
  );
}
