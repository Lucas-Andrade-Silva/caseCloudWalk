import {
  ArrowUpRight,
  CircleSlash,
  ExternalLink,
  GitBranch,
  MessageSquare,
  Sparkles,
  TriangleAlert,
  type LucideIcon,
} from "lucide-react";
import { useCallback, type ReactNode } from "react";
import { fetchExplanation, type ExplanationStep } from "../../lib/api";
import { CHANNEL_LABELS, FACT_LABELS, OPERATOR_LABELS, timeOfDay } from "../../lib/format";
import { usePolling } from "../../lib/usePolling";

const REFRESH_MS = 10_000;
const JAEGER_URL = (import.meta.env.VITE_JAEGER_URL as string | undefined) ?? "http://127.0.0.1:16686";

const STAGES: Record<string, string> = {
  "routing.opening": "abertura",
  "routing.enrichment": "depois da LLM",
  "routing.escalation": "escalação",
};

const SOURCES: Record<string, string> = { live: "ao vivo", replay: "replay gravado", stub: "stub de teste" };

const REASONS: Record<string, string> = {
  disabled: "LLM desligada",
  circuit_open: "disjuntor da LLM aberto",
  invalid_output: "resposta fora do schema",
  replay_miss: "sem resposta gravada",
  stub_failure: "falha injetada no teste",
};

const TRIGGERS: Record<string, string> = {
  agent_requested: "o agente pediu",
  agent_silence: "o agente ficou calado",
  analyst_takeover: "a analista assumiu",
  incident: "resposta do incidente",
};

const REDACTION_LABELS: Record<string, [string, string]> = {
  cpf: ["CPF redigido", "CPFs redigidos"],
  card: ["cartão redigido", "cartões redigidos"],
  email: ["e-mail redigido", "e-mails redigidos"],
  phone: ["telefone redigido", "telefones redigidos"],
};

const decimal = (value: number) => value.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function reasonText(reason: string): string {
  return REASONS[reason] ?? reason;
}

function valueText(value: unknown): string {
  return Array.isArray(value) ? value.join(", ") : String(value);
}

/** Condição de regra em texto. Folhas e um nível de "all"/"any"; o resto aparece como JSON. */
export function conditionText(node: unknown): string {
  if (!node || typeof node !== "object") return "sempre";
  const tree = node as { fact?: string; op?: string; value?: unknown; all?: unknown[]; any?: unknown[] };
  if (tree.fact) {
    return `${FACT_LABELS[tree.fact] ?? tree.fact} ${OPERATOR_LABELS[tree.op ?? ""] ?? tree.op} ${valueText(tree.value)}`;
  }
  if (tree.all) return tree.all.length === 0 ? "sempre" : tree.all.map(conditionText).join(" e ");
  if (tree.any) return tree.any.map(conditionText).join(" ou ");
  return JSON.stringify(node);
}

