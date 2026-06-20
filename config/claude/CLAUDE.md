# CLAUDE.md

## Language

- Never use Japanese in code, config files, or commit messages.
- Use Japanese only in conversation.

## Git

- Use conventional commit style (e.g., `feat:`, `fix:`, `docs:`, `refactor:`).
- Use `--force-with-lease` instead of `--force` when force pushing.
- Never commit automatically after completing work. Only commit when explicitly asked.
- Bundle all related changes (code, config, generated files) into a single commit.

## Shell

- Use `trash` instead of `rm -rf` for file deletion.

## Python

- Use `uv` instead of `pip` / `pip3` / `python` / `python3`.

## Documentation

- When your changes affect what a project does, how it's used, or how it's configured, update README.md and CLAUDE.md (if they exist) in the same changeset.
- Focus on sections that describe the changed functionality (feature lists, configuration tables, usage examples, setup instructions).

## Comments & Documentation

- Comments, docs, and code describe the current state and the technical reason something exists — never the conversation, the instructions you were given, or what was changed, removed, or avoided.
- Do not leave residue from our discussion. Phrases like "don't do X", "X is intentionally omitted", "removed per request", or "as instructed" are noise to any reader who wasn't part of the conversation.
- Exception: keep a "don't do X" note only when a reader who knows nothing about our conversation genuinely needs it, and then state the durable technical reason itself (e.g., `avoid X here: it deadlocks under load`) — not that it was requested.

## Agent Teams

- When performing investigation or side-effect-free operations (file reads, searches, code exploration), use the Agent tool to run multiple agents in parallel.
- Launch independent queries as concurrent agents in a single message rather than running them sequentially.
- Reserve sequential execution for tasks with dependencies between steps.