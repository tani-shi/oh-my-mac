# Global instructions

## Language

Use these languages regardless of the prompt's language:

- English: code, config files, code comments, commit messages, and README files in public repositories.
- Japanese: all other human-facing text.

## Writing and documentation

- Human-facing text minimizes the reader's cognitive load.
- Omit conversational rebuttals, discarded approaches, internal processing details, and incidental background.
- In Japanese documents and messages, do not mechanically insert spaces between Japanese text and Latin letters or digits. Preserve spaces required by syntax or official names.
- Agent instructions contain current durable outcomes, ownership boundaries, non-obvious constraints, and authorized scope.
- They omit obsolete, duplicate, and historical guidance.
- Fix failures at their owning layer.

## Comments

- Keep comments minimal so important warnings remain visible. Names, types, and structure explain ordinary code.
- Record non-obvious facts that could prevent incorrect changes where they matter.
- Link evidence when useful. Keep long explanations in documentation or commit history.
- Document public API contracts according to the project's convention.

## Tests

- Verification checks may be temporary.
- Keep new automated tests in Git only when explicitly requested.

## Git

- Switch branches with `git switch` and unstage with `git restore --staged`.
- Use `git discard` for destructive Git cleanup; it snapshots changes to `refs/discard/*` first.
- Recover discarded work with `git discard --undo`.
- Commit only when the user requests it in the current turn.
- Bundle related changes into a single commit.
- Use Conventional Commits.
- A commit message states the rationale for the change, not just a conventional-commit type prefix.
- Format pull request and issue titles as `<type>: <Japanese summary>` using a conventional type.
- Use `--force-with-lease` instead of `--force` when force pushing.
- After merging a branch, delete the merged branch locally and from its remote.

## Shell

- Use `rm` for generated or temporary files that can be recreated.
- Use `git rm -r` for tracked files.
- Use `git discard --untracked` for untracked repository files.
- Use `trash` for user data without another recovery path.

## Python

- Use `uv` instead of `pip` / `pip3` / `python` / `python3`.
