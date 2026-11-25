import { useCallback, useEffect, useState } from "react";
import { ApiError } from "../../lib/api";
import { BRAND_LABELS } from "../../lib/format";
import { LoadingScreen } from "../../ui/LoadingScreen";
import {
  createRuleSet,
  dryRunRuleSet,
  fetchCatalog,
  fetchQueues,
  fetchRuleSet,
  fetchRuleSets,
  publishRuleSet,
  updateRuleSet,
  type DryRunResult,
  type Outcome,
  type Queue,
  type RuleSet,
  type RuleSetSummary,
} from "../../lib/opsApi";
import { RuleCard } from "./RuleCard";
import { newRule, parseRule, serializeRule, type Catalog, type EditableRule } from "./rules/builder";

const STATUS_LABELS: Record<RuleSetSummary["status"], string> = {
  draft: "rascunho",
  published: "publicada",
  archived: "arquivada",
};

const BRANDS = ["infinitepay", "jim"];
const button = "inline-flex h-8 shrink-0 items-center justify-center gap-1.5 rounded-md border border-line-strong bg-surface px-3 text-xs font-medium text-text transition-colors duration-150 hover:border-faint hover:bg-elevated disabled:pointer-events-none disabled:opacity-40";
const primary = "inline-flex h-8 shrink-0 items-center justify-center gap-1.5 rounded-md bg-accent px-3 text-xs font-medium text-on-accent transition-colors duration-150 hover:bg-accent-strong disabled:pointer-events-none disabled:opacity-40";

// Erros do validador vêm com caminho ("rules[0].when.all[1].value"); a tela mostra no cartão da regra.
function errorsByRule(error: unknown): Map<number, string[]> {
  const byRule = new Map<number, string[]>();
  if (!(error instanceof ApiError)) return byRule;
  for (const detail of error.details) {
    const match = /^rules\[(\d+)\]\.?(.*)$/.exec(detail.path);
    if (!match) continue;
    const index = Number(match[1]);
    const rest = match[2] ?? "";
    let field = "Regra";
    if (rest === "name") field = "Nome";
    else if (rest === "id") field = "Identificador";
    else if (rest.startsWith("then")) field = "Ações";
    else if (rest.startsWith("when")) {
      const condition = /\[(\d+)\]/.exec(rest);
      field = condition ? `Condição ${Number(condition[1]) + 1}` : "Condição 1";
    }
    byRule.set(index, [...(byRule.get(index) ?? []), `${field}: ${detail.message}`]);
  }
  return byRule;
}

function describeChange(before: Outcome, after: Outcome): string {
  const parts: string[] = [];
  if (before.queue !== after.queue) parts.push(`fila ${before.queue ?? "—"} → ${after.queue ?? "—"}`);
  if (before.priority !== after.priority) parts.push(`prioridade ${before.priority ?? "—"} → ${after.priority ?? "—"}`);
  if (before.tags.join(",") !== after.tags.join(",")) parts.push(`tags [${before.tags.join(", ")}] → [${after.tags.join(", ")}]`);
  if (parts.length === 0) parts.push(`regra ${before.rule_id ?? "—"} → ${after.rule_id ?? "—"}`);
  return parts.join(" · ");
}

