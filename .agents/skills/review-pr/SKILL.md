---
name: review-pr
description: Independently review a pull request for correctness, regressions, security, scope, and verification evidence, then issue a release verdict. Use for PR review or merge-readiness checks; do not use to author the same change.
---

# Review pull request

Review as an independent release gate. Default to read-only.

1. Read `AGENTS.md`, `docs/context/STATE.md`, the PR description, base/head diff, and changed tests.
2. Reconstruct the requested behavior and acceptance criteria. Treat code and observed evidence as
   stronger than the PR narrative.
3. Inspect for correctness, regressions, security/privacy exposure, failure handling, unnecessary
   complexity, dependency growth, scope drift, stale context, and missing tests/evals.
4. Run focused checks and the broader gate when practical. Distinguish pass, fail, unavailable,
   and not run; never infer success from CI configuration alone.
5. Report actionable findings first, each with severity, file/line, impact, and a concrete failure
   scenario. Use `P0` critical, `P1` high, `P2` medium, and `P3` low.

End with exactly one verdict:

- `APPROVE`: no P0/P1/P2 findings, required checks passed, and evidence is sufficient.
- `REQUEST_CHANGES`: any blocking finding, failed required check, or materially missing evidence.
- `BLOCKED`: the diff or required environment cannot be inspected after reasonable attempts.

Do not modify the branch, approve your own authored work, post externally, or merge unless the user
separately requests that mutation. If there are no findings, say so and list residual risks or
unverified checks.
