# CLAUDE.md

## Claude Code Settings

- NEVER edit files under `~/.claude/` directly.
- Always edit the source files under `config/claude/` in this repository instead.
  - `config/claude/CLAUDE.md` → synced to `~/.claude/CLAUDE.md`
  - `config/claude/settings.json` → merged into `~/.claude/settings.json`
- Run `./sync-config.zsh` to apply changes to the local environment.
