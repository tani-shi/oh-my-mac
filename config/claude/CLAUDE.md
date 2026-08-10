# CLAUDE.md

## Language

- Write code, config files, and commit messages in English, regardless of the prompt's language.
- For conversation and human-facing documentation (README, guides, and similar prose meant for readers), match the language of the prompt.

## Wording

Comments, commit messages, and docs reach a reader who was not part of the conversation that produced them.

- Write from the code as it stands, not from the discussion that changed it. After a long exchange, read the surrounding lines first and match how they read.
- State what holds. Write a prohibition only where a reader would otherwise take the rejected path; the reason it was rejected is the content, not the ban itself.
- One point per comment. Words like "so", "therefore", and "which means" carry a derivation that belongs in the commit log.
- Use words that already appear in this codebase or in plain technical English. A term invented during a discussion stays there.

## Git

- Use conventional commit style (e.g., `feat:`, `fix:`, `docs:`, `refactor:`).
- A commit message states the rationale for the change, not just a conventional-commit type prefix.
- Use `--force-with-lease` instead of `--force` when force pushing.
- Bundle all related changes (code, config, generated files) into a single commit.

## Shell

- Use `trash` instead of `rm -rf` for file deletion.

## Python

- Use `uv` instead of `pip` / `pip3` / `python` / `python3`.

## Comments

- Each kind of explanation has its home: **code** carries *how*, **tests** carry *what*, **commit logs** carry *why*, and **comments** carry *why-not* — why the code takes this form and not the plausible alternative a reader would otherwise reach for. When a comment states plain *why* that belongs in the commit log, or *what* that belongs in a test, it is misplaced.
- Code is the primary medium of explanation: design, naming, and small well-bounded units carry the meaning. Default to zero comments — a comment is the exception, earning its place only by carrying why-knowledge the code cannot express.
- A comment that explains *what* code does is a refactoring signal — rename, extract, or restructure until the comment is unnecessary, then delete it instead of writing it.
- External-constraint comments are the typical why-not: references to external specs, workarounds for upstream bugs (with links), invariants and concurrency constraints, the rationale behind non-obvious values.
- Public API doc comments (docstrings, JSDoc) follow the project's existing convention; they document contracts for toolchains, not implementation.

## Refactoring

- When changing code, restructure within the touched scope instead of appending: prefer renaming, extracting, and deleting over adding branches, flags, and wrapper layers.
- Existing code has no authority merely because it exists. Reshape the code you touch into the best form for the current requirements rather than deferring to its current shape.
- Keep each unit at the minimum size that fully expresses its behavior; growth of a file or function is a design signal, not a default.
- Name files and directories at the scope their cohesive contents share — the entity, not one operation on it. A grab-bag too broad to predict its contents and a name too narrow — a homeless fragment, or a real shared unit named after one operation so its cohesive siblings cannot land beside it — are equally scope failures; consolidate the fragment into its home, or rename the mis-scoped unit up to its entity scope.
- Write only what a current caller needs: no speculative abstractions, options, or parameters for imagined futures — generality is added when the second caller arrives.
- Delete dead weight on contact: unused code, commented-out code, and ownerless TODOs are removed, not preserved. A TODO/FIXME that records a lasting reason for the deferred work, traceable to where it is tracked, is not ownerless dead weight.
- Outside the touched scope, report refactoring opportunities instead of applying them.

## Debugging

- Identify the root cause before proposing any fix; a change that only removes the symptom is not a fix.
- Test one hypothesis at a time with the smallest change that discriminates it — never stack a fix on top of an unverified one.
- Fix at the shared function and check its other callers; repairing only the path the report names leaves the siblings broken.

## Documentation

- When your changes affect what a project does, how it's used, or how it's configured, update README.md and CLAUDE.md (if they exist) in the same changeset.

## Subagents & Agent Teams

- Run read-only work (searches, finders, verifiers, reviews) under a subagent type whose tool grants cannot write — `Explore`, not the default `general-purpose` — and fan it out as unnamed subagents, never a team. `Explore` and `Plan` do not receive CLAUDE.md, so a rule they must honor is restated in the delegation prompt.
- Use named teammates (Agent Teams) only for stateful collaboration where agents must respond to each other across turns. Compose by orthogonal roles, not headcount: 2 for pair work (implementer + reviewer), 3 for discussion (proponent, opponent, synthesizer) — 3 is the upper bound, since communication paths and coordination cost grow quadratically.
- When more perspectives are needed than a team allows, generate them independently with unnamed subagents and synthesize; independent generation preserves diversity that live discussion collapses.