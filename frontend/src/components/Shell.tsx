import type { ReactNode } from "react";
import type { Me, Role } from "../lib/api";
import { useHashRoute } from "../lib/useHashRoute";

const NAVIGATION: Record<Role, { label: string; href: string }[]> = {
  analyst: [
    { label: "Fila", href: "#/fila" },
    { label: "Mapa vivo", href: "#/mapa" },
  ],
  ops: [
    { label: "Filas e regras", href: "#/operacao" },
    { label: "Mapa vivo", href: "#/mapa" },
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
  const brands = me.brands.length > 0 ? ` · ${me.brands.join(", ")}` : "";

  return (
    <div className="flex min-h-screen bg-bg text-text">
      <aside className="flex w-56 shrink-0 flex-col border-r border-line bg-surface">
        <div className="px-4 py-4">
          <p className="text-xs font-medium tracking-widest text-muted uppercase">Help Desk</p>
        </div>
        <nav aria-label="Principal" className="flex-1 px-2">
          {NAVIGATION[me.role].map((item) => {
            const active = route === item.href.slice(1) || route.startsWith(`${item.href.slice(1)}/`);
            return (
              <a
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`flex h-8 items-center rounded-md px-2 text-sm hover:bg-elevated hover:text-text ${
                  active ? "bg-elevated text-text" : "text-muted"
                }`}
              >
                {item.label}
              </a>
            );
          })}
        </nav>
        <div className="border-t border-line px-4 py-3">
          <p className="text-sm">{me.name}</p>
          <p className="text-xs text-muted">
            {ROLE_LABELS[me.role]}
            {brands}
          </p>
          <button type="button" onClick={onSignOut} className="mt-2 text-xs text-muted hover:text-text">
            Sair
          </button>
        </div>
      </aside>
      <main className="flex min-w-0 flex-1">{children}</main>
    </div>
  );
}
