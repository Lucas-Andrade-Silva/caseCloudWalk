import { useEffect } from "react";
import type { Me } from "../lib/api";
import { isCustomerRoute, navigate, useHashRoute } from "../lib/useHashRoute";
import { AnalystWorkspace } from "../screens/analyst/AnalystWorkspace";
import { Dashboard } from "../screens/dashboard/Dashboard";
import { ResolutionDetail } from "../screens/resolution/ResolutionDetail";
import { AnalystDetail } from "../screens/team/AnalystDetail";
import { TeamDetail } from "../screens/team/TeamDetail";
import { TicketsDetail } from "../screens/tickets/TicketsDetail";
import { LiveMap } from "../screens/map/LiveMap";
import { Home } from "../screens/home/Home";
import { OpsWorkspace } from "../screens/ops/OpsWorkspace";
import { HOME_ROUTE } from "./Shell";

// Escolhe a tela pela rota e pelo papel. Rota desconhecida leva para a tela inicial em cards (ADR 0010).
//
// A rota pública do cliente não é desta área: quem a mostra é o App. Ela pode chegar aqui por um instante
// (uma renderização do polling antes de o hashchange chegar ao App), e redirecioná-la tirava o cliente da
// própria página.
export function Routes({ me, token }: { me: Me; token: string }) {
  const route = useHashRoute();
  const isAnalystQueue = me.role === "analyst" && (route === "/fila" || route.startsWith("/fila/"));
  const isOps = me.role === "ops" && (route === "/operacao" || route === "/operacao/regras");
  const analystId = /^\/analista\/([^/]+)$/.exec(route)?.[1] ?? null;
  const known =
    isCustomerRoute(route) || isAnalystQueue || isOps || analystId !== null || route === "/solucao" || route === "/time" || route === "/tickets" || route === "/mapa" || route === "/painel" || route === HOME_ROUTE;

  useEffect(() => {
    if (!known) navigate(HOME_ROUTE);
  }, [known]);

  if (route === HOME_ROUTE) return <Home token={token} me={me} />;
  if (isAnalystQueue) return <AnalystWorkspace token={token} />;
  if (route === "/mapa") return <LiveMap token={token} me={me} />;
  if (route === "/painel") return <Dashboard token={token} me={me} />;
  if (route === "/solucao") return <ResolutionDetail token={token} />;
  if (route === "/time") return <TeamDetail token={token} />;
  if (route === "/tickets") return <TicketsDetail token={token} />;
  if (analystId) return <AnalystDetail token={token} id={decodeURIComponent(analystId)} />;
  if (isOps) return <OpsWorkspace token={token} route={route} />;
  return null;
}
