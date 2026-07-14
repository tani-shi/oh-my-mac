# CLAUDE.md

## Language

- Write code, config files, and commit messages in English, regardless of the prompt's language.
- For conversation and human-facing documentation (README, guides, and similar prose meant for readers), match the language of the prompt.

## Git

- Use conventional commit style (e.g., `feat:`, `fix:`, `docs:`, `refactor:`).
- Use `--force-with-lease` instead of `--force` when force pushing.
- Never commit automatically after completing work. Only commit when explicitly asked.
- Bundle all related changes (code, config, generated files) into a single commit.

## Shell

- Use `trash` instead of `rm -rf` for file deletion.

## Python

- Use `uv` instead of `pip` / `pip3` / `python` / `python3`.

## Comments

- Each kind of explanation has its home: **code** carries *how*, **tests** carry *what*, **commit logs** carry *why*, and **comments** carry *why-not* — the reasons for the paths not taken. When a comment states plain *why* that belongs in the commit log, or *what* that belongs in a test, it is misplaced.
- Code is the primary medium of explanation: design, naming, and small well-bounded units carry the meaning. Default to zero comments.
- A comment that explains *what* code does is a refactoring signal — rename, extract, or restructure until the comment is unnecessary, then delete it instead of writing it.
- The comments that belong in code state *why-not*: the rationale for a decision deliberately not taken, kept where the alternative is plausible enough that a reader would re-introduce it or flag its absence. External-constraint comments are the concrete forms of this — references to external specs, workarounds for upstream bugs (with links), invariants and concurrency constraints, the rationale behind non-obvious values — each answering "why this form and not the obvious alternative".
- Public API doc comments (docstrings, JSDoc) follow the project's existing convention; they document contracts for toolchains, not implementation.
- Comments, docs, and code state present-tense technical facts — never the conversation, the instructions given, or a narration of what was changed, removed, or avoided in this session. This bans change-narration residue, not durable design why-not: a "don't do X" note stating the lasting technical reason (e.g., `avoid X here: it deadlocks under load`) is exactly the why-not that belongs in code.

## Refactoring

- When changing code, restructure within the touched scope instead of appending: prefer renaming, extracting, and deleting over adding branches, flags, and wrapper layers.
- Existing code has no authority merely because it exists. Reshape the code you touch into the best form for the current requirements rather than deferring to its current shape.
- Keep each unit at the minimum size that fully expresses its behavior; growth of a file or function is a design signal, not a default.
- Write only what a current caller needs: no speculative abstractions, options, or parameters for imagined futures — generality is added when the second caller arrives.
- Delete dead weight on contact: unused code, commented-out code, and TODOs with no owner are removed, not preserved. A TODO/FIXME carrying both a rationale and a tracking reference (issue, ticket) is why-not, not ownerless dead weight — keep it.
- Outside the touched scope, report refactoring opportunities instead of applying them.

## Documentation

- When your changes affect what a project does, how it's used, or how it's configured, update README.md and CLAUDE.md (if they exist) in the same changeset.
- Focus on sections that describe the changed functionality (feature lists, configuration tables, usage examples, setup instructions).

## Subagents & Agent Teams

- For investigation and side-effect-free operations (file reads, searches, code exploration, reviews), run multiple agents in parallel via the Agent tool.
- Launch independent queries as concurrent agents in a single message; reserve sequential execution for steps with dependencies.
- Default to unnamed background subagents: results return directly as tool results with no coordination overhead.
- Read-only fan-out (parallel finders, verifiers, searchers) is always unnamed subagents, never a team.
- Use named teammates (Agent Teams) only for stateful collaboration where agents must respond to each other across turns. Compose by orthogonal roles, not headcount: 2 for pair work (implementer + reviewer), 3 for discussion (proponent, opponent, synthesizer) — 3 is the upper bound, since communication paths and coordination cost grow quadratically.
- When more perspectives are needed than a team allows, generate them independently with unnamed subagents and synthesize; independent generation preserves diversity that live discussion collapses.
- When a defined agent in ~/.claude/agents/ fits the role, pass it as subagent_type instead of a generic agent.