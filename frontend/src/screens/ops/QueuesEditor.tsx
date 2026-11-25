import { X } from "lucide-react";
import { fieldClass, labelClass } from "../../ui/field";
import { LoadingScreen } from "../../ui/LoadingScreen";
import { useCallback, useEffect, useState, type FormEvent } from "react";
import { BRAND_LABELS } from "../../lib/format";
import {
  addMember,
  createQueue,
  createTeam,
  fetchAnalysts,
  fetchQueues,
  fetchTeams,
  removeMember,
  updateQueue,
  type Analyst,
  type Queue,
  type Team,
} from "../../lib/opsApi";
import { describeError } from "./fieldErrors";

const BRANDS = ["infinitepay", "jim"];

interface Data {
  queues: Queue[];
  teams: Team[];
  analysts: Analyst[];
}

const input = `${fieldClass} h-8`;
const button = "inline-flex h-8 shrink-0 items-center justify-center gap-1.5 rounded-md border border-line-strong bg-surface px-3 text-xs font-medium text-text transition-colors duration-150 hover:border-faint hover:bg-elevated disabled:pointer-events-none disabled:opacity-40";

// Filas e equipes (ADR 0007, I11): a operação muda o roteamento humano sem depender de desenvolvimento.
export function QueuesEditor({ token }: { token: string }) {
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [queues, teams, analysts] = await Promise.all([fetchQueues(token), fetchTeams(token), fetchAnalysts(token)]);
      setData({ queues, teams, analysts });
      setError(null);
    } catch (failure) {
      setError(describeError(failure, "Não foi possível carregar filas e equipes."));
    }
  }, [token]);

  useEffect(() => {
    const timer = setTimeout(() => void load(), 0);
    return () => clearTimeout(timer);
  }, [load]);

  async function act(action: () => Promise<unknown>, fallback: string) {
    try {
      await action();
      setError(null);
    } catch (failure) {
      setError(describeError(failure, fallback));
    } finally {
      await load();
    }
  }

  if (!data) return error ? <p className="p-6 text-sm text-faint">{error}</p> : <LoadingScreen label="Carregando as filas…" />;

  return (
    <div className="flex-1 space-y-8 overflow-y-auto p-6">
      {error && (
        <p role="alert" className="text-xs text-danger">
          {error}
        </p>
      )}

      <div className="grid gap-6 xl:grid-cols-2">
        {BRANDS.map((brand) => (
          <section key={brand} aria-label={`Filas ${BRAND_LABELS[brand]}`} className="rounded-lg border border-line bg-surface">
            <h2 className="flex items-center gap-2 border-b border-line px-4 py-3 text-sm font-semibold text-text">
              Filas {BRAND_LABELS[brand]}
            </h2>
            <ul className="divide-y divide-line">
              {data.queues
                .filter((queue) => queue.brand === brand)
                .map((queue) => (
                  <QueueRow
                    key={queue.id}
                    queue={queue}
                    teams={data.teams}
                    onRename={(name) => act(() => updateQueue(token, queue.id, { name }), "Não foi possível renomear.")}
                    onTeam={(teamId) => act(() => updateQueue(token, queue.id, { team_id: teamId }), "Não foi possível trocar a equipe.")}
                  />
                ))}
            </ul>
          </section>
        ))}
      </div>

      <NewQueue teams={data.teams} onCreate={(queue) => createQueue(token, queue).then(load)} />

      <div>
        <h2 className="text-sm font-semibold text-text">Equipes</h2>
        <div className="mt-3 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {data.teams.map((team) => (
            <TeamCard
              key={team.id}
              team={team}
              analysts={data.analysts}
              onAdd={(userId) => act(() => addMember(token, team.id, userId), "Não foi possível adicionar.")}
              onRemove={(userId) => act(() => removeMember(token, team.id, userId), "Não foi possível remover.")}
            />
          ))}
        </div>
      </div>

      <NewTeam onCreate={(team) => createTeam(token, team).then(load)} />
    </div>
  );
}

