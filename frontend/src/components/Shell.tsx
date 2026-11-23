import { Inbox, LogOut, Radar, Workflow, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import type { Me, Role } from "../lib/api";
import { BRAND_LABELS } from "../lib/format";
import { useHashRoute } from "../lib/useHashRoute";
import { BrandMark } from "../ui/BrandMark";

const NAVIGATION: Record<Role, { label: string; href: string; icon: LucideIcon }[]> = {
  analyst: [
    { label: "Fila", href: "#/fila", icon: Inbox },
    { label: "Mapa vivo", href: "#/mapa", icon: Radar },
  ],
  ops: [
    { label: "Filas e regras", href: "#/operacao", icon: Workflow },
    { label: "Mapa vivo", href: "#/mapa", icon: Radar },
  ],
};

const ROLE_LABELS: Record<Role, string> = { analyst: "Analista", ops: "Operação" };

interface ShellProps {
  me: Me;
  onSignOut: () => void;
  children: ReactNode;
}

export function Shell({ me, onSignOut, children }: ShellProps) {
  const route = useHashRoute();
  const brands = me.brands.map((brand) => BRAND_LABELS[brand] ?? brand).join(" · ");

  return (
    <div className="flex min-h-screen bg-bg text-text">
      <aside className="flex w-52 shrink-0 flex-col border-r border-line bg-bg">
        <div className="flex h-12 items-center px-4">
          <BrandMark />
        </div>
        <nav aria-label="Principal" className="flex-1 space-y-0.5 px-2 pt-2">
          {NAVIGATION[me.role].map((item) => {
            const active = route === item.href.slice(1) || route.startsWith(`${item.href.slice(1)}/`);
            const Icon = item.icon;
            return (
              <a
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`group flex h-8 items-center gap-2.5 rounded-md px-2 text-sm transition-colors duration-150 ${
                  active ? "bg-elevated text-text" : "text-muted hover:bg-surface hover:text-text"
                }`}
              >
                <Icon
                  aria-hidden
                  className={`size-4 shrink-0 ${active ? "text-accent" : "text-faint group-hover:text-muted"}`}
                  strokeWidth={1.75}
                />
                {item.label}
              </a>
            );
          })}
        </nav>
        <div className="flex items-center gap-2.5 border-t border-line px-3 py-3">
          <span
            aria-hidden
            className="flex size-7 shrink-0 items-center justify-center rounded-md bg-elevated font-mono text-xs text-accent"
          >
            {me.name.slice(0, 1).toUpperCase()}
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm leading-tight">{me.name}</p>
            <p className="truncate text-[11px] leading-tight text-faint">
              {ROLE_LABELS[me.role]}
              {brands && ` · ${brands}`}
            </p>
          </div>
          <button
            type="button"
            onClick={onSignOut}
            aria-label="Sair"
            title="Sair"
            className="flex size-7 shrink-0 items-center justify-center rounded-md text-faint transition-colors hover:bg-elevated hover:text-text"
          >
            <LogOut aria-hidden className="size-3.5" strokeWidth={1.75} />
          </button>
        </div>
      </aside>
      <main className="flex min-w-0 flex-1">{children}</main>
    </div>
  );
}
