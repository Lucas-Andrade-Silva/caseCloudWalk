import { ApiError } from "../../lib/api";

const FIELD_LABELS: Record<string, string> = {
  brand: "Marca",
  name: "Nome",
  slug: "Identificador",
  team: "Equipe",
  team_id: "Equipe",
  user_id: "Analista",
};

/** Texto de erro da API da operação com os nomes de campo da tela ("slug" vira "Identificador"). */
export function describeError(error: unknown, fallback: string): string {
  if (error instanceof ApiError && error.details.length > 0) {
    return error.details.map((detail) => `${FIELD_LABELS[detail.path] ?? detail.path}: ${detail.message}`).join("; ");
  }
  if (error instanceof ApiError && error.message) return error.message;
  return fallback;
}
