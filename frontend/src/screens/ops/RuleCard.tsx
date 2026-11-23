import { ArrowDown, ArrowUp, Trash2 } from "lucide-react";
import type { Queue } from "../../lib/opsApi";
import { defaultCondition, type Catalog, type Condition, type EditableRule, type SimpleRule } from "./rules/builder";

const FACT_LABELS: Record<string, string> = {
  brand: "Marca",
  channel: "Canal",
  stage: "Momento",
  message_text: "Texto da mensagem",
  customer_recurring: "Cliente recorrente",
  contacts_24h: "Contatos em 24 h",
  amount: "Valor citado",
  escalation_reason: "Motivo da escalação",
  escalation_trigger: "Gatilho da escalação",
  ai_minutes: "Minutos com a IA",
  category: "Categoria (IA)",
  language: "Idioma (IA)",
  frustration: "Frustração (IA)",
};

const OPERATOR_LABELS: Record<string, string> = {
  eq: "é igual a",
  neq: "é diferente de",
  in: "é um de",
  contains_any: "contém alguma de",
  gt: "maior que",
  gte: "maior ou igual a",
  lt: "menor que",
  lte: "menor ou igual a",
};

const PRIORITIES = ["p1", "p2", "p3", "p4"];

const iconButton =
  "flex size-7 items-center justify-center rounded-md text-faint transition-colors duration-150 hover:bg-elevated hover:text-text disabled:pointer-events-none disabled:opacity-30";
const control = "h-8 rounded-md border border-line-strong bg-surface px-2.5 text-xs text-text outline-none transition-colors duration-150 hover:border-faint focus:border-accent disabled:opacity-60 disabled:hover:border-line-strong";

interface RuleCardProps {
  rule: EditableRule;
  index: number;
  total: number;
  catalog: Catalog;
  queues: Queue[];
  editable: boolean;
  errors: string[];
  onChange: (rule: EditableRule) => void;
  onMove: (delta: -1 | 1) => void;
  onRemove: () => void;
}

export function RuleCard({ rule, index, total, catalog, queues, editable, errors, onChange, onMove, onRemove }: RuleCardProps) {
  const name = rule.kind === "simple" ? rule.name : rule.raw.name;

  return (
    <fieldset
      aria-label={`Regra ${name.trim() || "sem nome"}`}
      className="rounded-lg border border-line bg-surface p-4"
    >
      <div className="flex items-center gap-2">
        <span className="flex size-6 shrink-0 items-center justify-center rounded-md bg-elevated font-mono text-[11px] text-muted tabular">{index + 1}</span>
        {rule.kind === "simple" ? (
          <>
            <label htmlFor={`rule-name-${index}`} className="sr-only">
              Nome da regra
            </label>
            <input
              id={`rule-name-${index}`}
              value={rule.name}
              disabled={!editable}
              onChange={(event) => onChange({ ...rule, name: event.target.value })}
              className="h-8 flex-1 rounded-md border border-transparent bg-transparent px-2 text-sm font-medium text-text outline-none hover:border-line-strong focus:border-accent disabled:hover:border-transparent"
            />
          </>
        ) : (
          <p className="flex-1 px-2 text-sm font-medium">{rule.raw.name}</p>
        )}
        {editable && (
          <div className="flex gap-0.5">
            <button type="button" aria-label="Subir" title="Subir" disabled={index === 0} onClick={() => onMove(-1)} className={iconButton}>
              <ArrowUp aria-hidden className="size-3.5" strokeWidth={2} />
            </button>
            <button type="button" aria-label="Descer" title="Descer" disabled={index === total - 1} onClick={() => onMove(1)} className={iconButton}>
              <ArrowDown aria-hidden className="size-3.5" strokeWidth={2} />
            </button>
            <button type="button" aria-label="Remover regra" title="Remover regra" onClick={onRemove} className={`${iconButton} hover:bg-danger/12 hover:text-danger`}>
              <Trash2 aria-hidden className="size-3.5" strokeWidth={2} />
            </button>
          </div>
        )}
      </div>

      {rule.kind === "advanced" ? (
        <div className="mt-3">
          <p className="text-xs text-warning">Regra com mais de um nível: só leitura aqui, editável pela API.</p>
          <pre className="mt-2 overflow-x-auto rounded-md bg-bg p-3 font-mono text-[11px] text-muted">
            {JSON.stringify(rule.raw, null, 2)}
          </pre>
        </div>
      ) : (
        <SimpleBody rule={rule} index={index} catalog={catalog} queues={queues} editable={editable} onChange={onChange} />
      )}

      {errors.length > 0 && (
        <ul className="mt-3 space-y-0.5">
          {errors.map((error) => (
            <li key={error} className="text-xs text-danger">
              {error}
            </li>
          ))}
        </ul>
      )}
    </fieldset>
  );
}

