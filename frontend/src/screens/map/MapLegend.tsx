import type { ReactNode } from "react";

// "Como ler" do mapa vivo (ADR 0012): o desenho de cada marca ao lado de um nome curto e do detalhe, só com o que
// vale para a tela atual (grupos ou zoom). Os desenhos usam as mesmas cores e anéis do mapa.

const ORANGE = "var(--color-warning)";
const GREEN = "var(--color-accent)";
const INCIDENT = "var(--color-incident)";
const DANGER = "var(--color-danger)";
const FILL = "var(--color-muted)";

function Swatch({ children }: { children: ReactNode }) {
  return (
    <svg aria-hidden="true" viewBox="-14 -14 28 28" className="size-7 shrink-0">
      {children}
    </svg>
  );
}

const Group = () => <circle r="8" fill={FILL} fillOpacity="0.25" stroke={FILL} strokeWidth="1.5" />;
const Dot = ({ r = 5 }: { r?: number }) => <circle r={r} fill={FILL} fillOpacity="0.9" />;

const OVERVIEW: { title: string; detail: string; swatch: ReactNode }[] = [
  { title: "Grupo", detail: "cresce com os tickets", swatch: <Group /> },
  {
    title: "Incidente",
    detail: "anel laranja tracejado",
    swatch: (
      <>
        <Group />
        <circle r="12" fill="none" stroke={INCIDENT} strokeWidth="1.5" strokeDasharray="3 3" />
      </>
    ),
  },
  {
    title: "Prazo em risco",
    detail: "anel vermelho pulsando",
    swatch: (
      <>
        <Group />
        <circle r="12" fill="none" stroke={DANGER} strokeWidth="1.5" opacity="0.8" />
      </>
    ),
  },
];

const ZOOMED: { title: string; detail: string; swatch: ReactNode }[] = [
  {
    title: "Prioridade",
    detail: "tamanho do ponto, P1 maior",
    swatch: (
      <>
        <circle cx="-8" r="3" fill={FILL} />
        <circle cx="-1" r="4.5" fill={FILL} />
        <circle cx="9" r="6" fill={FILL} />
      </>
    ),
  },
  { title: "Esperando humano", detail: "anel laranja", swatch: <><Dot r={6} /><circle r="6" fill="none" stroke={ORANGE} strokeWidth="2" /></> },
  { title: "Com humano", detail: "anel verde", swatch: <><Dot r={6} /><circle r="6" fill="none" stroke={GREEN} strokeWidth="2" /></> },
  { title: "Com a IA", detail: "sem anel", swatch: <Dot r={6} /> },
  {
    title: "Incidente",
    detail: "anel laranja tracejado",
    swatch: (
      <>
        <Dot r={5} />
        <circle r="10" fill="none" stroke={INCIDENT} strokeWidth="1.5" strokeDasharray="3 3" />
      </>
    ),
  },
  {
    title: "Prazo em risco",
    detail: "anel vermelho pulsando",
    swatch: (
      <>
        <Dot r={5} />
        <circle r="10" fill="none" stroke={DANGER} strokeWidth="1.5" opacity="0.8" />
      </>
    ),
  },
];

export function MapLegend({ zoomed }: { zoomed: boolean }) {
  return (
    <section aria-label="Como ler" className="mt-8">
      <h2 className="text-xs font-semibold text-text">Como ler</h2>
      <ul aria-label="Como ler o mapa" className="mt-3 space-y-2.5">
        {(zoomed ? ZOOMED : OVERVIEW).map((item) => (
          <li key={item.title} className="flex items-center gap-3">
            <Swatch>{item.swatch}</Swatch>
            <span className="min-w-0">
              <span className="block text-xs text-text">{item.title}</span>
              <span className="block text-[11px] text-faint">{item.detail}</span>
            </span>
          </li>
        ))}
      </ul>
      <p className="mt-4 text-[11px] text-faint">{zoomed ? "Esc ou “Todos os grupos” volta." : "Clique num círculo para ampliar."}</p>
    </section>
  );
}
