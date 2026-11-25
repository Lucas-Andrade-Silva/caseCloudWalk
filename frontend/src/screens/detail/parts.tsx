import type { ReactNode } from "react";

// Blocos das telas de detalhe dos cards (ADR 0011): página rolável, seção, número com legenda, lista de barras
// e gráfico por dia. Todo gráfico tem a tabela com os valores reais para leitor de tela.

export const dayLabel = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

export const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`;

export function DetailPage({ title, subtitle, lead, children }: { title: string; subtitle: string; lead?: ReactNode; children: ReactNode }) {
  return (
    // Rolável e focável: quem usa só o teclado rola a página com as setas (axe: scrollable-region-focusable).
    <div role="region" aria-label={title} tabIndex={0} className="h-full flex-1 overflow-y-auto focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent">
      <div className="mx-auto max-w-[1100px] space-y-5 p-6">
        <header className="flex items-center gap-4">
          {lead}
          <div className="min-w-0">
            <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
            <p className="mt-1 text-xs text-faint">{subtitle}</p>
          </div>
        </header>
        {children}
      </div>
    </div>
  );
}

export function Message({ children }: { children: ReactNode }) {
  return <div className="flex flex-1 items-center justify-center p-8 text-sm text-faint">{children}</div>;
}

export function Section({ title, label, children, className = "" }: { title: string; label?: string; children: ReactNode; className?: string }) {
  return (
    <section aria-label={label ?? title} className={`rounded-2xl border border-line bg-surface p-5 ${className}`}>
      <h2 className="text-sm font-medium text-muted">{title}</h2>
      {children}
    </section>
  );
}

export function Stat({ name, value, detail, tone = "text-text" }: { name: string; value: ReactNode; detail?: ReactNode; tone?: string }) {
  return (
    <div role="group" aria-label={name} className="rounded-2xl border border-line bg-surface p-5">
      <p className="text-sm text-muted">{name}</p>
      <p className={`mt-2 text-3xl font-semibold tracking-tight tabular ${tone}`}>{value}</p>
      {detail && <p className="mt-1.5 text-xs text-faint">{detail}</p>}
    </div>
  );
}

export interface BarItem {
  key: string;
  label: string;
  value: number;
  display: ReactNode;
  color?: string;
}

/** Lista de barras horizontais: o rótulo, a barra proporcional ao maior valor e o número. */
export function BarList({ label, items, empty }: { label: string; items: BarItem[]; empty?: string }) {
  const max = Math.max(...items.map((item) => item.value), 1);
  if (items.length === 0) return <p className="mt-4 text-sm text-faint">{empty ?? "Nada por aqui ainda."}</p>;
  return (
    <ul aria-label={label} className="mt-4 space-y-3.5">
      {items.map((item) => (
        <li key={item.key} className="grid grid-cols-[8.5rem_1fr_auto] items-center gap-3 text-sm">
          <span className="truncate text-muted">{item.label}</span>
          <span aria-hidden className="h-2 overflow-hidden rounded-full bg-elevated">
            <span className="block h-full rounded-full" style={{ width: `${(item.value / max) * 100}%`, background: item.color ?? "var(--color-accent)" }} />
          </span>
          <span className="min-w-8 text-right font-medium tabular">{item.display}</span>
        </li>
      ))}
    </ul>
  );
}

export interface DaySeries {
  name: string;
  color: string;
}

/** Colunas por dia, com uma barra por série. `null` (dia sem dado) não desenha barra. */
export function DayChart({
  label,
  series,
  days,
  format = String,
}: {
  label: string;
  series: DaySeries[];
  days: { date: string; values: (number | null)[] }[];
  format?: (value: number) => string;
}) {
  const max = Math.max(...days.flatMap((day) => day.values.map((value) => value ?? 0)), 1);
  return (
    <>
      {series.length > 1 && (
        <p aria-hidden className="mt-3 flex gap-4 text-xs text-muted">
          {series.map((item) => (
            <span key={item.name} className="flex items-center gap-1.5">
              <span className="size-2 rounded-sm" style={{ background: item.color }} />
              {item.name}
            </span>
          ))}
        </p>
      )}
      <div aria-hidden className="mt-4 grid grid-cols-7 gap-3">
        {days.map((day) => (
          <div key={day.date} className="flex flex-col items-center gap-2">
            <div className="flex h-40 w-full items-stretch justify-center gap-1.5 pt-5">
              {day.values.map((value, index) => {
                const height = ((value ?? 0) / max) * 100;
                return (
                  <span key={index} className="relative block max-w-7 flex-1">
                    <span className="absolute inset-x-0 bottom-0 rounded-t-md" style={{ height: `${height}%`, minHeight: value ? 4 : 0, background: series[index]!.color }} />
                    {value ? (
                      <span
                        className="absolute left-1/2 -translate-x-1/2 text-[10px] whitespace-nowrap text-muted tabular"
                        style={{ bottom: `calc(${height}% + 4px)` }}
                      >
                        {format(value)}
                      </span>
                    ) : null}
                  </span>
                );
              })}
            </div>
            <span className="text-[11px] text-faint tabular">{dayLabel(day.date)}</span>
          </div>
        ))}
      </div>
      <table aria-label={label} className="sr-only">
        <thead>
          <tr>
            <th>Dia</th>
            {series.map((item) => (
              <th key={item.name}>{item.name}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {days.map((day) => (
            <tr key={day.date}>
              <td>{dayLabel(day.date)}</td>
              {day.values.map((value, index) => (
                <td key={index}>{value === null ? "—" : format(value)}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}
