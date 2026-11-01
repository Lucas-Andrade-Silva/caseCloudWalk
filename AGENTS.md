# CloudWalk project instructions

This repository is developed by one person with Codex acting as an engineering partner.
The product scope is intentionally undefined until the TAPI is recorded. Do not infer the
solution, stack, architecture, or CloudWalk requirements from the reference projects.

## Start every task here

1. Read `docs/context/STATE.md` for the current snapshot.
2. Read only the product, decision, and code files needed for the request.
3. Inspect the current branch, worktree, and relevant tests before writing.

Do not preload historical context. `docs/context/REFERENCE_AUDIT.md` is background material,
not required reading for ordinary tasks.

## Sources of truth

- `AGENTS.md`: durable engineering rules.
- `docs/context/STATE.md`: short, mutable handoff between chats.
- `docs/decisions/`: accepted architectural and process decisions.
- Product goals and plans: to be created from the TAPI; do not invent them beforehand.
- Code, tests, and observed command output outrank stale prose.

When sources conflict, stop and surface the conflict. Never silently rewrite an accepted
decision or claim that an unexecuted check passed.

## Context economy

- Keep `STATE.md` below 120 lines and useful to a new chat.
- Update it after a material decision, merged capability, new blocker, or changed next step.
- Replace stale status; do not turn it into a chronological log.
- Record durable rationale once in `docs/decisions/` and link it from `STATE.md`.
- Put detailed evidence in the PR, test output, or a focused document instead of duplicating it.

## Git and pull-request workflow

- Never implement on `main`. Create or switch to a focused branch before the first write.
- Use `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, or `chore/` plus a short kebab-case name.
- Preserve unrelated user changes. Commit only files belonging to the current task.
- Use Conventional Commit messages and keep commits reviewable.
- Never force-push, bypass checks, merge with unresolved blocking findings, or commit secrets.
- Every content change reaches `main` through a pull request.
- The authoring chat must not approve its own PR. Run `$review-pr` in a separate Codex chat or
  independent review task.
- Merge only when required checks pass and the independent review verdict is `APPROVE`.
- Use `$ship-change` when the user asks to commit, publish, or open the pull request.
- External writes still require the authorization applicable to the current task and tools.

## Engineering standard

- Diagnose before editing and change the narrowest responsible layer.
- Prefer explicit contracts, typed boundaries, deterministic behavior, and small modules.
- Separate domain logic from providers, orchestration, transport, and presentation.
- Keep core tests offline and deterministic. Isolate live model/provider checks.
- For AI behavior, version representative cases and measurable evals; do not rely on demos alone.
- Treat prompts, model settings, retrieval parameters, and evaluation data as versioned behavior.
- Validate untrusted input, minimize credentials and personal data, and avoid logging secrets.
- Add dependencies only for a demonstrated need; record consequential choices in an ADR.
- Do not copy code or scaffolding from prior projects without a requirement and a fit analysis.

## Verification and completion

Before declaring a task complete:

1. Run the smallest relevant checks, then the broader repository gate when available.
2. Review `git diff` for scope, secrets, generated noise, and accidental regressions.
3. Update tests, documentation, and `STATE.md` when their truth changed.
4. Report commands actually run, results, residual risks, and anything not verified.

A task is not done because code exists; it is done when its acceptance criteria have evidence.
