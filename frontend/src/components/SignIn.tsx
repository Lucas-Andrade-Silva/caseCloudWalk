import { ArrowRight } from "lucide-react";
import { useState, type FormEvent } from "react";
import { BrandMark } from "../ui/BrandMark";
import { Button } from "../ui/Button";
import { fieldClass, labelClass } from "../ui/field";

// Pessoas sintéticas dos seeds de desenvolvimento (backend/db/seeds.rb). Nunca existem em produção.
const DEV_PEOPLE = [
  { name: "Ana", role: "analista", token: "dev-analyst-ana" },
  { name: "Bruno", role: "analista", token: "dev-analyst-bruno" },
  { name: "Carla", role: "analista", token: "dev-analyst-carla" },
  { name: "Olivia", role: "operação", token: "dev-ops-olivia" },
];

interface SignInProps {
  onSubmit: (token: string) => void;
  error: string | null;
  busy: boolean;
}

export function SignIn({ onSubmit, error, busy }: SignInProps) {
  const [token, setToken] = useState("");

  function submit(event: FormEvent) {
    event.preventDefault();
    if (token.trim()) onSubmit(token.trim());
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-bg px-4 text-text">
      <div className="w-full max-w-sm animate-rise">
        <BrandMark size="lg" />
        <h1 className="mt-8 text-2xl font-semibold tracking-tight">Entrar</h1>
        <p className="mt-1.5 text-sm text-muted">Atendimento AI-first da InfinitePay e da JIM.</p>

        <form onSubmit={submit} className="mt-8 space-y-3">
          <label htmlFor="token" className={labelClass}>
            Token de acesso
          </label>
          <input
            id="token"
            type="password"
            autoComplete="off"
            value={token}
            onChange={(event) => setToken(event.target.value)}
            className={`${fieldClass} h-10 font-mono`}
          />
          {error && (
            <p role="alert" className="text-xs text-danger">
              {error}
            </p>
          )}
          <Button type="submit" variant="primary" busy={busy} disabled={!token.trim()} className="h-10 w-full">
            Entrar
          </Button>
        </form>

        {import.meta.env.DEV && (
          <section className="mt-10 border-t border-line pt-5" aria-label="Pessoas de teste">
            <p className="font-mono text-[11px] text-faint">desenvolvimento · entrar como</p>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {DEV_PEOPLE.map((person) => (
                <button
                  key={person.token}
                  type="button"
                  disabled={busy}
                  onClick={() => onSubmit(person.token)}
                  className="group flex h-10 items-center justify-between rounded-md border border-line bg-surface px-3 text-left text-sm text-text transition-colors duration-150 hover:border-line-strong hover:bg-elevated disabled:opacity-40"
                >
                  <span>
                    {person.name}
                    <span className="ml-2 text-xs text-faint">{person.role}</span>
                  </span>
                  <ArrowRight aria-hidden className="size-3.5 text-faint transition-colors group-hover:text-accent" />
                </button>
              ))}
            </div>
          </section>
        )}
      </div>
    </main>
  );
}
