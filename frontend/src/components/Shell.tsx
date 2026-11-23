import { Inbox, LayoutDashboard, LogOut, Radar, TriangleAlert, Workflow, type LucideIcon } from "lucide-react";
import { useCallback, type ReactNode } from "react";
import { fetchIncidents, type Me, type Role } from "../lib/api";
import { BRAND_LABELS } from "../lib/format";
import { useHashRoute } from "../lib/useHashRoute";
import { usePolling } from "../lib/usePolling";
import { BrandMark } from "../ui/BrandMark";

const NAVIGATION: Record<Role, { label: string; href: string; icon: LucideIcon }[]> = {
  analyst: [
    { label: "Painel", href: "#/painel", icon: LayoutDashboard },
    { label: "Fila", href: "#/fila", icon: Inbox },
    { label: "Mapa vivo", href: "#/mapa", icon: Radar },
  ],
  ops: [
    { label: "Painel", href: "#/painel", icon: LayoutDashboard },
    { label: "Filas e regras", href: "#/operacao", icon: Workflow },
    { label: "Mapa vivo", href: "#/mapa", icon: Radar },
  ],
};

const ROLE_LABELS: Record<Role, string> = { analyst: "Analista", ops: "Operação" };
const INCIDENTS_REFRESH_MS = 10_000;

interface ShellProps {
  me: Me;
  token: string;
  onSignOut: () => void;
  children: ReactNode;
}

function GroupLabel({ children }: { children: ReactNode }) {
  return <p className="px-3 pt-5 pb-1.5 text-[11px] font-medium text-faint">{children}</p>;
}

export function Shell({ me, token, onSignOut, children }: ShellProps) {
  const route = useHashRoute();
  const brands = me.brands.map((brand) => BRAND_LABELS[brand] ?? brand).join(" · ");
  const loadIncidents = useCallback(() => fetchIncidents(token), [token]);
  const incidents = usePolling(loadIncidents, INCIDENTS_REFRESH_MS).data?.incidents ?? [];
  const incidentHref = me.role === "analyst" ? "#/fila" : "#/mapa";

  return (
    <div className="flex min-h-screen bg-bg text-text">
      <aside className="flex w-60 shrink-0 flex-col border-r border-line bg-surface">
        <div className="flex items-center gap-3 border-b border-line px-4 py-4">
          <span
            aria-hidden
            className="flex size-9 shrink-0 items-center justify-center rounded-full bg-accent text-sm font-semibold text-on-accent"
          >
            {me.name.slice(0, 1).toUpperCase()}
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold leading-tight">{me.name}</p>
            <p className="truncate text-xs leading-tight text-faint">
              {ROLE_LABELS[me.role]}
              {brands && ` · ${brands}`}
            </p>
          </div>
        </div>

        <nav aria-label="Principal" className="flex-1 overflow-y-auto px-2 pb-4">
          <GroupLabel>Geral</GroupLabel>
          <ul className="space-y-0.5">
            {NAVIGATION[me.role].map((item) => {
              const active = route === item.href.slice(1) || route.startsWith(`${item.href.slice(1)}/`);
              const Icon = item.icon;
              return (
                <li key={item.href}>
                  <a
                    href={item.href}
                    aria-current={active ? "page" : undefined}
                    className={`flex h-9 items-center gap-3 rounded-lg px-3 text-sm transition-colors duration-150 ${
                      active ? "bg-elevated font-semibold text-text" : "text-muted hover:bg-elevated hover:text-text"
                    }`}
                  >
                    <Icon aria-hidden className={`size-4 shrink-0 ${active ? "text-accent" : "text-faint"}`} strokeWidth={1.9} />
                    {item.label}
                  </a>
                </li>
              );
            })}
          </ul>

          {incidents.length > 0 && (
            <>
              <GroupLabel>Incidentes abertos</GroupLabel>
              <ul aria-label="Incidentes abertos" className="space-y-0.5">
                {incidents.map((incident) => (
                  <li key={incident.id}>
                    <a
                      href={incidentHref}
                      className="flex items-start gap-2.5 rounded-lg px-3 py-2 text-sm text-muted transition-colors hover:bg-elevated hover:text-text"
                    >
                      <TriangleAlert aria-hidden className="mt-0.5 size-4 shrink-0 text-incident" strokeWidth={1.9} />
                      <span className="min-w-0">
                        <span className="block truncate font-medium text-text">{incident.title}</span>
                        <span className="block text-xs text-faint tabular">
                          {incident.open_tickets} tickets · {BRAND_LABELS[incident.brand] ?? incident.brand}
                        </span>
                      </span>
                    </a>
                  </li>
                ))}
              </ul>
            </>
          )}
        </nav>

        <div className="flex items-center justify-between border-t border-line px-4 py-3">
          <BrandMark />
          <button
            type="button"
            onClick={onSignOut}
            aria-label="Sair"
            title="Sair"
            className="flex size-8 items-center justify-center rounded-lg text-faint transition-colors hover:bg-elevated hover:text-text"
          >
            <LogOut aria-hidden className="size-4" strokeWidth={1.9} />
          </button>
        </div>
      </aside>
      <main className="flex min-w-0 flex-1">{children}</main>
    </div>
  );
}
