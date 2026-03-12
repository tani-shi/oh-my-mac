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

## Skills

- When writing code that uses external libraries/frameworks, always look up the latest documentation using context7 MCP tools (`resolve-library-id` then `query-docs`) before writing implementation code.
- When multiple skills could apply, prefer process skills (brainstorming, debugging) before implementation skills.