function SimpleBody({
  rule,
  index,
  catalog,
  queues,
  editable,
  onChange,
}: {
  rule: SimpleRule;
  index: number;
  catalog: Catalog;
  queues: Queue[];
  editable: boolean;
  onChange: (rule: SimpleRule) => void;
}) {
  const setCondition = (position: number, condition: Condition) =>
    onChange({ ...rule, conditions: rule.conditions.map((current, i) => (i === position ? condition : current)) });

  return (
    <div className="mt-3 grid gap-4 lg:grid-cols-[1fr_16rem]">
      <div>
        <div className="flex items-center gap-2 text-xs text-muted">
          <span>Quando</span>
          <label htmlFor={`rule-match-${index}`} className="sr-only">
            Combinar condições
          </label>
          <select
            id={`rule-match-${index}`}
            value={rule.match}
            disabled={!editable || rule.conditions.length < 2}
            onChange={(event) => onChange({ ...rule, match: event.target.value as SimpleRule["match"] })}
            className={control}
          >
            <option value="all">todas as condições</option>
            <option value="any">qualquer condição</option>
          </select>
          <span>valerem</span>
        </div>

        {rule.conditions.length === 0 && (
          <p className="mt-2 text-xs text-faint">Sem condições: vale para todo ticket.</p>
        )}
        <ol className="mt-2 space-y-2">
          {rule.conditions.map((condition, position) => {
            const type = catalog.facts[condition.fact];
            const operators = type ? catalog.operators[type] : [];
            const n = position + 1;
            return (
              <li key={position} className="flex flex-wrap items-center gap-2">
                <label htmlFor={`fact-${index}-${position}`} className="sr-only">
                  Fato da condição {n}
                </label>
                <select
                  id={`fact-${index}-${position}`}
                  value={condition.fact}
                  disabled={!editable}
                  onChange={(event) => {
                    const fact = event.target.value;
                    const factType = catalog.facts[fact];
                    setCondition(position, { fact, op: (factType && catalog.operators[factType][0]) ?? "eq", value: "" });
                  }}
                  className={control}
                >
                  {Object.keys(catalog.facts).map((fact) => (
                    <option key={fact} value={fact}>
                      {FACT_LABELS[fact] ?? fact}
                    </option>
                  ))}
                </select>
                <label htmlFor={`op-${index}-${position}`} className="sr-only">
                  Operador da condição {n}
                </label>
                <select
                  id={`op-${index}-${position}`}
                  value={condition.op}
                  disabled={!editable}
                  onChange={(event) => setCondition(position, { ...condition, op: event.target.value })}
                  className={control}
                >
                  {operators.map((op) => (
                    <option key={op} value={op}>
                      {OPERATOR_LABELS[op] ?? op}
                    </option>
                  ))}
                </select>
                <label htmlFor={`value-${index}-${position}`} className="sr-only">
                  Valor da condição {n}
                </label>
                {type === "boolean" ? (
                  <select
                    id={`value-${index}-${position}`}
                    value={condition.value || "true"}
                    disabled={!editable}
                    onChange={(event) => setCondition(position, { ...condition, value: event.target.value })}
                    className={control}
                  >
                    <option value="true">sim</option>
                    <option value="false">não</option>
                  </select>
                ) : (
                  <input
                    id={`value-${index}-${position}`}
                    value={condition.value}
                    disabled={!editable}
                    placeholder={type === "text" || condition.op === "in" ? "separe por vírgula" : type === "number" ? "ex.: 5.000" : ""}
                    onChange={(event) => setCondition(position, { ...condition, value: event.target.value })}
                    className={`${control} min-w-48 flex-1`}
                  />
                )}
                {editable && (
                  <button
                    type="button"
                    aria-label={`Remover condição ${n}`}
                    onClick={() => onChange({ ...rule, conditions: rule.conditions.filter((_, i) => i !== position) })}
                    className="h-7 rounded px-2 text-xs text-faint hover:text-danger"
                  >
                    ×
                  </button>
                )}
              </li>
            );
          })}
        </ol>
        {editable && (
          <button
            type="button"
            onClick={() => onChange({ ...rule, conditions: [...rule.conditions, defaultCondition(catalog)] })}
            className="mt-2 text-xs text-accent underline-offset-2 hover:underline"
          >
            Adicionar condição
          </button>
        )}
      </div>

      <div className="space-y-2 border-line lg:border-l lg:pl-4">
        <p className="font-mono text-[11px] text-accent">então</p>
        <label className="block text-[11px] text-faint" htmlFor={`queue-${index}`}>
          Fila
        </label>
        <select
          id={`queue-${index}`}
          value={rule.queue}
          disabled={!editable}
          onChange={(event) => onChange({ ...rule, queue: event.target.value })}
          className={`${control} w-full`}
        >
          <option value="">Não muda</option>
          {queues.map((queue) => (
            <option key={queue.id} value={queue.slug}>
              {queue.name}
            </option>
          ))}
        </select>
        <label className="block text-[11px] text-faint" htmlFor={`priority-${index}`}>
          Prioridade
        </label>
        <select
          id={`priority-${index}`}
          value={rule.priority}
          disabled={!editable}
          onChange={(event) => onChange({ ...rule, priority: event.target.value })}
          className={`${control} w-full`}
        >
          <option value="">Não muda</option>
          {PRIORITIES.map((priority) => (
            <option key={priority} value={priority}>
              {priority.toUpperCase()}
            </option>
          ))}
        </select>
        <label className="block text-[11px] text-faint" htmlFor={`tags-${index}`}>
          Tags
        </label>
        <input
          id={`tags-${index}`}
          value={rule.tags}
          disabled={!editable}
          placeholder="separe por vírgula"
          onChange={(event) => onChange({ ...rule, tags: event.target.value })}
          className={`${control} w-full font-mono`}
        />
      </div>
    </div>
  );
}
