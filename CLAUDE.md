# CLAUDE.md

## Claude Code Settings

- NEVER edit files under `~/.claude/` directly.
- Always edit the source files under `config/claude/` in this repository instead.
  - `config/claude/CLAUDE.md` → synced to `~/.claude/CLAUDE.md`
  - `config/claude/settings.json` → merged into `~/.claude/settings.json`
  - `config/claude/keybindings.json` → merged into `~/.claude/keybindings.json`
  - `config/claude/scripts/*` → synced to `~/.claude/scripts/`
  - `config/claude/agents/*.md` → synced to `~/.claude/agents/` (reusable subagents / Agent Teams teammates)
  - `config/claude/skills/*/SKILL.md` → synced to `~/.claude/skills/` (personal skills, auto-loaded as `<name>@skills-dir`)
  - `config/claude/plugins.txt` → the full set of user-scope plugins; `make sync-claude-plugins` installs what is listed and uninstalls what is not
- Run `make diff-config` to check differences, then `make sync-config` to apply.
- `.claude/` at the repository root is project scope: it configures Claude Code sessions run inside this repository and is not synced to `~/.claude/`.

## VSCode Settings

- NEVER edit `~/Library/Application Support/Code/User/settings.json` directly.
- Always edit the source files under `config/vscode/` in this repository instead.
  - `config/vscode/settings.json` → merged into `~/Library/Application Support/Code/User/settings.json`
  - `config/vscode/extensions.txt` → installed via `code --install-extension`
- Run `make diff-config` to check differences, then `make sync-config` to apply.

## config.zsh

- Every sync operation MUST include a diff check — only write when the current state differs from the desired state. Never blindly overwrite.
- diff and sync modes share the same definitions (configs array, jq expressions, plist keys, etc.). When adding a new sync target, write both mode handlers in the same block.
- macOS defaults are managed via the `macos_defaults` array using `defaults read`/`defaults write`. Add new entries as `"domain:key:type:value"` (supported types: `bool`, `int`, `float`, `string`).
- Global git config, including aliases such as `git discard`, is managed via the `git_config_keys` array as `"key:value"`. A script an alias invokes is synced through the `configs` array and run as `zsh <path>`, so it needs no executable bit — `sync_files` copies content only and never manages file modes.

## Tests

- `make test` runs `scripts/test-discard.zsh`. Add cases there when changing `config/git/discard.zsh`.
- Tests run against the repository copy of a script, never the synced copy under `$HOME`, so a change is verified before `make sync-config`.
- Each case runs in a throwaway repository under `mktemp -d` with `HOME`, `GIT_CONFIG_GLOBAL`, and `GIT_CONFIG_SYSTEM` redirected, and with a `trash` stub earlier in `PATH`. Keep that isolation: a test must not reach the real Trash, the real git config, or a real repository.

## Version Pinning

All external dependencies are version-pinned to prevent supply chain attacks. `make update` intentionally does NOT upgrade packages — it only installs missing ones and syncs config.

`make upgrade` opens an interactive Claude Code session on `/upgrade`. The command lives in `.claude/commands/upgrade.md` and carries the investigation steps and the hold-back criteria summarized below; edit it there when the policy changes. It presents its findings, rewrites the pins the user approves, runs `make upgrade-apply` to install them and refresh `versions.json`, then commits via `scripts/commit-upgrade.zsh`. The user approves the pins and the commit; `upgrade-apply` runs unattended, since it converges on whatever the pins already say.

- **Homebrew**: `brew bundle --no-upgrade` prevents automatic upgrades. Use `make upgrade` to review and apply updates. `make upgrade-apply` runs `brew bundle --file=Brewfile` (without `--no-upgrade`), so it upgrades only Brewfile-declared formulae/casks and never touches locally installed packages outside the repo.
- **Homebrew taps**: Non-official taps must be explicitly trusted (Homebrew 6.x `HOMEBREW_REQUIRE_TAP_TRUST`). List every non-official tap in `config/homebrew/trusted-taps.txt`; `make install`/`make update`/`make upgrade-apply` run `make trust-taps` before bundling to trust them idempotently. When adding a `tap`/`tap/formula` to `Brewfile`, also add its tap here (include the resolved formula tap if it differs from the one named in the `tap/formula` spec).
- **Claude Code**: Version is pinned in `config/claude/version`. `make install`/`make update` install only the pinned version. `make upgrade` tracks the latest published version by default, and only holds back when the CHANGELOG shows breaking changes affecting this repo's config surface (settings.json, hooks, slash commands, MCP, plugins, agents, skills, keybindings) OR GitHub Issues show trending unresolved critical bug reports (crashes, hangs, data loss) from multiple users. Auto-updater is disabled via `DISABLE_AUTOUPDATER=1`.
- **Sheldon plugins**: Every plugin in `config/sheldon/plugins.toml` MUST have a `tag` (or `rev` if no tags exist). Never add a plugin without version pinning.
- **uv tools**: Tools in `config/uv/tools.txt` MUST use `@tag` or `@commit` suffix, except `claude-sentinel` and `claude-sessions` (owned by the user, always use HEAD).
- **Node (fnm)**: The global default Node version is pinned in `config/fnm/version` as an exact version (e.g., `24.16.0`), never a floating alias like `lts-latest`. `make install`/`make update` run `fnm install` + `fnm default` for that version, skipping when it is already the default. `fnm env --use-on-cd` still honors per-project `.node-version`/`.nvmrc` files on top of this default. Node 24.17 regressed `http.Agent` keep-alive handling (`ERR_STREAM_PREMATURE_CLOSE` on reused sockets), breaking `node-fetch@2`-based tooling such as Google's `gaxios`/`googleapis` stack (nodejs/node#63989); stay below 24.17 until it is resolved.
- **Notion CLI (ntn)**: Notion's official CLI (published on npm by Notion) is pinned in `config/ntn/version` as an exact version and installed globally with npm using the fnm-managed Node. `make install`/`make update` run `install-ntn` after `install-node` and reinstall only when `ntn --version` differs from the pin. `make upgrade` tracks the latest published version (`npm view ntn version`) with the same hold-back policy as Claude Code (breaking CLI changes or trending critical bug reports). Auth is never stored in the repo: use interactive `ntn login` (macOS Keychain) or the `NOTION_API_TOKEN` env var for scripts/CI.
- **Claude Code plugins**: Updated only via `make upgrade`, not automatically. Removing an entry from `plugins.txt` uninstalls it on the next `make install`/`make update`.

`versions.json` is a committed snapshot that records only repo-declared packages, so it stays reproducible across machines. `snapshot-versions.zsh` scopes the brew/cask sections to `brew bundle list --file=Brewfile` (declared formulae/casks, resolved to canonical names) rather than `brew list` (every installed formula), matching the config-file-scoped sheldon/uv/claude/ntn sections. Locally installed packages outside `Brewfile` and transitive dependencies are intentionally excluded.
