// API da operação: equipes, filas e versões de regras (ADR 0005; telas no ADR 0007, I10 e I11).
import { request } from "./api";
import type { Catalog, RuleJson } from "../screens/ops/rules/builder";

export interface Queue {
  id: string;
  slug: string;
  name: string;
  brand: string;
  default: boolean;
  team: { id: string; slug: string; name: string };
}

export interface Team {
  id: string;
  slug: string;
  name: string;
  members: { id: string; name: string }[];
  queues: string[];
}

export interface Analyst {
  id: string;
  name: string;
  teams: string[];
}

export type RuleSetStatus = "draft" | "published" | "archived";

export interface RuleSetSummary {
  id: string;
  brand: string;
  version: number;
  status: RuleSetStatus;
  published_at: string | null;
  rules_count: number;
}

export interface RuleSet extends RuleSetSummary {
  rules: RuleJson[];
}

export interface Outcome {
  rule_id: string | null;
  queue: string | null;
  priority: string | null;
  tags: string[];
}

export interface DryRunResult {
  current_version: number | null;
  candidate_version: number;
  evaluated: number;
  changed: number;
  changes: { ticket_id: string; before: Outcome; after: Outcome }[];
}

export const fetchQueues = (token: string) => request<Queue[]>(token, "/api/ops/queues");
export const createQueue = (token: string, queue: { brand: string; slug: string; name: string; team_id: string }) =>
  request<Queue>(token, "/api/ops/queues", { method: "POST", body: queue });
export const updateQueue = (token: string, id: string, changes: { name?: string; team_id?: string }) =>
  request<Queue>(token, `/api/ops/queues/${id}`, { method: "PATCH", body: changes });

export const fetchTeams = (token: string) => request<Team[]>(token, "/api/ops/teams");
export const createTeam = (token: string, team: { slug: string; name: string }) =>
  request<Team>(token, "/api/ops/teams", { method: "POST", body: team });
export const addMember = (token: string, teamId: string, userId: string) =>
  request<null>(token, `/api/ops/teams/${teamId}/members`, { method: "POST", body: { user_id: userId } });
export const removeMember = (token: string, teamId: string, userId: string) =>
  request<null>(token, `/api/ops/teams/${teamId}/members/${userId}`, { method: "DELETE" });
export const fetchAnalysts = (token: string) => request<Analyst[]>(token, "/api/ops/analysts");

export const fetchCatalog = (token: string) => request<Catalog>(token, "/api/ops/rules/catalog");
export const fetchRuleSets = (token: string, brand: string) =>
  request<RuleSetSummary[]>(token, `/api/ops/brands/${brand}/rule_sets`);
export const fetchRuleSet = (token: string, id: string) => request<RuleSet>(token, `/api/ops/rule_sets/${id}`);
export const createRuleSet = (token: string, brand: string, rules: RuleJson[]) =>
  request<RuleSet>(token, `/api/ops/brands/${brand}/rule_sets`, { method: "POST", body: { rules } });
export const updateRuleSet = (token: string, id: string, rules: RuleJson[]) =>
  request<RuleSet>(token, `/api/ops/rule_sets/${id}`, { method: "PATCH", body: { rules } });
export const publishRuleSet = (token: string, id: string) =>
  request<RuleSet>(token, `/api/ops/rule_sets/${id}/publish`, { method: "POST" });
export const dryRunRuleSet = (token: string, id: string) =>
  request<DryRunResult>(token, `/api/ops/rule_sets/${id}/dry_run`, { method: "POST", body: {} });
