# oh-my-mac

My Mac setup, managed declaratively.

## Prerequisites

### Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Add to `~/.zshrc`:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## Quick Start

```bash
git clone git@github.com:tani-shi/oh-my-mac.git ~/dev/oh-my-mac
cd ~/dev/oh-my-mac
make install
```

## Agent Instructions

Claude Code and Codex both work in this repository, and both read their instructions from one place per scope.

| File | Scope | Read by |
| --- | --- | --- |
| `AGENTS.md` | this repository | Claude Code, Codex |
| `CLAUDE.md` | this repository | Claude Code |
| `.codex/config.toml` (`developer_instructions`) | this repository | Codex |
| `config/agents/instructions.md` | every repository, as user settings | Claude Code, Codex |
| `config/claude/instructions.md` | every repository, as user settings | Claude Code |
| `config/codex/instructions.md` | every repository, as user settings | Codex |

`AGENTS.md` holds the project instructions both agents follow. Codex finds it by its own discovery rules; `CLAUDE.md` pulls it in with `@AGENTS.md` and adds only what is specific to Claude Code. Neither a Codex fallback filename nor a symlink is needed, and no sentence is written twice.

`.claude/` and `.codex/` at the repository root are the per-agent project scopes, holding what only one agent needs while working here. Codex reads `.codex/config.toml` once the directory is trusted.

The `config/` entries are a different scope again: `make sync-config` concatenates the shared `instructions.md` with each agent's own into `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, and syncs Codex skills into `~/.agents/skills/`, so they apply in every repository rather than this one.

## What's Included

### Homebrew Packages (`Brewfile`)

| Category | Packages |
| --- | --- |
| Shell | starship, sheldon, fzf, ripgrep, shellcheck, shfmt |
| Modern CLI replacements | bat, eza, fd, delta, zoxide |
| Terminal multiplexer | tmux |
| Utilities | jq, sqlite, tree, btop, duti |
| Font | font-jetbrains-mono-nerd-font |
| Development | fnm, uv, terraform, awscli, gcloud-cli, visual-studio-code |
| Git / GitHub | gh, git-lfs |

### Trusted Homebrew Taps (`config/homebrew/trusted-taps.txt`)

Homebrew 6.x refuses to load formulae from non-official taps unless they are explicitly trusted. `make install` / `make update` / `make upgrade-apply` run `make trust-taps` before bundling to trust these idempotently, so a fresh machine installs in one shot.

| Tap | Used by |
| --- | --- |
| hashicorp/tap | terraform |

### Config Files

