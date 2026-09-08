# Global instructions

## Language

- Write code, config files, code comments, and commit messages in English, regardless of the prompt's language.
- Write README files in English for public repositories and in Japanese for non-public repositories, regardless of the prompt's language.
- Write pull request and issue title summaries, their descriptions, code review comments, guides, release notes, and human-facing documentation other than README files in Japanese, regardless of the prompt's language.
- Reply to the user in Japanese, regardless of the language used in the prompt.

## Wording

Comments, commit messages, and docs reach a reader who was not part of the conversation that produced them.

- Write from the code as it stands, not from the discussion that changed it. After a long exchange, read the surrounding lines first and match how they read.
- State what holds. Agent instructions carry durable outcomes, ownership boundaries, non-obvious constraints, and authorized scope; the agent chooses a workflow that satisfies them. Correct failures at their owning layer, with prompt guidance reserved for durable knowledge that layer cannot enforce.
- Use words that already appear in this codebase or in plain technical English. A term invented during a discussion stays there.
- Keep each Markdown prose paragraph on one unwrapped source line; reserve new lines for paragraph boundaries and Markdown structure.

## Git

- Use conventional commit style (e.g., `feat:`, `fix:`, `docs:`, `refactor:`).
- Format pull request and issue titles as `<type>: <Japanese summary>`, using a suitable conventional commit type.
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

## Requirements

- Resolve uncertainty about the goal, scope, or expected behavior before implementation that depends on the answer. Ask when the decision would materially change the result; investigate facts available in existing sources and choose routine implementation details independently. Proceed when the request is already clear.
- Use the agreed goal and acceptance criteria as the basis for implementation and verification.

## Comments

Comments direct the reader's limited attention to important details. Excess commentary makes important warnings easier to skip. Ordinary code communicates through names, types, and structure; keep comments minimal.

- Record facts a reader could miss from the code that could lead to an incorrect understanding or change.
- Place one short point at the location that needs the reader's attention.
- Link to evidence for constraints such as external specifications and compatibility requirements when useful.
- Keep extended explanations in documentation or commit history, with a brief local pointer when needed.
- Public API doc comments (docstrings, JSDoc) document contracts according to the project's existing convention.

## Refactoring

- Choose a simple, understandable structure that satisfies the current requirements.
- Introduce abstractions, options, and shared code when concrete current needs justify them.
- Limit structural improvements and removal of unused code to what the current goal requires. Report material issues outside that scope.

## Debugging

- Identify the root cause before proposing any fix; a change that only removes the symptom is not a fix.
- Test one hypothesis at a time with the smallest change that discriminates it — never stack a fix on top of an unverified one.
- Fix at the shared function and check its other callers; repairing only the path the report names leaves the siblings broken.

## Verification

- Derive expected results from agreed acceptance criteria, confirmed examples, or external specifications. Resolve discrepancies between the implementation and expected results by returning to those sources.
- Verify the current change and decide separately which regression tests are worth retaining. Select cases by the impact of failure, likelihood of recurrence, existing coverage, and maintenance cost.
- Report the behavior verified and the limits of that evidence.

## Documentation

- Update README.md in the same changeset as a change to what a project does, how it's used, or how it's configured.
- Update a project's agent instructions when the change alters how an agent must work in it — a new constraint, a moved workflow, a rule that no longer holds. A change the instructions do not speak to leaves them untouched.

## Project agent instructions

- Reach for this layout when the task itself is to initialize or standardize a repository's agent instructions:
  - `AGENTS.md` — the rules every agent follows. Codex discovers it by name.
  - `CLAUDE.md` — Claude Code loads this file; do not count on it discovering `AGENTS.md` on its own. Wherever Claude Code is used this file exists and carries the line `@AGENTS.md` ahead of anything it adds. Rules only Claude Code follows go below that line; with none, the import is the whole point of the file.
  - `.codex/config.toml` — rules only Codex follows, as `developer_instructions`. Write it once such a rule exists.
- A repository that already has its own convention keeps it until the user asks to migrate; unrelated work leaves its instruction files alone.