function outputText(output: { queue: string | null; priority: string | null; tags: string[] }): string {
  const parts = [
    output.queue && `fila ${output.queue}`,
    output.priority && output.priority.toUpperCase(),
    output.tags.length > 0 && output.tags.join(", "),
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(" · ") : "sem mudança";
}

function Step({
  icon: Icon,
  tone = "muted",
  title,
  at,
  children,
}: {
  icon: LucideIcon;
  tone?: "muted" | "accent" | "warning" | "info";
  title: ReactNode;
  at: string;
  children?: ReactNode;
}) {
  const tones = { muted: "text-muted", accent: "text-accent", warning: "text-warning", info: "text-info" };
  return (
    <li className="relative">
      <span
        aria-hidden
        className="absolute top-0 -left-[27px] flex size-[22px] items-center justify-center rounded-full bg-bg ring-1 ring-line-strong"
      >
        <Icon className={`size-3 ${tones[tone]}`} strokeWidth={2} />
      </span>
      <p className="flex items-baseline justify-between gap-2 text-xs font-semibold text-text">
        <span>{title}</span>
        <time className="font-mono text-[11px] font-normal text-faint">{timeOfDay(at)}</time>
      </p>
      {children && <div className="mt-1 space-y-1 text-xs leading-relaxed text-muted">{children}</div>}
    </li>
  );
}

function renderStep(step: ExplanationStep, index: number) {
  switch (step.kind) {
    case "opened":
      return (
        <Step key={index} icon={MessageSquare} title={`Chegou pelo ${CHANNEL_LABELS[step.channel] ?? step.channel}`} at={step.at} />
      );
    case "rule":
      return (
        <Step
          key={index}
          icon={GitBranch}
          tone="info"
          title={`Regras v${step.rule_set_version ?? "—"} · ${STAGES[step.step] ?? step.step}`}
          at={step.at}
        >
          {step.rule ? (
            <>
              <p className="text-text">{step.rule.name}</p>
              <p className="font-mono text-[11px] text-faint">se {conditionText(step.rule.when)}</p>
              <p className="font-mono text-[11px] text-info">→ {outputText(step.output)}</p>
            </>
          ) : (
            <p>Nenhuma regra casou: segue a fila prevista ou a padrão.</p>
          )}
        </Step>
      );
    case "llm_facts":
      return (
        <Step key={index} icon={Sparkles} tone="accent" title="LLM classificou" at={step.at}>
          <p className="flex flex-wrap gap-1.5">
            <span
              className={`rounded px-1.5 py-0.5 font-mono text-[11px] ${
                step.accepted ? "bg-accent/12 text-accent" : "bg-elevated text-faint line-through"
              }`}
            >
              {step.category ?? "sem categoria"}
            </span>
            <span className="rounded bg-elevated px-1.5 py-0.5 font-mono text-[11px]">idioma {step.language}</span>
            <span className="rounded bg-elevated px-1.5 py-0.5 font-mono text-[11px]">frustração {step.frustration}</span>
          </p>
          <p className="flex items-center gap-2">
            <meter
              min={0}
              max={1}
              low={step.min_confidence}
              optimum={1}
              value={step.confidence}
              aria-label="Confiança da LLM"
              className="h-1.5 w-16"
            />
            <span className="font-mono text-[11px]">
              confiança {decimal(step.confidence)} (mínimo {decimal(step.min_confidence)})
              {!step.accepted && <span className="text-warning"> · abaixo do mínimo: categoria descartada</span>}
            </span>
          </p>
          <p className="font-mono text-[11px] text-faint">
            {step.model} · {step.prompt_version} · {SOURCES[step.source] ?? step.source}
          </p>
        </Step>
      );
    case "llm_fallback":
      return (
        <Step key={index} icon={CircleSlash} tone="warning" title="Sem LLM: seguiu só com as regras" at={step.at}>
          <p>{reasonText(step.reason)}</p>
        </Step>
      );
    case "escalated":
      return (
        <Step key={index} icon={ArrowUpRight} tone="warning" title={`Escalado: ${TRIGGERS[step.trigger] ?? step.trigger}`} at={step.at}>
          <p className="font-mono text-[11px]">
            motivo {step.reason} · {step.priority?.toUpperCase()}
          </p>
        </Step>
      );
    case "brief":
      return (
        <Step key={index} icon={Sparkles} tone="accent" title="Brief escrito pela LLM" at={step.at}>
          <p className="font-mono text-[11px] text-faint">
            {step.model} · {step.prompt_version} · {SOURCES[step.source] ?? step.source}
          </p>
        </Step>
      );
    case "brief_fallback":
      return (
        <Step key={index} icon={CircleSlash} tone="warning" title="Brief por template" at={step.at}>
          <p>{reasonText(step.reason)}</p>
        </Step>
      );
    case "incident":
      return (
        <Step key={index} icon={TriangleAlert} tone="warning" title="Entrou num incidente" at={step.at}>
          <p className="font-mono text-[11px]">{step.key}</p>
        </Step>
      );
  }
}

function redactionText(redactions: Record<string, number>): string[] {
  return Object.entries(redactions).map(([kind, count]) => {
    const [one, many] = REDACTION_LABELS[kind] ?? [`${kind} redigido`, `${kind} redigidos`];
    return `${count} ${count === 1 ? one : many}`;
  });
}

// "Por que a IA decidiu" (ADR 0009, W1): a cadeia de decisão do ticket, do texto que a LLM viu até o trace.
export function DecisionTrail({ token, ticketId }: { token: string; ticketId: string }) {
  const load = useCallback(() => fetchExplanation(token, ticketId), [token, ticketId]);
  const explanation = usePolling(load, REFRESH_MS);
  const data = explanation.data?.ticket_id === ticketId ? explanation.data : null;

  if (!data) {
    return (
      <p className="p-5 text-xs text-faint">
        {explanation.error ? "Não foi possível carregar a cadeia de decisão." : "Carregando…"}
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-6 p-5">
      <figure aria-label="Texto que a LLM recebeu" className="rounded-lg border border-line bg-surface p-3">
        <figcaption className="font-mono text-[11px] text-faint">o que a LLM recebeu</figcaption>
        <p className="mt-1.5 font-mono text-xs leading-relaxed break-words text-text">{data.redacted_text}</p>
        {Object.keys(data.redactions).length > 0 && (
          <p className="mt-2 flex flex-wrap gap-1.5">
            {redactionText(data.redactions).map((text) => (
              <span key={text} className="rounded bg-accent/12 px-1.5 py-0.5 font-mono text-[11px] text-accent">
                {text}
              </span>
            ))}
          </p>
        )}
      </figure>

      {data.steps.length === 0 ? (
        <p className="text-xs text-faint">Nenhuma decisão registrada ainda.</p>
      ) : (
        <ol aria-label="Cadeia de decisão" className="ml-[11px] space-y-5 border-l border-line pl-6">
          {data.steps.map(renderStep)}
        </ol>
      )}

      {data.trace_id ? (
        <a
          href={`${JAEGER_URL}/trace/${data.trace_id}`}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1.5 text-xs text-accent underline-offset-2 hover:underline"
        >
          <ExternalLink aria-hidden className="size-3.5" strokeWidth={2} />
          Ver o trace ponta a ponta no Jaeger
          <span className="font-mono text-[11px] text-faint">{data.trace_id.slice(0, 8)}</span>
        </a>
      ) : (
        <p className="text-xs text-faint">Sem trace registrado para este ticket.</p>
      )}
    </div>
  );
}