| Source | Destination |
| --- | --- |
| `config/starship.toml` | `~/.config/starship.toml` |
| `config/sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `config/zshrc` | `~/.zshrc` |
| `config/git/ignore` | `~/.config/git/ignore` |
| `config/git/discard.zsh` | `~/.config/git/discard.zsh` |
| `config/agents/instructions.md` + `config/claude/instructions.md` | `~/.claude/CLAUDE.md` |
| `config/agents/instructions.md` + `config/codex/instructions.md` | `~/.codex/AGENTS.md` |
| `config/codex/config.toml` | managed keys in `~/.codex/config.toml` |
| `config/claude/settings.json` | `~/.claude/settings.json` |
| `config/claude/keybindings.json` | `~/.claude/keybindings.json` |
| `config/claude/scripts/*.zsh` | `~/.claude/scripts/` |
| `config/claude/agents/*.md` | `~/.claude/agents/` |
| `config/claude/skills/*/SKILL.md` | `~/.claude/skills/` |
| `config/codex/skills/*/` | `~/.agents/skills/` |
| `config/vscode/settings.json` | `~/Library/Application Support/Code/User/settings.json` |

### Codex Skills

`config/codex/skills/refactor-review/` は、現在の実装目的と作業差分を対象に構造的なリファクタリング候補を最大3件まで提示します。`$refactor-review` で読み取り専用レビューを実行し、同一セッションで `$refactor-review apply` を実行すると、直前に `APPLY` と判定された候補だけを適用して関連テストを実行します。暗黙起動は無効で、通常の不具合レビューは Codex 標準の `/review` を使用します。

`make sync-config` は、このリポジトリが同期した Codex skill の相対ファイルパスを `~/.agents/skills/.oh-my-mac-managed` に記録します。配布元から削除されたファイルだけをこの記録に基づいて削除し、ほかの方法で追加された skill やファイルは保持します。未管理の同名 skill が既に存在する場合は、上書きせず同期を中止します。

### git discard (`config/git/discard.zsh`)

`git discard` throws away working-tree state after recording it, so every discard can be taken back. `config.zsh` registers it as the global git alias `discard`.

| Command | Effect |
| --- | --- |
| `git discard [<pathspec>...]` | Reset the working tree and index to HEAD (whole repository by default) |
| `git discard --source=<rev> [<pathspec>...]` | Reset to `<rev>` instead, discarding everything since it |
| `git discard --untracked [<pathspec>...]` | Move untracked files to the Trash; gitignored files are left alone |
| `git discard --hard [<commit>]` | Snapshot, then `git reset --hard` |
| `git discard --list` | List snapshots |
| `git discard --undo [<ref>] [-- <pathspec>...]` | Restore the newest (or named) snapshot |

`--undo` restores only the paths whose current content still matches what the discard left there, so files edited again afterwards keep their newer version and are reported as skipped. Restored files come back staged.

Snapshots are commit objects made with `git stash create` and held under `refs/discard/*`, so they cost nothing until the working tree is dirty and survive garbage collection. Each one older than `GIT_DISCARD_KEEP_DAYS` (30) is dropped once `GIT_DISCARD_KEEP_MIN` (20) newer ones exist; `GIT_DISCARD_KEEP_DAYS=0` keeps them forever. Untracked files have no git object to snapshot; the Trash is their recovery path.

The point is the permission layer: an operation that can always be undone is safe to auto-approve. [agent-sentinel](https://github.com/tani-shi/agent-sentinel) recognizes `git discard` as the recoverable path and, once it sees the alias configured, denies `git checkout` and the working-tree form of `git restore` so coding agents reach for it instead. `git restore --staged`, which moves the index without touching files, stays allowed. Its Codex execution rules use only `prompt` and `forbidden`; they never grant sandbox bypass.

### Node (`config/fnm/version`)

[fnm](https://github.com/Schniz/fnm) manages Node.js. `fnm env --use-on-cd` (in `config/zshrc`) switches versions per project from a `.node-version` / `.nvmrc` file, while `config/fnm/version` pins the global default that `make install` / `make update` install via `fnm install` + `fnm default`. The step is skipped when the pinned version is already installed and set as default. The default is held below 24.17 pending [nodejs/node#63989](https://github.com/nodejs/node/issues/63989) — an `http.Agent` keep-alive regression that breaks node-fetch-based tooling.

| Tool | Version |
| --- | --- |
| node | 24.16.0 (Node 24 LTS "Krypton") |

### Notion CLI (`config/ntn/version`)

[ntn](https://developers.notion.com/cli) is Notion's official CLI, published on npm by Notion. It gives scripts and coding agents session-independent, idempotent access to the Notion API (the Notion MCP server covers interactive use). `make install` / `make update` install the pinned version globally with npm using the fnm-managed Node, reinstalling only when `ntn --version` differs from the pin.

| Tool | Version |
| --- | --- |
| ntn | 0.21.10 |

### Codex CLI (`config/codex/version`)

[Codex CLI](https://developers.openai.com/codex/cli) is OpenAI's coding agent, published on npm as `@openai/codex`. It runs alongside Claude Code and reads the same rules — see [Agent Instructions](#agent-instructions). `make install` / `make update` install the pinned version globally with npm using the fnm-managed Node, reinstalling only when the globally installed `@openai/codex` differs from the pin; the step is skipped when npm is unavailable. Homebrew's `codex` cask carries no version pin and is not used.

`config/codex/config.toml` declares the global defaults this repository manages. The sync uses a pinned TOML parser to update those top-level keys while preserving project trust entries, plugins, MCP servers, and other values written by Codex or the ChatGPT desktop app. Invalid TOML aborts the sync without changing the installed file.

`agent-sentinel` is installed and checked before config sync. The sync generates its Codex hook and execution rules in a temporary directory, preserving unrelated hooks already installed in `~/.codex/hooks.json`, then compares or copies the result to `~/.codex/`. Generated copies are not stored in the repository, and `~/.codex/rules/default.rules` remains user- or application-owned. Before writing, sync requires the exact agent-sentinel hook and an explicit `prompt` or `forbidden` decision on every generated rule. `make refresh-agent-sentinel` updates the HEAD-tracking tool, refreshes the integrated Claude settings, validates both hosts, runs the tests, and shows the pending user-config diff. After syncing, open `/hooks` in Codex CLI and trust the hook. Codex GUI execution is not part of this repository's verified integration surface.

| Tool | Version |
| --- | --- |
| codex | 0.147.0 |

### uv Tools (`config/uv/tools.txt`)

| Tool | Source |
| --- | --- |
| agent-sentinel (Claude extra) | [tani-shi/agent-sentinel](https://github.com/tani-shi/agent-sentinel) |

### VSCode Extensions (`config/vscode/extensions.txt`)

| Extension | Description |
| --- | --- |
| kaiwood.center-editor-window | Center the active line in the editor |
| ms-dotnettools.csharp | C# language support (Roslyn) |
| ms-dotnettools.csdevkit | C# Dev Kit — .NET IntelliSense, project/solution navigation |

Add extensions as `publisher.extension-name` per line.

### Claude Code Plugins (`config/claude/plugins.txt`)

| Plugin | Registry |
| --- | --- |
| code-review | claude-plugins-official |
| context7 | claude-plugins-official |
| playwright | claude-plugins-official |

`make install` / `make update` install plugins listed here and uninstall user-scope plugins that are not. Marketplaces are not managed by this repository; remove an unused one with `claude plugin marketplace remove <name>`.

## Usage

| Command | Description |
| --- | --- |
| `make` / `make help` | Show available targets |
| `make install` | Install packages + sync config + install plugins |
| `make update` | Sync config + install missing packages (no upgrades) |
| `make upgrade` | Open a Claude Code session that investigates upgrades, applies them, and commits |
| `make upgrade-apply` | Apply the pinned versions (invoked from `/upgrade`) |
| `make refresh-agent-sentinel` | Update agent-sentinel HEAD and refresh generated config |
| `make trust-taps` | Trust non-official Homebrew taps listed in `config/homebrew/trusted-taps.txt` |
| `make test` | Run the test suite |
| `make diff-config` | Show differences between repo and local config |
| `make sync-config` | Sync config files only |

## Post-install Setup

These require interactive authentication and cannot be automated:

### SSH key + GitHub auth

```bash
ssh-keygen
gh auth login
# Protocol: SSH / Key: id_ed25519
```

### Notion CLI auth

```bash
ntn login   # opens a browser; token is stored in the macOS Keychain
```

For scripts and CI, export a Notion personal access token instead of logging in — it takes precedence over the Keychain and is never stored in this repo:

```bash
export NOTION_API_TOKEN=ntn_...
```

### Codex CLI auth

```bash
codex login   # opens a browser; credentials land in ~/.codex/auth.json
```

For scripts and CI, export an OpenAI API key instead — it is never stored in this repo:

```bash
export OPENAI_API_KEY=sk-...
```

### iTerm2

- Primary terminal for shell work and Claude Code; tab title shows the current directory basename, and tab color flips green on Claude Code completion / orange while it's awaiting input / purple while `agent-sentinel` is running a slow LLM-backed permission judgment (managed by zsh hooks + Claude Code Stop/Notification/PreToolUse hooks)
- Managed via Dynamic Profile (`config/iterm2/profile.json`), synced by `make sync-config`
- After first sync: **Profiles → oh-my-mac → Other Actions… → Set as Default** to apply

  ![Set as Default](docs/iterm2-set-as-default.png)

- For SSH with native pane splits, use tmux Control Mode: `ssh host -t 'tmux -CC new -A -s main'`
- Manual steps required for tmux integration (**Settings → General → tmux**):
  - **Attaching**: "Tabs in the attaching window"
  - **Automatically bury the tmux client session after connecting**: ON
- Manual steps required for app-global appearance (**Settings → Appearance → General**) — these are application-wide preferences, not profile-scoped, so they cannot be set via Dynamic Profile and must be enabled by hand:
  - **Auto-hide menu bar in non-native fullscreen**: ON
  - **Exclude from Dock and ⌘-Tab Application Switcher**: ON
  - **…but only if all windows are hotkey windows**: ON (required to keep the option above enabled)

  ![Appearance settings](docs/iterm2-appearance-manual-settings.png)

### macOS Performance

- Managed via `defaults write` in `make sync-config`: window animations disabled
- Manual steps required for accessibility settings:
  - **System Settings → Accessibility → Display → Reduce Motion**: ON
  - **System Settings → Accessibility → Display → Reduce Transparency**: ON
