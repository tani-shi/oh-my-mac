# CLAUDE.md

## Language

- Never use Japanese in code, config files, or commit messages.
- Use Japanese only in conversation.

## Git

- Use conventional commit style (e.g., `feat:`, `fix:`, `docs:`, `refactor:`).
- Use `--force-with-lease` instead of `--force` when force pushing.

## Shell

- Use `trash` instead of `rm -rf` for file deletion.

## Python

- Use `uv` instead of `pip` / `pip3` / `python` / `python3`.

## Documentation

- When your changes affect what a project does, how it's used, or how it's configured, update README.md and CLAUDE.md (if they exist) in the same changeset.
- Focus on sections that describe the changed functionality (feature lists, configuration tables, usage examples, setup instructions).

## Agent Teams

- When performing investigation or side-effect-free operations (file reads, searches, code exploration), use the Agent tool to run multiple agents in parallel.
- Launch independent queries as concurrent agents in a single message rather than running them sequentially.
- Reserve sequential execution for tasks with dependencies between steps.