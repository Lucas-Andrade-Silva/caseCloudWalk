// Token de acesso guardado no navegador. Dados sintéticos e tokens de desenvolvimento apenas (ADR 0007).
const KEY = "helpdesk.token";

export function loadToken(): string | null {
  try {
    return window.localStorage.getItem(KEY);
  } catch {
    return null;
  }
}

export function saveToken(token: string): void {
  try {
    window.localStorage.setItem(KEY, token);
  } catch {
    // Sem armazenamento (janela privada): a sessão vale só enquanto a página estiver aberta.
  }
}

export function clearToken(): void {
  try {
    window.localStorage.removeItem(KEY);
  } catch {
    // Nada a limpar.
  }
}
