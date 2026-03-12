# CLAUDE.md

## Claude Code Settings

- NEVER edit files under `~/.claude/` directly.
- Always edit the source files under `config/claude/` in this repository instead.
  - `config/claude/CLAUDE.md` → synced to `~/.claude/CLAUDE.md`
  - `config/claude/settings.json` → merged into `~/.claude/settings.json`
  - `config/claude/plugins.txt` → installed via `claude plugin install`
- Run `make diff-config` to check differences, then `make sync-config` to apply.

## config.zsh

- Every sync operation MUST include a diff check — only write when the current state differs from the desired state. Never blindly overwrite.
- diff and sync modes share the same definitions (configs array, jq expressions, plist keys, etc.). When adding a new sync target, write both mode handlers in the same block.
