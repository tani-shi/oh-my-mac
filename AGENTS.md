# Project instructions

This repository is the source of truth for a macOS workstation: shell, git, editors,
CLI agents, and macOS preferences. `make sync-config` copies and merges what is
declared here into the locations those tools actually read.

## Configuration sources

- Edit the sources under `config/` — never the generated copies under the user's home directory. A direct edit there is lost on the next sync.
- Run `make diff-config` to see what a sync would change, then `make sync-config` to apply it.

| Directory | Holds |
| --- | --- |
| `config/agents/` | user-global instructions shared by every CLI agent |
| `config/claude/` | Claude Code configuration and its user-global instructions |
| `config/codex/` | Codex configuration, version pin, user-global instructions, and skills |
| `config/vscode/`, `config/iterm2/`, `config/git/`, … | one directory per tool |

Instruction files fall into two scopes that must not be mixed:

| File | Scope | Read by |
| --- | --- | --- |
| `AGENTS.md` | this repository | Claude Code, Codex |
| `CLAUDE.md` | this repository | Claude Code |
| `.codex/config.toml` (`developer_instructions`) | this repository | Codex |
| `config/agents/instructions.md` | every repository, as user settings | Claude Code, Codex |
| `config/claude/instructions.md` | every repository, as user settings | Claude Code |
| `config/codex/instructions.md` | every repository, as user settings | Codex |

Codex reads this file by its own discovery rules and `CLAUDE.md` imports it with
`@AGENTS.md`, so project instructions live here once. Neither a Codex fallback
filename nor a symlink is involved.

The `config/` entries are a different scope from the first three: they are the
sources for the user's own `~/.claude/` and `~/.codex/`, and apply in every
repository rather than this one.

## Codex CLI Settings

- `config/agents/instructions.md` + `config/codex/instructions.md` are concatenated into the generated `~/.codex/AGENTS.md`.
- `config/codex/config.toml` declares the top-level keys merged into `~/.codex/config.toml`.
- `config/codex/version` pins the installed CLI version.
- `config/codex/skills/*/` is synced into `~/.agents/skills/`. Invoke `refactor-review` explicitly with `$refactor-review`; implicit invocation is disabled by its `agents/openai.yaml` policy.
- `.agents/skills/upgrade/` is the repository-scoped dependency upgrade workflow. An explicit `$upgrade` invocation authorizes its version selection, local application, commit, pull request, and merge after its gates pass without separate approvals.
- `.codex/` at the repository root is project scope: it configures Codex sessions run inside this repository, is not synced to `~/.codex/`, and loads only once the directory is trusted. Its `developer_instructions` carries what only Codex needs while working here.
- Auth lives in `~/.codex/auth.json` or the macOS Keychain and never in the repository:
  sign in with `codex login`, or set `OPENAI_API_KEY` for scripts and CI.

## VSCode Settings

- NEVER edit `~/Library/Application Support/Code/User/settings.json` directly.
- Always edit the source files under `config/vscode/` in this repository instead.
  - `config/vscode/settings.json` → merged into `~/Library/Application Support/Code/User/settings.json`
  - `config/vscode/extensions.txt` → installed via `code --install-extension`

## config.zsh

- Every sync operation MUST include a diff check — only write when the current state differs from the desired state. Never blindly overwrite. `diff` mode writes nothing at all: compare against a temporary stand-in rather than creating the destination.
- diff and sync modes share the same definitions (configs array, jq expressions, plist keys, etc.). When adding a new sync target, write both mode handlers in the same block.
- `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` are generated: `sync_instructions` concatenates `config/agents/instructions.md` with the CLI's own `instructions.md` into a temporary file, and `sync_file` diffs and copies that.
- The iTerm2 Dynamic Profile is rewritable and three-way merged against its previous repository baseline. Local edits win conflicts, while untouched values receive repository additions, updates, and removals; keep the baseline outside `DynamicProfiles/` so iTerm2 does not load it as a profile.
- Codex's `hooks.json` and `agent-sentinel.rules` are generated into the sync's temporary directory by the installed `agent-sentinel`, then diffed or copied to `~/.codex/`; generation starts from the installed `hooks.json` so unrelated user hooks survive. Generated copies do not live in the repository, and `default.rules` remains application-owned. Sync verifies the exact agent-sentinel hook and requires every generated rule to declare `prompt` or `forbidden` before writing any config, while `make refresh-agent-sentinel` updates its HEAD-tracking uv tool and refreshes the repository-owned Claude settings.
- `scripts/config-tools.zsh` defines the managed config-tools environment and Python paths shared by installation and config sync. `make install-config-tools` rebuilds that environment from the dependencies pinned in `config/uv/config-tools.txt` when its Python or installed versions are invalid. `merge-codex-config.py` runs through the prepared interpreter without resolving dependencies during config diff or sync. It updates only the top-level keys declared by `config/codex/config.toml`; tables and other undeclared values in `~/.codex/config.toml` remain application-owned. A parse failure aborts the sync before the installed file is changed.
- macOS defaults are managed via the `macos_defaults` array using `defaults read`/`defaults write`. Add new entries as `"domain:key:type:value"` (supported types: `bool`, `int`, `float`, `string`).
- `remove_claude_orphans` deletes files under `~/.claude/agents/`, `~/.claude/scripts/`, and `~/.claude/skills/` that the repository no longer declares, then removes directories left behind by a renamed or deleted skill. Deletion is permanent: keep anything worth surviving a sync in `config/claude/`.
- Codex skill ownership is recorded as relative file paths in `~/.agents/skills/.oh-my-mac-managed` because that directory is shared with independently installed skills. Sync aborts rather than overwrite an unrecorded same-name skill. `reconcile_codex_skills` removes only valid paths in the previous manifest that no longer exist under `config/codex/skills/`; unrecorded skills and files are left untouched.
- Global git config, including aliases such as `git discard`, is managed via the `git_config_keys` array as `"key:value"`. A script an alias invokes is synced through the `configs` array and run as `zsh <path>`, so it needs no executable bit — `sync_files` copies content only and never manages file modes.

