import { vi } from "vitest";

export type Handler = (body: unknown) => [number, unknown?];

export interface ApiCall {
  method: string;
  path: string;
  body: unknown;
  headers: Record<string, string>;
}

// Troca o fetch por respostas por rota ("GET /api/work"). Guarda cada chamada para o teste conferir.
export function mockApi(handlers: Record<string, Handler>) {
  const calls: ApiCall[] = [];

  const fetchMock = vi.fn(async (path: string, init: RequestInit = {}) => {
    const method = init.method ?? "GET";
    const body = typeof init.body === "string" ? JSON.parse(init.body) : undefined;
    calls.push({ method, path, body, headers: (init.headers ?? {}) as Record<string, string> });

    const handler = handlers[`${method} ${path}`];
    if (!handler) return new Response(JSON.stringify({ error: `sem rota de teste para ${method} ${path}` }), { status: 404 });

    const [status, payload] = handler(body);
    if (payload === undefined) return new Response(null, { status });
    return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });
  });

  vi.stubGlobal("fetch", fetchMock);
  return { calls, set: (route: string, handler: Handler) => (handlers[route] = handler) };
}
