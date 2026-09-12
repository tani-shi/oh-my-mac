# Codex instructions

## Task titles

- When the user's objective becomes materially clearer or changes and the current task title no longer represents it, rename the task to a concise Japanese noun phrase describing the current deliverable.
- Treat implementation details, status questions, and small refinements as the same objective.

## Git

- Name branches after the change they contain, using a suitable prefix such as `feat/`, `fix/`, `docs/`, or `refactor/`, rather than an agent-specific prefix such as `codex/`.

## Subagents

- Use subagents for independent read-only work when parallelism materially helps; keep small, single-source checks direct.
- Do not assume a subagent receives AGENTS.md; restate the constraints it must follow in the delegation prompt.
- Compose by orthogonal roles, not headcount.
