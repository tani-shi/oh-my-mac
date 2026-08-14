## Git

- Name branches after the change they contain, using a suitable prefix such as `feat/`, `fix/`, `docs/`, or `refactor/`, rather than an agent-specific prefix such as `codex/`.

## Subagents

- Use subagents for independent read-only work when parallelism materially helps; keep small, single-source checks direct.
- Do not assume a subagent receives AGENTS.md; restate the constraints it must follow in the delegation prompt.
- Compose by orthogonal roles, not headcount.

## Refactoring reviews

- Treat `codex review` as a read-only selection gate. For structural simplification, return at most three material findings, ranked by value; omit cosmetic, refuted, and low-value candidates.
- Mark a finding `APPLY` only when repository evidence proves the change behavior-preserving. Mark it `ASK` when an external contract or design choice requires human judgment. Apply neither during review; use a follow-up change task for approved findings and run the relevant tests.
