# Global instructions

## Language

- Write code, config files, code comments, and commit messages in English, regardless of the prompt's language.
- Write README files in English for public repositories and in Japanese for non-public repositories, regardless of the prompt's language.
- Write pull request and issue title summaries, their descriptions, code review comments, guides, release notes, and human-facing documentation other than README files in Japanese, regardless of the prompt's language.
- Reply to the user in Japanese, regardless of the language used in the prompt.

## Wording

- Write comments, commit messages, and docs from the current code for readers outside the conversation. Read the surrounding text and match its style.
- Keep agent instructions focused on durable outcomes, ownership boundaries, non-obvious constraints, and authorized scope; the agent chooses a workflow that satisfies them. Fix failures at their owning layer; reserve instructions for durable knowledge that layer cannot enforce.
- Use existing codebase vocabulary or plain technical English.
- Keep each Markdown prose paragraph on one unwrapped source line; reserve new lines for paragraph boundaries and Markdown structure.
- In Japanese documents and messages, do not mechanically insert spaces between Japanese text and Latin letters or digits. Preserve spaces required by syntax or official names.
- State verified facts directly; distinguish inferences, proposals, and preferences from facts and decisions.

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

- Implement the agreed goal and acceptance criteria. Resolve material uncertainty about scope or behavior before dependent implementation. Investigate available facts and choose routine implementation details independently; ask for missing decisions, and proceed when the request is clear.

## Comments

Comments direct limited reader attention to important details; keep them minimal so warnings remain noticeable. Names, types, and structure explain ordinary code.

- Record facts readers could miss from the code that could lead to misunderstanding or an incorrect change. Place one short point where attention is needed.
- Link supporting evidence when useful. Keep extended explanations in documentation or commit history, with a brief local pointer when needed.
- Document public API contracts according to the project's existing convention.

## Refactoring

- Choose a simple, understandable structure that satisfies the current requirements.
- Introduce abstractions, options, and shared code when concrete current needs justify them.
- Limit structural improvements and removal of unused code to what the current goal requires. Report material issues outside that scope.

## Debugging

- Identify the root cause before proposing any fix; a change that only removes the symptom is not a fix.
- Test one hypothesis at a time with the smallest change that discriminates it — never stack a fix on top of an unverified one.
- Fix at the shared function and check its other callers; repairing only the path the report names leaves the siblings broken.

## Verification

- Derive expected results from agreed requirements, confirmed examples, or external specifications, not solely from the current implementation or its output. Resolve discrepancies against those sources.
- Verify observable results by executing the code and relevant dependencies. Limit stubs and mocks to boundaries impractical to exercise; they do not verify real integration. Source structure, internal calls, and passing tests alone do not establish correctness.
- Separate current-change verification from retained regression tests. Verify important behavior even when expensive; retain tests that detect requirement violations cheaply and reliably at justified maintenance cost. Consider failure impact, recurrence risk, and existing coverage, not test counts or coverage targets. Temporary checks need not be retained.
- Apply these criteria when reviewing tests. Within the change's scope, remove or simplify implementation-derived expectations without independent justification, source-text checks unrelated to requirements, redundant cases, and excessive stubs or mocks. Preserve checks of public output whose text or format is a requirement.
- Report verification steps, expected and observed results, and unverified behavior; include them in PR descriptions for human audit. Never claim an unperformed check is complete.

## Documentation

- Update README.md when a change makes its existing description inaccurate or leaves out information needed to use the project.
- Keep README.md focused on information human readers need to use the project. Use headings, tables, or diagrams where they reduce the reading needed; omit prose that repeats what names or structure already make clear.
- Update a project's agent instructions when the change alters how an agent must work in it — a new constraint, a moved workflow, a rule that no longer holds. A change the instructions do not speak to leaves them untouched.
