import { describe, expect, it } from "vitest";
import { newRule, parseRule, serializeRule, type Catalog, type RuleJson } from "./builder";

const catalog: Catalog = {
  facts: { message_text: "text", amount: "number", contacts_24h: "number", channel: "string", customer_recurring: "boolean" },
  operators: { text: ["contains_any"], number: ["eq", "gt", "gte", "lt", "lte"], string: ["eq", "neq", "in"], boolean: ["eq"] },
};

// As regras v1 publicadas nos seeds (backend/db/seeds.rb).
const seeds: RuleJson[] = [
  {
    id: "credito-alto-valor",
    name: "Crédito acima de R$ 5 mil",
    when: {
      all: [
        { fact: "message_text", op: "contains_any", value: ["crédito", "empréstimo"] },
        { fact: "amount", op: "gte", value: 5000 },
      ],
    },
    then: { queue: "credito-infinitepay", priority: "p1", tags: ["alto_valor"] },
  },
  {
    id: "maquininha",
    name: "Maquininha",
    when: { fact: "message_text", op: "contains_any", value: ["maquininha", "não liga"] },
    then: { queue: "maquininha-infinitepay", priority: "p2", tags: ["dispositivo"] },
  },
  { id: "recontato", name: "Recontato", when: { fact: "contacts_24h", op: "gte", value: 3 }, then: { priority: "p2", tags: ["recontato"] } },
  { id: "todas", name: "Todas", when: {}, then: { priority: "p3" } },
];

describe("construtor de regras", () => {
  it("abre as regras dos seeds e grava de volta exatamente o mesmo JSON", () => {
    for (const rule of seeds) {
      expect(serializeRule(parseRule(rule), catalog)).toEqual(rule);
    }
  });

  it("mostra as condições como texto editável", () => {
    const editable = parseRule(seeds[0]!);

    expect(editable).toMatchObject({
      kind: "simple",
      match: "all",
      conditions: [
        { fact: "message_text", op: "contains_any", value: "crédito, empréstimo" },
        { fact: "amount", op: "gte", value: "5000" },
      ],
      queue: "credito-infinitepay",
      priority: "p1",
      tags: "alto_valor",
    });
  });

  it("converte o texto para o tipo do fato ao gravar", () => {
    const editable = parseRule(seeds[3]!);
    if (editable.kind !== "simple") throw new Error("esperava regra simples");
    const edited = {
      ...editable,
      match: "any" as const,
      conditions: [
        { fact: "channel", op: "in", value: "whatsapp,  email ," },
        { fact: "customer_recurring", op: "eq", value: "true" },
        { fact: "amount", op: "gt", value: "1.500" },
        { fact: "amount", op: "lt", value: "2.500,75" },
        { fact: "contacts_24h", op: "gte", value: "2,5" },
      ],
      queue: "",
      tags: " vip, urgente ",
    };

    expect(serializeRule(edited, catalog)).toEqual({
      id: "todas",
      name: "Todas",
      when: {
        any: [
          { fact: "channel", op: "in", value: ["whatsapp", "email"] },
          { fact: "customer_recurring", op: "eq", value: true },
          // Formato brasileiro: ponto de milhar, vírgula decimal. "1.500" é mil e quinhentos.
          { fact: "amount", op: "gt", value: 1500 },
          { fact: "amount", op: "lt", value: 2500.75 },
          { fact: "contacts_24h", op: "gte", value: 2.5 },
        ],
      },
      then: { priority: "p3", tags: ["vip", "urgente"] },
    });
  });

  it("deixa número inválido como texto, para o backend apontar o erro no lugar certo", () => {
    const editable = parseRule(seeds[2]!);
    if (editable.kind !== "simple") throw new Error("esperava regra simples");

    const serialized = serializeRule({ ...editable, conditions: [{ fact: "contacts_24h", op: "gte", value: "três" }] }, catalog);

    expect(serialized.when).toEqual({ fact: "contacts_24h", op: "gte", value: "três" });
  });

  it("guarda regras aninhadas sem mexer, só para leitura", () => {
    const nested: RuleJson = {
      id: "aninhada",
      name: "Aninhada",
      when: { any: [{ all: [{ fact: "amount", op: "gt", value: 1 }] }] },
      then: { priority: "p1" },
    };

    const editable = parseRule(nested);

    expect(editable.kind).toBe("advanced");
    expect(serializeRule(editable, catalog)).toBe(nested);
  });

  it("cria regra nova com id único", () => {
    expect(newRule(["regra-1", "regra-2"])).toMatchObject({ kind: "simple", id: "regra-3", name: "Nova regra", conditions: [] });
  });
});