## Tests

- `make test` runs `scripts/test-discard.zsh`, `scripts/test-commit-upgrade.zsh`, `scripts/test-upgrade-apply.zsh`, `scripts/test-documentation.zsh`, and `scripts/test-config-sync.zsh`. Add `config/git/discard.zsh` cases to the first, upgrade commit workflow cases to the second, selective upgrade application cases to the third, Brewfile/README package and README/public `make` target consistency cases to the fourth, and config sync plus Codex skill contract cases to the fifth.
- Tests run against the repository copy of a script, never the synced copy under `$HOME`, so a change is verified before `make sync-config`.
- Each case runs in a throwaway directory under `mktemp -d` with `HOME`, `GIT_CONFIG_GLOBAL`, and `GIT_CONFIG_SYSTEM` redirected, and with stubs earlier in `PATH`. Keep that isolation: a test must not reach the real Trash, the real git config, a real repository, or the real macOS preferences.
- `make test` does not install config tools. `test-config-sync.zsh` injects the managed config Python into a marked temporary root; set `OH_MY_MAC_TEST_CONFIG_PYTHON` to inject another prepared interpreter without writing to the test runner's home directory. The installer accepts `OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT` only for a marked directory below the OS temporary directory and rejects the former arbitrary-path override.
- `defaults`, `duti`, and `code` reach state that `HOME` does not redirect, so `test-config-sync.zsh` stubs them with ones that record what they were told; a stub that loses its state between passes makes the idempotency cases pass for the wrong reason.

## Dependency Versioning

`README.md`'s **Dependency Version Guarantees** section is the source of truth for the reproducibility boundary of every managed dependency class. Keep its single guarantee-and-exception table aligned with `Makefile`, `config.zsh`, and `.agents/skills/upgrade/SKILL.md`. Do not describe this repository as locking every external dependency or producing byte-for-byte reproducible installations.

- `config/claude/version`, `config/fnm/version`, `config/ntn/version`, and `config/codex/version` contain exact direct versions. Keep `DISABLE_AUTOUPDATER=1` for Claude Code so its installed version remains under repository control.
- Packages in `config/uv/config-tools.txt` use exact `==` pins. The Python interpreter constraint remains a range and is documented as such in the guarantee table.
- Every remote plugin in `config/sheldon/plugins.toml` has a `tag`, or a `rev` when no tag exists. The user-local Sheldon lock is not a repository lock.
- Tools in `config/uv/tools.txt` use an `@tag` or `@commit` suffix, except the user-owned `agent-sentinel` and `claude-sessions`, whose source requirements intentionally reference HEAD.
- `Brewfile`, `config/homebrew/trusted-taps.txt`, `config/vscode/extensions.txt`, and `config/claude/plugins.txt` declare membership, not versions. When adding a non-official Homebrew tap or `tap/formula` entry, add every required tap to `config/homebrew/trusted-taps.txt`, including the formula's resolved tap when it differs from the one named in the entry.
- The explicit upgrade policy and its editable files live in `.agents/skills/upgrade/SKILL.md`. Keep that workflow and the README guarantee table consistent with the internal `upgrade-apply` target; it requires a validated selective plan, records per-candidate results, and does not run `sync-config`. Claude Code is an upgrade target, and its CLI may manage its own installation and plugins, but it is never the workflow host, judge, or reviewer.
- Node 24.17 regressed `http.Agent` keep-alive handling (`ERR_STREAM_PREMATURE_CLOSE`) and breaks `node-fetch@2`-based tooling such as Google's `gaxios`/`googleapis` stack (nodejs/node#63989). Keep the global default below 24.17 until it is resolved.
