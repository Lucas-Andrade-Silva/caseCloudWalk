import { useEffect } from "react";
import type { Me } from "../lib/api";
import { isCustomerRoute, navigate, useHashRoute } from "../lib/useHashRoute";
import { AnalystWorkspace } from "../screens/analyst/AnalystWorkspace";
import { OpsWorkspace } from "../screens/ops/OpsWorkspace";

const HOME: Record<Me["role"], string> = { analyst: "/fila", ops: "/operacao" };

// Escolhe a tela pela rota e pelo papel. Rota desconhecida leva para a tela inicial do papel.
//
// A rota pública do cliente não é desta área: quem a mostra é o App. Ela pode chegar aqui por um instante
// (uma renderização do polling antes de o hashchange chegar ao App), e redirecioná-la tirava o cliente da
// própria página.
export function Routes({ me, token }: { me: Me; token: string }) {
  const route = useHashRoute();
  const isAnalystQueue = me.role === "analyst" && (route === "/fila" || route.startsWith("/fila/"));
  const isOps = me.role === "ops" && (route === "/operacao" || route === "/operacao/regras");
  const known = isCustomerRoute(route) || isAnalystQueue || isOps || route === "/mapa";

  useEffect(() => {
    if (!known) navigate(HOME[me.role]);
  }, [known, me.role]);

  if (isAnalystQueue) return <AnalystWorkspace token={token} />;
  if (route === "/mapa") return <Upcoming text="O mapa vivo entra numa próxima etapa." />;
  if (isOps) return <OpsWorkspace token={token} route={route} />;
  return null;
}

function Upcoming({ text }: { text: string }) {
  return (
    <div className="flex flex-1 items-center justify-center">
      <p className="text-sm text-faint">{text}</p>
    </div>
  );
}
