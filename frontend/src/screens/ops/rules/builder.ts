// Tradução entre a árvore JSON das regras (ADR 0005) e os cartões do construtor de um nível (ADR 0007, I10).
// Funções puras: o que entra no construtor e volta sem edição sai igual ao que entrou.

export type FactType = "string" | "text" | "number" | "boolean";

export interface Catalog {
  facts: Record<string, FactType>;
  operators: Record<FactType, string[]>;
}

export interface Leaf {
  fact: string;
  op: string;
  value: unknown;
}

export interface RuleJson {
  id: string;
  name: string;
  when?: Record<string, unknown>;
  then: { queue?: string; priority?: string; tags?: string[] };
}

export interface Condition {
  fact: string;
  op: string;
  /** Sempre texto na tela; vira o tipo do fato ao gravar. Listas separadas por vírgula. */
  value: string;
}

export interface SimpleRule {
  kind: "simple";
  id: string;
  name: string;
  match: "all" | "any";
  conditions: Condition[];
  queue: string;
  priority: string;
  tags: string;
}

/** Regra com aninhamento mais fundo: só leitura na tela, editável pela API. */
export interface AdvancedRule {
  kind: "advanced";
  raw: RuleJson;
}

export type EditableRule = SimpleRule | AdvancedRule;

function isLeaf(node: unknown): node is Leaf {
  return typeof node === "object" && node !== null && "fact" in node;
}

function valueToText(value: unknown): string {
  if (Array.isArray(value)) return value.join(", ");
  return value === undefined || value === null ? "" : String(value);
}

export function parseRule(rule: RuleJson): EditableRule {
  const when = rule.when ?? {};
  let match: SimpleRule["match"] = "all";
  let leaves: Leaf[];

  if (Object.keys(when).length === 0) {
    leaves = [];
  } else if (isLeaf(when)) {
    leaves = [when];
  } else {
    const group = (["all", "any"] as const).find((key) => key in when);
    const children = group ? when[group] : undefined;
    if (!group || !Array.isArray(children) || !children.every(isLeaf)) return { kind: "advanced", raw: rule };
    match = group;
    leaves = children;
  }

  return {
    kind: "simple",
    id: rule.id,
    name: rule.name,
    match,
    conditions: leaves.map((leaf) => ({ fact: leaf.fact, op: leaf.op, value: valueToText(leaf.value) })),
    queue: rule.then.queue ?? "",
    priority: rule.then.priority ?? "",
    tags: (rule.then.tags ?? []).join(", "),
  };
}

function list(text: string): string[] {
  return text
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

// Número no formato brasileiro: "1.500" é mil e quinhentos, "2.500,75" e "2,5" usam vírgula decimal.
// Texto que não é número fica como texto, para o backend apontar o erro no caminho certo.
function parseNumber(text: string): number | string {
  const trimmed = text.trim();
  let normalized = trimmed;
  if (/^-?\d{1,3}(\.\d{3})+(,\d+)?$/.test(trimmed)) normalized = trimmed.replace(/\./g, "").replace(",", ".");
  else if (/^-?\d+,\d+$/.test(trimmed)) normalized = trimmed.replace(",", ".");
  const value = Number(normalized);
  return trimmed !== "" && Number.isFinite(value) ? value : text;
}

function textToValue(condition: Condition, catalog: Catalog): unknown {
  const type = catalog.facts[condition.fact];
  if (type === "text" || (type === "string" && condition.op === "in")) return list(condition.value);
  if (type === "number") return parseNumber(condition.value);
  if (type === "boolean") return condition.value === "true";
  return condition.value;
}

export function serializeRule(rule: EditableRule, catalog: Catalog): RuleJson {
  if (rule.kind === "advanced") return rule.raw;

  const leaves: Leaf[] = rule.conditions.map((condition) => ({
    fact: condition.fact,
    op: condition.op,
    value: textToValue(condition, catalog),
  }));
  let when: Record<string, unknown>;
  if (leaves.length === 0) when = {};
  else if (leaves.length === 1) when = { ...leaves[0]! };
  else when = { [rule.match]: leaves };

  const then: RuleJson["then"] = {};
  if (rule.queue) then.queue = rule.queue;
  if (rule.priority) then.priority = rule.priority;
  const tags = list(rule.tags);
  if (tags.length > 0) then.tags = tags;

  return { id: rule.id, name: rule.name, when, then };
}

export function newRule(existingIds: string[]): SimpleRule {
  let index = existingIds.length + 1;
  while (existingIds.includes(`regra-${index}`)) index++;
  return {
    kind: "simple",
    id: `regra-${index}`,
    name: "Nova regra",
    match: "all",
    conditions: [],
    queue: "",
    priority: "",
    tags: "",
  };
}

export function defaultCondition(catalog: Catalog): Condition {
  const fact = Object.keys(catalog.facts)[0] ?? "message_text";
  const type = catalog.facts[fact] ?? "text";
  return { fact, op: catalog.operators[type]?.[0] ?? "eq", value: "" };
}
