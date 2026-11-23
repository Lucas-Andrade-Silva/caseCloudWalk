import { BRAND_LABELS } from "../lib/format";

// Ponto de cor da marca do ticket (InfinitePay ou JIM). As cores são provisórias (ADR 0009).
export function BrandDot({ brand }: { brand: string }) {
  return (
    <span
      title={BRAND_LABELS[brand] ?? brand}
      aria-hidden
      className={`size-1.5 shrink-0 rounded-full ${brand === "jim" ? "bg-brand-jim" : "bg-brand-infinitepay"}`}
    />
  );
}