// Editor de regras (ADR 0005 e ADR 0007, I10): rascunho, simulação contra tickets reais e publicação.
export function RulesEditor({ token }: { token: string }) {
  const [brand, setBrand] = useState("infinitepay");
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [queues, setQueues] = useState<Queue[]>([]);
  const [versions, setVersions] = useState<RuleSetSummary[]>([]);
  const [selected, setSelected] = useState<RuleSet | null>(null);
  const [rules, setRules] = useState<EditableRule[]>([]);
  const [dirty, setDirty] = useState(false);
  const [ruleErrors, setRuleErrors] = useState<Map<number, string[]>>(new Map());
  const [message, setMessage] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const [dryRun, setDryRun] = useState<DryRunResult | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);

  const open = useCallback(
    async (id: string) => {
      const ruleSet = await fetchRuleSet(token, id);
      setSelected(ruleSet);
      setRules(ruleSet.rules.map(parseRule));
      setDirty(false);
      setRuleErrors(new Map());
      setDryRun(null);
      setConfirming(false);
    },
    [token],
  );

  const loadBrand = useCallback(
    async (slug: string, preferId?: string) => {
      const list = await fetchRuleSets(token, slug);
      setVersions(list);
      const target = list.find((version) => version.id === preferId) ??
        list.find((version) => version.status === "draft") ??
        list.find((version) => version.status === "published") ??
        list[0];
      if (target) await open(target.id);
      else {
        setSelected(null);
        setRules([]);
      }
    },
    [token, open],
  );

  useEffect(() => {
    let active = true;
    Promise.all([fetchCatalog(token), fetchQueues(token)]).then(
      ([loadedCatalog, loadedQueues]) => {
        if (!active) return;
        setCatalog(loadedCatalog);
        setQueues(loadedQueues);
      },
      () => active && setMessage({ tone: "error", text: "Não foi possível carregar o catálogo de regras." }),
    );
    return () => {
      active = false;
    };
  }, [token]);

  useEffect(() => {
    const timer = setTimeout(() => {
      loadBrand(brand).catch(() => setMessage({ tone: "error", text: "Não foi possível carregar as versões." }));
    }, 0);
    return () => clearTimeout(timer);
  }, [brand, loadBrand]);

  if (!catalog) return message ? <p className="p-6 text-sm text-faint">{message.text}</p> : <LoadingScreen label="Carregando as regras…" />;

  const editable = selected?.status === "draft";
  const brandQueues = queues.filter((queue) => queue.brand === brand);

  function update(next: EditableRule[]) {
    setRules(next);
    setDirty(true);
    setDryRun(null);
    setConfirming(false);
  }

  async function run(action: () => Promise<void>, failure: string) {
    setBusy(true);
    setMessage(null);
    try {
      await action();
    } catch (error) {
      const byRule = errorsByRule(error);
      setRuleErrors(byRule);
      setMessage({ tone: "error", text: byRule.size > 0 ? "Corrija os erros marcados nas regras." : failure });
    } finally {
      setBusy(false);
    }
  }

  const serialized = () => rules.map((rule) => serializeRule(rule, catalog));

  return (
    <div className="flex min-w-0 flex-1 flex-col">
      <div className="flex min-h-14 flex-wrap items-center gap-3 border-b border-line px-6 py-2.5">
        <label htmlFor="rules-brand" className="text-xs text-muted">
          Marca
        </label>
        <select
          id="rules-brand"
          value={brand}
          onChange={(event) => setBrand(event.target.value)}
          className="h-8 rounded-md border border-line-strong bg-surface px-2.5 text-xs text-text outline-none transition-colors duration-150 hover:border-faint focus:border-accent disabled:opacity-60 disabled:hover:border-line-strong"
        >
          {BRANDS.map((value) => (
            <option key={value} value={value}>
              {BRAND_LABELS[value]}
            </option>
          ))}
        </select>
        <label htmlFor="rules-version" className="ml-2 text-xs text-muted">
          Versão
        </label>
        <select
          id="rules-version"
          value={selected?.id ?? ""}
          onChange={(event) => void open(event.target.value)}
          className="h-8 rounded-md border border-line-strong bg-surface px-2.5 text-xs text-text outline-none transition-colors duration-150 hover:border-faint focus:border-accent disabled:opacity-60 disabled:hover:border-line-strong"
        >
          {versions.map((version) => (
            <option key={version.id} value={version.id}>
              v{version.version} · {STATUS_LABELS[version.status]} · {version.rules_count} regras
            </option>
          ))}
        </select>
        {selected && (
          <p className="text-xs text-muted">
            Versão {selected.version} · {STATUS_LABELS[selected.status]}
          </p>
        )}

        <div className="ml-auto flex flex-wrap items-center gap-2">
          {selected && !editable && (
            <button
              type="button"
              disabled={busy}
              className={primary}
              onClick={() =>
                run(async () => {
                  const draft = await createRuleSet(token, brand, selected.rules);
                  await loadBrand(brand, draft.id);
                  setMessage({ tone: "ok", text: `Rascunho v${draft.version} criado.` });
                }, "Não foi possível criar o rascunho.")
              }
            >
              Criar rascunho a partir desta versão
            </button>
          )}
          {editable && selected && (
            <>
              <button
                type="button"
                className={button}
                onClick={() => update([...rules, newRule(rules.map((rule) => (rule.kind === "simple" ? rule.id : rule.raw.id)))])}
              >
                Adicionar regra
              </button>
              <button
                type="button"
                disabled={busy || !dirty}
                className={button}
                onClick={() =>
                  run(async () => {
                    const saved = await updateRuleSet(token, selected.id, serialized());
                    setSelected(saved);
                    setRules(saved.rules.map(parseRule));
                    setDirty(false);
                    setRuleErrors(new Map());
                    setMessage({ tone: "ok", text: "Rascunho salvo." });
                  }, "Não foi possível salvar o rascunho.")
                }
              >
                Salvar rascunho
              </button>
              <button
                type="button"
                disabled={busy || dirty}
                title={dirty ? "Salve antes de simular" : undefined}
                className={button}
                onClick={() => run(async () => setDryRun(await dryRunRuleSet(token, selected.id)), "Não foi possível simular.")}
              >
                Simular
              </button>
              {confirming ? (
                <>
                  <button
                    type="button"
                    disabled={busy}
                    className={primary}
                    onClick={() =>
                      run(async () => {
                        await publishRuleSet(token, selected.id);
                        await loadBrand(brand, selected.id);
                        setMessage({ tone: "ok", text: `Versão ${selected.version} publicada.` });
                      }, "Não foi possível publicar.")
                    }
                  >
                    Confirmar publicação
                  </button>
                  <button type="button" className={button} onClick={() => setConfirming(false)}>
                    Cancelar
                  </button>
                </>
              ) : (
                <button
                  type="button"
                  disabled={busy || dirty}
                  title={dirty ? "Salve antes de publicar" : undefined}
                  className={primary}
                  onClick={() => setConfirming(true)}
                >
                  Publicar
                </button>
              )}
            </>
          )}
        </div>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto p-6">
        {message && (
          <p role={message.tone === "ok" ? "status" : "alert"} className={`text-xs ${message.tone === "ok" ? "text-success" : "text-danger"}`}>
            {message.text}
          </p>
        )}
        {confirming && (
          <p className="text-xs text-warning">
            Publicar troca as regras de {BRAND_LABELS[brand]} para os próximos tickets. A versão atual vira arquivo.
          </p>
        )}
        {editable && <p className="text-xs text-faint">A primeira regra que casar decide. Ordem importa.</p>}

        {dryRun && (
          <section aria-label="Resultado da simulação" className="animate-rise rounded-lg border border-info/30 bg-info/5 p-4">
            <h2 className="text-sm font-semibold text-info">Simulação</h2>
            <p className="mt-1 text-sm">
              {dryRun.changed} de {dryRun.evaluated} tickets recentes mudariam
              {dryRun.current_version ? ` em relação à v${dryRun.current_version}` : ""}.
            </p>
            {dryRun.changes.length > 0 && (
              <ul className="mt-2 max-h-48 space-y-1 overflow-y-auto">
                {dryRun.changes.map((change) => (
                  <li key={change.ticket_id} className="flex gap-3 text-xs">
                    <span className="font-mono text-faint">{change.ticket_id.slice(0, 8)}</span>
                    <span className="text-muted">{describeChange(change.before, change.after)}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        )}

        {selected === null && <p className="text-sm text-faint">Esta marca ainda não tem regras.</p>}
        {rules.map((rule, index) => (
          <RuleCard
            key={index}
            rule={rule}
            index={index}
            total={rules.length}
            catalog={catalog}
            queues={brandQueues}
            editable={editable}
            errors={ruleErrors.get(index) ?? []}
            onChange={(next) => update(rules.map((current, i) => (i === index ? next : current)))}
            onMove={(delta) => {
              const next = [...rules];
              const [moved] = next.splice(index, 1);
              if (moved) next.splice(index + delta, 0, moved);
              update(next);
            }}
            onRemove={() => update(rules.filter((_, i) => i !== index))}
          />
        ))}
      </div>
    </div>
  );
}
