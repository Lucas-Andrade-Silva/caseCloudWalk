import { QueuesEditor } from "./QueuesEditor";
import { RulesEditor } from "./RulesEditor";

const TABS = [
  { label: "Filas e equipes", route: "/operacao" },
  { label: "Regras", route: "/operacao/regras" },
];

// Área da operação (ADR 0007, I10 e I11): filas e equipes de um lado, regras de roteamento do outro.
export function OpsWorkspace({ token, route }: { token: string; route: string }) {
  const onRules = route === "/operacao/regras";

  return (
    <div className="flex h-full min-w-0 flex-1 flex-col">
      <nav aria-label="Operação" className="flex gap-1 border-b border-line bg-surface px-6 pt-3">
        {TABS.map((tab) => {
          const active = tab.route === route;
          return (
            <a
              key={tab.route}
              href={`#${tab.route}`}
              aria-current={active ? "page" : undefined}
              className={`-mb-px border-b-2 px-3 pb-2.5 text-sm ${
                active ? "border-accent text-text" : "border-transparent text-muted hover:text-text"
              }`}
            >
              {tab.label}
            </a>
          );
        })}
      </nav>
      {onRules ? <RulesEditor token={token} /> : <QueuesEditor token={token} />}
    </div>
  );
}
