# Claude Code

@AGENTS.md

## Claude Code Settings

- NEVER edit files under `~/.claude/` directly.
- Always edit the source files under `config/claude/` in this repository instead.
  - `config/agents/instructions.md` + `config/claude/instructions.md` → concatenated into `~/.claude/CLAUDE.md`
  - `config/claude/settings.json` → merged into `~/.claude/settings.json`
  - `config/claude/keybindings.json` → merged into `~/.claude/keybindings.json`
  - `config/claude/scripts/*` → synced to `~/.claude/scripts/`
  - `config/claude/agents/*.md` → synced to `~/.claude/agents/` (reusable subagents / Agent Teams teammates)
  - `config/claude/skills/*/SKILL.md` → synced to `~/.claude/skills/` (personal skills, auto-loaded as `<name>@skills-dir`)
  - `config/claude/plugins.txt` → the full set of user-scope plugins; `make sync-claude-plugins` installs what is listed and uninstalls what is not
- Repository dependency upgrades run through the Codex-only `$upgrade` skill. Claude Code remains a managed upgrade target but does not host that workflow.
