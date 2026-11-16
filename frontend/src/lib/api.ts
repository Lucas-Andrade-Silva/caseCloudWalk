// Cliente da API da plataforma. O Vite repassa /api para o Rails (ADR 0007, I6).
export type Role = "analyst" | "ops";

export interface Me {
  id: string;
  name: string;
  role: Role;
  brands: string[];
}

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string, token: string): Promise<T> {
  const response = await fetch(path, {
    headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
  });
  const body: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const message = body && typeof body === "object" && "error" in body ? String(body.error) : response.statusText;
    throw new ApiError(response.status, message);
  }
  return body as T;
}

export function fetchMe(token: string): Promise<Me> {
  return request<Me>("/api/me", token);
}
