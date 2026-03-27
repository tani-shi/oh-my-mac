# CLAUDE.md

## Claude Code Settings

- NEVER edit files under `~/.claude/` directly.
- Always edit the source files under `config/claude/` in this repository instead.
  - `config/claude/CLAUDE.md` → synced to `~/.claude/CLAUDE.md`
  - `config/claude/settings.json` → merged into `~/.claude/settings.json`
  - `config/claude/keybindings.json` → merged into `~/.claude/keybindings.json`
  - `config/claude/scripts/check-docs.zsh` → synced to `~/.claude/scripts/check-docs.zsh`
  - `config/claude/plugins.txt` → installed via `claude plugin install`
- Run `make diff-config` to check differences, then `make sync-config` to apply.

## config.zsh

- Every sync operation MUST include a diff check — only write when the current state differs from the desired state. Never blindly overwrite.
- diff and sync modes share the same definitions (configs array, jq expressions, plist keys, etc.). When adding a new sync target, write both mode handlers in the same block.
- macOS defaults are managed via the `macos_defaults` array using `defaults read`/`defaults write`. Add new entries as `"domain:key:type:value"` (supported types: `bool`, `int`, `float`, `string`).

## Version Pinning

All external dependencies are version-pinned to prevent supply chain attacks. `make update` intentionally does NOT upgrade packages — it only installs missing ones and syncs config.

- **Homebrew**: `brew bundle --no-upgrade` prevents automatic upgrades. Use `make upgrade` to review and apply updates via Claude Code.
- **Claude Code**: Version is pinned in `config/claude/version`. `make install`/`make update` install only the pinned version.
- **Sheldon plugins**: Every plugin in `config/sheldon/plugins.toml` MUST have a `tag` (or `rev` if no tags exist). Never add a plugin without version pinning.
- **uv tools**: Tools in `config/uv/tools.txt` MUST use `@tag` or `@commit` suffix, except `claude-sentinel` (owned by the user, always uses HEAD).
- **Claude Code plugins**: Updated only via `make upgrade`, not automatically.

To upgrade dependencies, run `make upgrade` which launches Claude Code to investigate changelogs, security advisories, and incident reports before applying updates.
