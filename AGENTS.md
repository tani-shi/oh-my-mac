# Project instructions

This repository configures a macOS workstation. `make install` and `make update` install tools and apply configuration; `CLAUDE.md` imports these project instructions with `@AGENTS.md`.

## Configuration sources

- Edit sources under `config/`, including VS Code settings, rather than generated copies under the user's home directory.
- `config/agents/instructions.md` contains user-global instructions shared by the CLI agents. `config/claude/instructions.md` and `config/codex/instructions.md` contain CLI-specific additions. These apply in every repository; keep this repository's rules in `AGENTS.md`.
- Shared and CLI-specific instructions are concatenated into `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` during sync.
- Use `make diff-config` to inspect configuration changes and `make sync-config` to apply them separately from installation.
- Authentication belongs in the tools' local auth storage or environment, never in this repository.

## Configuration ownership

- Sync writes only when the desired state differs. Diff mode is read-only, including for missing destinations; use temporary stand-ins rather than creating destination files. Both modes share declarations and merge rules.
- Claude Code settings and keybindings, VS Code settings, and Codex configuration share files with local or application-owned values. Preserve those values when merging repository declarations.
- Codex config merging updates only declared scalar leaves. Parse errors or scalar/table conflicts must leave the installed file unchanged. The prepared config-tools Python environment is shared by installation and sync; diff and sync do not resolve dependencies or install packages.
- The iTerm2 Dynamic Profile uses a three-way merge against the previous repository baseline. Local edits win conflicts; unchanged values receive repository additions, updates, and removals. Keep the baseline outside `DynamicProfiles/` so iTerm2 does not load it as a profile.
- The repository owns Claude agents, scripts, and skills under `~/.claude/`. Sync permanently deletes undeclared files under `agents/`, `scripts/`, and `skills/`, and undeclared skill directories. Keep anything that must survive in `config/claude/`.
- `~/.agents/skills/` is shared with independently installed skills. The `.oh-my-mac-managed` manifest records relative file paths owned by this repository. Remove only valid previously recorded paths; preserve unrecorded files and stop rather than overwrite an unmanaged same-name skill.
- agent-sentinel generates Codex hooks and rules from installed `hooks.json`. Preserve unrelated hooks and application-owned `default.rules`; validate required hooks and `prompt` or `forbidden` rules. `make refresh-agent-sentinel` updates the HEAD-tracking tool and Claude settings.
- Global Git settings belong in `config.zsh`'s `git_config_keys`; file copies belong in `configs`; macOS preferences belong in `macos_defaults`. A synced Git alias script runs as `zsh <path>` because file sync copies content without managing executable bits.

## Skills

- `config/codex/skills/` syncs to `~/.agents/skills/`. Preserve each skill's explicit invocation policy in `agents/openai.yaml`.
- Use the explicitly invoked `.agents/skills/upgrade/` workflow for version updates; its skill defines authorization and completion boundaries.

## Dependency versioning

- Claude Code, Node, and ntn have exact versions in their `config/` directories. Keep `DISABLE_AUTOUPDATER=1` for Claude Code. Codex CLI is installed only when absent; its subsequent version lifecycle is outside repository management.
- `config/homebrew/Brewfile.install-only` declares VS Code and the Codex desktop app (`chatgpt`). Install them with `brew bundle --no-upgrade` before configuration sync; their updates belong to the apps. Keep them out of the main `Brewfile` update path.
- Config-tools packages use exact `==` pins in `config/uv/config-tools.txt`; their Python interpreter uses a range.
- Remote Sheldon plugins use tags, or revisions when no tag exists. The user-local Sheldon lock is not a repository lock.
- uv tools use tags or commits except the intentionally HEAD-tracking `agent-sentinel` and `claude-sessions`.
- `Brewfile`, trusted taps, VS Code extensions, and Claude plugins declare membership rather than versions. When adding a non-official Homebrew tap or `tap/formula`, declare every required tap in `config/homebrew/trusted-taps.txt`, including a resolved tap that differs from the named one.
- Node 24.17 regressed `http.Agent` keep-alive handling (`ERR_STREAM_PREMATURE_CLOSE`) and breaks `node-fetch@2`-based tooling (nodejs/node#63989). Keep the global default below 24.17 until resolved.
