import { useState, type FormEvent } from "react";

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
    <main className="flex min-h-screen items-center justify-center bg-bg px-4">
      <div className="w-full max-w-sm">
        <p className="text-xs font-medium tracking-widest text-muted uppercase">Help Desk</p>
        <h1 className="mt-1 text-lg font-semibold text-text">Entrar</h1>

        <form onSubmit={submit} className="mt-6 space-y-3">
          <label htmlFor="token" className="block text-xs text-muted">
            Token de acesso
          </label>
          <input
            id="token"
            type="password"
            autoComplete="off"
            value={token}
            onChange={(event) => setToken(event.target.value)}
            className="h-9 w-full rounded-md border border-line bg-surface px-3 text-sm text-text outline-none focus:border-accent"
          />
          {error && (
            <p role="alert" className="text-xs text-danger">
              {error}
            </p>
          )}
          <button
            type="submit"
            disabled={busy || !token.trim()}
            className="h-9 w-full rounded-md bg-accent text-sm font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-40"
          >
            Entrar
          </button>
        </form>

        {import.meta.env.DEV && (
          <section className="mt-8 border-t border-line pt-4" aria-label="Pessoas de teste">
            <p className="text-xs text-muted">Desenvolvimento: entrar como</p>
            <div className="mt-2 grid grid-cols-2 gap-2">
              {DEV_PEOPLE.map((person) => (
                <button
                  key={person.token}
                  type="button"
                  disabled={busy}
                  onClick={() => onSubmit(person.token)}
                  className="flex h-9 items-center justify-between rounded-md border border-line bg-surface px-3 text-left text-sm text-text hover:bg-elevated disabled:opacity-40"
                >
                  <span>{person.name}</span>
                  <span className="text-xs text-muted">{person.role}</span>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>
    </main>
  );
}
