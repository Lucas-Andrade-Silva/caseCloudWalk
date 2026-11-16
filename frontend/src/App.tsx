import { useEffect, useState } from "react";
import { Shell } from "./components/Shell";
import { SignIn } from "./components/SignIn";
import { ApiError, fetchMe, type Me } from "./lib/api";
import { clearToken, loadToken, saveToken } from "./lib/session";

type State =
  | { kind: "checking" }
  | { kind: "signed-out"; error: string | null; busy: boolean }
  | { kind: "signed-in"; me: Me };

function explain(error: unknown): string {
  if (error instanceof ApiError && error.status === 401) return "Token inválido.";
  if (error instanceof ApiError && error.status === 403) return "Este token não dá acesso à interface.";
  return "Não foi possível falar com a plataforma. Tente de novo.";
}

export default function App() {
  const [state, setState] = useState<State>(() =>
    loadToken() ? { kind: "checking" } : { kind: "signed-out", error: null, busy: false },
  );

  async function signIn(token: string) {
    try {
      const me = await fetchMe(token);
      saveToken(token);
      setState({ kind: "signed-in", me });
    } catch (error) {
      clearToken();
      setState({ kind: "signed-out", error: explain(error), busy: false });
    }
  }

  // Sessão guardada: confere o token ao abrir. O estado só muda na resposta, e uma resposta que chega
  // depois de o efeito ser desfeito (StrictMode monta duas vezes) é ignorada.
  useEffect(() => {
    const stored = loadToken();
    if (!stored) return;

    let active = true;
    fetchMe(stored).then(
      (me) => {
        if (active) setState({ kind: "signed-in", me });
      },
      (error: unknown) => {
        if (!active) return;
        clearToken();
        setState({ kind: "signed-out", error: explain(error), busy: false });
      },
    );
    return () => {
      active = false;
    };
  }, []);

  if (state.kind === "checking") {
    return <div className="min-h-screen bg-bg" aria-busy="true" />;
  }

  if (state.kind === "signed-out") {
    return (
      <SignIn
        error={state.error}
        busy={state.busy}
        onSubmit={(token) => {
          setState({ kind: "signed-out", error: null, busy: true });
          void signIn(token);
        }}
      />
    );
  }

  return (
    <Shell
      me={state.me}
      onSignOut={() => {
        clearToken();
        setState({ kind: "signed-out", error: null, busy: false });
      }}
    />
  );
}
