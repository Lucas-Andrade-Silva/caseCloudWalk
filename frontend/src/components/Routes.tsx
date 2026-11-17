import { useEffect } from "react";
import type { Me } from "../lib/api";
import { navigate, useHashRoute } from "../lib/useHashRoute";
import { AnalystWorkspace } from "../screens/analyst/AnalystWorkspace";

const HOME: Record<Me["role"], string> = { analyst: "/fila", ops: "/operacao" };

// Escolhe a tela pela rota e pelo papel. Rota desconhecida leva para a tela inicial do papel.
export function Routes({ me, token }: { me: Me; token: string }) {
  const route = useHashRoute();
  const isAnalystQueue = me.role === "analyst" && (route === "/fila" || route.startsWith("/fila/"));
  const known = isAnalystQueue || route === "/mapa" || (me.role === "ops" && route === "/operacao");

  useEffect(() => {
    if (!known) navigate(HOME[me.role]);
  }, [known, me.role]);

  if (isAnalystQueue) return <AnalystWorkspace token={token} />;
  if (route === "/mapa") return <Upcoming text="O mapa vivo entra numa próxima etapa." />;
  if (route === "/operacao") return <Upcoming text="O editor de filas e regras entra numa próxima etapa." />;
  return null;
}

function Upcoming({ text }: { text: string }) {
  return (
    <div className="flex flex-1 items-center justify-center">
      <p className="text-sm text-faint">{text}</p>
    </div>
  );
}
