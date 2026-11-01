---
name: ship-change
description: Prepare verified repository changes for delivery by committing, pushing a focused branch, and opening a pull request. Use when the user asks to commit, publish, deliver, or create a PR; do not use to merge or approve the work.
---

# Ship change

Deliver the current task without expanding its implementation scope.

1. Read `AGENTS.md` and `docs/context/STATE.md`; inspect branch, status, diff, and remote.
2. Refuse to ship from `main`. Create a focused branch if the work has not yet been committed.
3. Separate unrelated user changes. Never stage secrets, local environments, generated noise, or
   files outside the task.
4. Run the smallest relevant checks and the repository gate when available. Stop on a failure
   unless the user explicitly changes the task to remediation.
5. Update tests, task documentation, and `STATE.md` only when their truth changed.
6. Review the final diff and staged diff, then create a Conventional Commit describing the result.
7. Before push or PR creation, confirm the current task authorizes those external writes. Never
   force-push, bypass protection, or reuse stale authorization for a different repository.
8. Push the branch and open a PR against `main` using the repository template. Include observed
   checks, risks, recovery notes, and whether context/ADRs changed.

Stop after creating the PR. Do not approve or merge it. Report the branch, commit, PR link, checks,
and any evidence the independent `$review-pr` pass still needs.
