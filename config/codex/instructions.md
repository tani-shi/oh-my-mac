## Task titles

- When the user's objective becomes materially clearer or changes and the current task title no longer represents it, rename the task to a concise Japanese noun phrase describing the current deliverable.
- Treat implementation details, status questions, and small refinements as the same objective.

## Git

- Name branches after the change they contain, using a suitable prefix such as `feat/`, `fix/`, `docs/`, or `refactor/`, rather than an agent-specific prefix such as `codex/`.

## Subagents

- Use subagents for independent read-only work when parallelism materially helps; keep small, single-source checks direct.
- Do not assume a subagent receives AGENTS.md; restate the constraints it must follow in the delegation prompt.
- Compose by orthogonal roles, not headcount.

## Refactoring reviews

- Treat `codex review` as a read-only selection gate. For structural simplification, return at most three repository-backed findings, ranked by material impact and repair value. Prefer shared causes and structural failures over isolated symptoms; omit cosmetic, refuted, low-value, and speculative edge cases whose reachability or impact is not evidenced by the repository.
- Mark a finding `APPLY` only when repository evidence proves the change behavior-preserving. Mark it `ASK` when an external contract or design choice requires human judgment. Apply neither during review; use a follow-up change task for approved findings and run the relevant tests.
