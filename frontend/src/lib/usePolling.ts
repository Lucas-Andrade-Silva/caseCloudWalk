import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Busca um recurso agora e de novo a cada `intervalMs` (saída por polling do ADR 0002; o ActionCable entra
 * depois). `reload` busca na hora, por exemplo depois de uma ação do usuário. Uma resposta de uma busca
 * antiga nunca sobrescreve a de uma mais nova.
 */
export function usePolling<T>(load: (() => Promise<T>) | null, intervalMs: number) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<unknown>(null);
  const latest = useRef(0);
  const loadRef = useRef(load);

  useEffect(() => {
    loadRef.current = load;
  }, [load]);

  const reload = useCallback(async () => {
    const current = loadRef.current;
    if (!current) return;
    const ticket = ++latest.current;
    try {
      const value = await current();
      if (ticket === latest.current) {
        setData(value);
        setError(null);
      }
    } catch (failure) {
      if (ticket === latest.current) setError(failure);
    }
  }, []);

  // Descarta o que ainda está a caminho: a resposta de uma busca antiga não vale mais.
  const discardInFlight = useCallback(() => {
    latest.current++;
  }, []);

  useEffect(() => {
    if (!load) return;
    const first = setTimeout(() => void reload(), 0);
    const timer = setInterval(() => void reload(), intervalMs);
    return () => {
      clearTimeout(first);
      clearInterval(timer);
      discardInFlight();
    };
  }, [load, intervalMs, reload, discardInFlight]);

  return { data, error, reload, setData };
}
