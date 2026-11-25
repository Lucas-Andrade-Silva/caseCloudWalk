import { ArrowLeft, Bell, LogOut } from "lucide-react";
import { useCallback, type ReactNode } from "react";
import { fetchIncidents, type Me, type Role } from "../lib/api";
import { BRAND_LABELS } from "../lib/format";
import { useHashRoute } from "../lib/useHashRoute";
import { usePolling } from "../lib/usePolling";
import { Avatar } from "../ui/Avatar";
import { BrandMark } from "../ui/BrandMark";

const ROLE_LABELS: Record<Role, string> = { analyst: "Analista", ops: "Operação" };
const INCIDENTS_REFRESH_MS = 10_000;
export const HOME_ROUTE = "/inicio";

interface ShellProps {
  me: Me;
  token: string;
  onSignOut: () => void;
  children: ReactNode;
}

// Sem barra lateral (ADR 0010, H1): uma barra superior fina. Fora da tela inicial, "Voltar" fica no canto
// superior esquerdo e leva de volta aos cards.
export function Shell({ me, token, onSignOut, children }: ShellProps) {
  const route = useHashRoute();
  const onHome = route === HOME_ROUTE;
  const brands = me.role === "ops" ? "Todas as marcas" : me.brands.map((brand) => BRAND_LABELS[brand] ?? brand).join(" · ");
  const loadIncidents = useCallback(() => fetchIncidents(token), [token]);
  const incidents = usePolling(loadIncidents, INCIDENTS_REFRESH_MS).data?.incidents ?? [];
  const incidentHref = me.role === "analyst" ? "#/fila" : "#/mapa";

  return (
    <div className="flex h-screen flex-col bg-bg text-text">
      <header className="shrink-0 border-b border-line bg-bg/80 backdrop-blur">
        <nav aria-label="Principal" className="mx-auto flex h-14 max-w-[1440px] items-center gap-3 px-6">
          {!onHome && (
            <a
              href={`#${HOME_ROUTE}`}
              className="-ml-2 flex h-9 items-center gap-1.5 rounded-lg px-2.5 text-sm font-medium text-muted transition-colors hover:bg-elevated hover:text-text"
            >
              <ArrowLeft aria-hidden className="size-4" strokeWidth={2} />
              Voltar
            </a>
          )}
          <a href={`#${HOME_ROUTE}`} aria-label="helpdesk, ir para o início" className="rounded-md px-1 py-1">
            <BrandMark />
          </a>
          <span className="rounded-lg border border-line px-2.5 py-1 text-xs text-muted">
            {ROLE_LABELS[me.role]}
            {brands && <span className="text-faint"> · {brands}</span>}
          </span>

          <div className="ml-auto flex items-center gap-2">
            <a
              href={incidentHref}
              aria-label={incidents.length > 0 ? `${incidents.length} incidentes abertos` : "Nenhum incidente aberto"}
              className="relative flex size-9 items-center justify-center rounded-lg border border-line text-muted transition-colors hover:bg-elevated hover:text-text"
            >
              <Bell aria-hidden className="size-4" strokeWidth={1.9} />
              {incidents.length > 0 && (
                <span aria-hidden className="absolute -top-1 -right-1 flex size-4 items-center justify-center rounded-full bg-incident text-[10px] font-semibold text-bg">
                  {incidents.length}
                </span>
              )}
            </a>
            <span className="flex items-center gap-2 pl-1">
              <Avatar name={me.name} className="size-8 rounded-full" />
              <span className="text-sm font-medium">{me.name}</span>
            </span>
            <button
              type="button"
              onClick={onSignOut}
              aria-label="Sair"
              title="Sair"
              className="flex size-9 items-center justify-center rounded-lg text-faint transition-colors hover:bg-elevated hover:text-text"
            >
              <LogOut aria-hidden className="size-4" strokeWidth={1.9} />
            </button>
          </div>
        </nav>
      </header>
      <main className="flex min-h-0 flex-1">{children}</main>
    </div>
  );
}
