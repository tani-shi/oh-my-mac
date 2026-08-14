# Global instructions

## Language

- Write code, config files, and commit messages in English, regardless of the prompt's language.
- Reply to the user in Japanese, regardless of the language used in the prompt.
- For human-facing documentation (README, guides, and similar prose meant for readers), match the language of the prompt.

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
- Finishing a task is not a request to commit. Commit only when the user asks for it in that turn.
- Bundle all related changes (code, config, generated files) into a single commit.
- After merging a branch, delete the merged branch locally and from its remote.
- Switch branches with `git switch` and unstage with `git restore --staged`.
- Discard working-tree changes, untracked files (`--untracked`), commits (`--hard`), or everything since a revision (`--source=<rev>`) with `git discard`, which snapshots to `refs/discard/*` first; recover with `git discard --undo`.

## Shell

- Pick the deletion tool by how the target comes back:
  - `rm` — what a rerun regenerates: ignored build output, paths under a temporary directory, state a script itself writes.
  - `git rm -r` — tracked files.
  - `git discard --untracked` — untracked work in a repository.
  - `trash` — user data with no other way back.

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

- Update README.md in the same changeset as a change to what a project does, how it's used, or how it's configured.
- Update a project's agent instructions when the change alters how an agent must work in it — a new constraint, a moved workflow, a rule that no longer holds. A change the instructions do not speak to leaves them untouched.

## Project agent instructions

- Reach for this layout when the task itself is to initialize or standardize a repository's agent instructions:
  - `AGENTS.md` — the rules every agent follows. Codex discovers it by name.
  - `CLAUDE.md` — Claude Code loads this file; do not count on it discovering `AGENTS.md` on its own. Wherever Claude Code is used this file exists and carries the line `@AGENTS.md` ahead of anything it adds. Rules only Claude Code follows go below that line; with none, the import is the whole point of the file.
  - `.codex/config.toml` — rules only Codex follows, as `developer_instructions`. Write it once such a rule exists.
- A repository that already has its own convention keeps it until the user asks to migrate; unrelated work leaves its instruction files alone.