function QueueRow({
  queue,
  teams,
  onRename,
  onTeam,
}: {
  queue: Queue;
  teams: Team[];
  onRename: (name: string) => void;
  onTeam: (teamId: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(queue.name);

  return (
    <li className="flex items-center gap-3 px-4 py-2.5">
      <div className="min-w-0 flex-1">
        {editing ? (
          <form
            onSubmit={(event) => {
              event.preventDefault();
              setEditing(false);
              if (name.trim() && name.trim() !== queue.name) onRename(name.trim());
            }}
            className="flex gap-2"
          >
            <label htmlFor={`rename-${queue.id}`} className="sr-only">
              Novo nome da fila {queue.name}
            </label>
            <input id={`rename-${queue.id}`} value={name} onChange={(event) => setName(event.target.value)} className={input} autoFocus />
            <button type="submit" className={button}>
              Salvar
            </button>
          </form>
        ) : (
          <p className="flex items-center gap-2 text-sm">
            <span className="truncate">{queue.name}</span>
            {queue.default && <span className="rounded border border-accent/40 px-1.5 font-mono text-[10px] text-accent">padrão</span>}
            <button type="button" onClick={() => setEditing(true)} className="text-[11px] text-faint underline-offset-2 hover:text-text hover:underline">
              Renomear
            </button>
          </p>
        )}
        <p className="font-mono text-[11px] text-faint">{queue.slug}</p>
      </div>
      <label htmlFor={`team-${queue.id}`} className="sr-only">
        Equipe da fila {queue.name}
      </label>
      <select
        id={`team-${queue.id}`}
        value={queue.team.id}
        onChange={(event) => onTeam(event.target.value)}
        className="h-8 w-48 rounded-md border border-line-strong bg-bg px-2.5 text-xs text-text outline-none hover:border-faint focus:border-accent"
      >
        {teams.map((team) => (
          <option key={team.id} value={team.id}>
            {team.name}
          </option>
        ))}
      </select>
    </li>
  );
}

function NewQueue({
  teams,
  onCreate,
}: {
  teams: Team[];
  onCreate: (queue: { brand: string; slug: string; name: string; team_id: string }) => Promise<unknown>;
}) {
  const [brand, setBrand] = useState("infinitepay");
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [teamId, setTeamId] = useState(teams[0]?.id ?? "");
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    try {
      await onCreate({ brand, name: name.trim(), slug: slug.trim(), team_id: teamId });
      setName("");
      setSlug("");
      setError(null);
    } catch (failure) {
      setError(describeError(failure, "Não foi possível criar a fila."));
    }
  }

  return (
    <form aria-label="Nova fila" onSubmit={submit} className="rounded-lg border border-dashed border-line-strong p-5">
      <h2 className="text-sm font-semibold text-text">Nova fila</h2>
      <div className="mt-3 grid gap-3 md:grid-cols-4">
        <Field id="queue-brand" label="Marca">
          <select id="queue-brand" value={brand} onChange={(event) => setBrand(event.target.value)} className={input}>
            {BRANDS.map((value) => (
              <option key={value} value={value}>
                {BRAND_LABELS[value]}
              </option>
            ))}
          </select>
        </Field>
        <Field id="queue-name" label="Nome">
          <input id="queue-name" value={name} onChange={(event) => setName(event.target.value)} className={input} />
        </Field>
        <Field id="queue-slug" label="Identificador">
          <input id="queue-slug" value={slug} onChange={(event) => setSlug(event.target.value)} placeholder="credito-jim" className={`${input} font-mono`} />
        </Field>
        <Field id="queue-team" label="Equipe">
          <select id="queue-team" value={teamId} onChange={(event) => setTeamId(event.target.value)} className={input}>
            {teams.map((team) => (
              <option key={team.id} value={team.id}>
                {team.name}
              </option>
            ))}
          </select>
        </Field>
      </div>
      <div className="mt-3 flex items-center gap-3">
        <button type="submit" disabled={!name.trim() || !slug.trim()} className={button}>
          Criar fila
        </button>
        {error && (
          <p role="alert" className="text-xs text-danger">
            {error}
          </p>
        )}
      </div>
    </form>
  );
}

function TeamCard({
  team,
  analysts,
  onAdd,
  onRemove,
}: {
  team: Team;
  analysts: Analyst[];
  onAdd: (userId: string) => void;
  onRemove: (userId: string) => void;
}) {
  const candidates = analysts.filter((analyst) => !team.members.some((member) => member.id === analyst.id));
  const [selected, setSelected] = useState(candidates[0]?.id ?? "");
  const choice = candidates.some((analyst) => analyst.id === selected) ? selected : (candidates[0]?.id ?? "");

  return (
    <section aria-label={`Equipe ${team.name}`} className="rounded-lg border border-line bg-surface p-4">
      <h3 className="text-sm font-semibold">{team.name}</h3>
      <p className="mt-0.5 font-mono text-[11px] text-faint">
        {team.queues.length > 0 ? `Filas: ${team.queues.join(", ")}` : "Sem filas"}
      </p>
      <ul className="mt-3 flex flex-wrap gap-1.5">
        {team.members.length === 0 && <li className="text-xs text-faint">Sem analistas.</li>}
        {team.members.map((member) => (
          <li key={member.id} className="flex items-center gap-1 rounded-md bg-elevated py-0.5 pr-0.5 pl-2 text-xs">
            {member.name}
            <button
              type="button"
              aria-label={`Remover ${member.name}`}
              onClick={() => onRemove(member.id)}
              className="flex size-5 items-center justify-center rounded text-faint transition-colors hover:bg-danger/12 hover:text-danger"
            >
              <X aria-hidden className="size-3" strokeWidth={2} />
            </button>
          </li>
        ))}
      </ul>
      {candidates.length > 0 && (
        <div className="mt-3 flex gap-2">
          <label htmlFor={`add-${team.id}`} className="sr-only">
            Adicionar à equipe {team.name}
          </label>
          <select
            id={`add-${team.id}`}
            value={choice}
            onChange={(event) => setSelected(event.target.value)}
            className="h-8 flex-1 rounded-md border border-line-strong bg-bg px-2.5 text-xs text-text outline-none hover:border-faint focus:border-accent"
          >
            {candidates.map((analyst) => (
              <option key={analyst.id} value={analyst.id}>
                {analyst.name}
              </option>
            ))}
          </select>
          <button type="button" onClick={() => choice && onAdd(choice)} className={button}>
            Adicionar
          </button>
        </div>
      )}
    </section>
  );
}

function NewTeam({ onCreate }: { onCreate: (team: { slug: string; name: string }) => Promise<unknown> }) {
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    try {
      await onCreate({ name: name.trim(), slug: slug.trim() });
      setName("");
      setSlug("");
      setError(null);
    } catch (failure) {
      setError(describeError(failure, "Não foi possível criar a equipe."));
    }
  }

  return (
    <form aria-label="Nova equipe" onSubmit={submit} className="rounded-lg border border-dashed border-line-strong p-5">
      <h2 className="text-sm font-semibold text-text">Nova equipe</h2>
      <div className="mt-3 grid gap-3 md:grid-cols-3">
        <Field id="team-name" label="Nome da equipe">
          <input id="team-name" value={name} onChange={(event) => setName(event.target.value)} className={input} />
        </Field>
        <Field id="team-slug" label="Identificador da equipe">
          <input id="team-slug" value={slug} onChange={(event) => setSlug(event.target.value)} className={`${input} font-mono`} />
        </Field>
        <div className="flex items-end">
          <button type="submit" disabled={!name.trim() || !slug.trim()} className={button}>
            Criar equipe
          </button>
        </div>
      </div>
      {error && (
        <p role="alert" className="mt-2 text-xs text-danger">
          {error}
        </p>
      )}
    </form>
  );
}

function Field({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  return (
    <div>
      <label htmlFor={id} className={labelClass}>
        {label}
      </label>
      <div className="mt-1.5">{children}</div>
    </div>
  );
}
