# oh-my-mac

My Mac setup, managed declaratively.

## Prerequisites

This repository supports only Apple Silicon (arm64) Macs. Homebrew and the synced
`~/.zshrc` use `/opt/homebrew`, the standard Homebrew prefix on Apple Silicon.

### Homebrew

Install Homebrew and initialize the current shell so the following commands can use it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## クイックスタート

新しい環境では、次の手順で必要なツールの導入と設定同期をまとめて行います。

```bash
mkdir -p ~/dev
git clone https://github.com/tani-shi/oh-my-mac.git ~/dev/oh-my-mac
cd ~/dev/oh-my-mac
make install
```

既存の環境へ導入する場合は、`make install` の前に変更予定とClaude設定を確認してください。`make diff-config` の実行には `agent-sentinel`、`jq`、`uv`などの同期用依存が必要です。これらが導入済みなら、先に次を実行します。

```bash
make diff-config
```

同期用依存が未導入で `make diff-config` を実行できない場合は、`make install` より先にClaude設定を手動で退避してください。`make install` は依存を導入した後、確認なしで `make sync-config` まで実行し、`~/.claude/agents/`、`~/.claude/scripts/`、`~/.claude/skills/` にあるリポジトリ未管理の項目を恒久削除します。たとえば、既存データをリポジトリ外へ退避するには次のようにします。

```bash
backup_dir="$HOME/claude-config-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
for name in agents scripts skills; do
  [[ -e "$HOME/.claude/$name" ]] && cp -R "$HOME/.claude/$name" "$backup_dir/"
done
```

継続して利用するagent・script・skillは、対応する相対パスで `config/claude/` に追加できます。詳しい所有範囲と副作用は[設定同期の変更範囲](#設定同期の変更範囲)を参照してください。

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

### 設定同期の変更範囲

`make diff-config` は、次の管理対象の設定ファイル、管理集合、OS/global stateへ変更を適用せず、差分と不足項目を表示します。ただし、現状は `uv run` の依存解決により `~/.cache/uv` へ書き込むことがあるため、処理全体がread-onlyという意味ではありません（[#12](https://github.com/tani-shi/oh-my-mac/issues/12)）。内容を確認してから `make sync-config` を実行してください。`make install` と `make update` も処理の途中で `make sync-config` を実行します。

| 区分 | `make sync-config` の動作 |
| --- | --- |
| ファイルコピー | `config/` の通常ファイル、共有・CLI別の指示を連結したファイル、agent-sentinelから生成したCodex設定を、内容が異なる場合だけ所定のパスへコピーします。コピー先の既存内容はリポジトリの内容で置き換わります。 |
| マージ | Claude Codeのsettings/keybindings、Codexのリポジトリ宣言済みトップレベルキー、VS Code settingsを既存設定へマージします。iTerm2 Dynamic Profileは前回同期時のリポジトリ内容を基準に3-way mergeし、ローカル変更を保持します。 |
| 管理集合の調整 | Claude Codeのagent・script・skillとCodex skillsについて、下記の所有規則に従って追加・更新・削除を行います。 |
| 外部状態の変更 | 不足しているVS Code extensionのインストール、global Git configの更新、`duti`によるdefault applicationの変更、`defaults write`によるmacOS preferencesの変更を行います。`config/sheldon/plugins.toml`を更新した場合は `sheldon lock --update` も実行します。 |

Claude Codeについては、次のパスをリポジトリが集合全体として所有します。

- `~/.claude/agents/*.md`
- `~/.claude/scripts/` 直下のファイル
- `~/.claude/skills/` 以下のファイルとディレクトリ

対応する相対パスが `config/claude/` に存在しないファイルは恒久削除され、リポジトリに存在しない `~/.claude/skills/` 以下のディレクトリも再帰的に削除されます。個人用のagent・script・skillを残す場合は、同期前に対象ディレクトリ外へ退避するか、継続して利用するものを `config/claude/` に追加してください。`~/.claude/CLAUDE.md` は共有指示とClaude固有指示から生成し直されますが、settingsとkeybindingsは上表のとおり既存内容へマージされます。

Codex skillsの扱いは異なります。リポジトリが同期した相対ファイルパスを `~/.agents/skills/.oh-my-mac-managed` に記録し、その記録に含まれるファイルだけを削除対象にします。別の方法で追加したskillやファイルは保持し、同名の未管理skillがある場合は上書きせず同期を中止します。

### Codex Skills

`config/codex/skills/refactor-review/` identifies up to three structural refactoring candidates based on the current implementation goals and working changes. Run `$refactor-review` for a read-only review, then run `$refactor-review apply` in the same session to apply only the candidates previously marked `APPLY` and run the relevant tests. Implicit invocation is disabled; use Codex's standard `/review` command for regular bug reviews.

`make sync-config` records the relative paths of Codex skill files synced by this repository in `~/.agents/skills/.oh-my-mac-managed`. It uses this record to remove only files that have been deleted from the source while preserving skills and files added by other means. If an unmanaged skill with the same name already exists, the sync stops without overwriting it.

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

[Codex CLI](https://developers.openai.com/codex/cli) is OpenAI's coding agent, published on npm as `@openai/codex`. It runs alongside Claude Code and reads the same rules — see [Agent Instructions](#agent-instructions). `make install` / `make update` install the pinned version globally with npm using the fnm-managed Node, reinstalling only when the globally installed `@openai/codex` differs from the pin. A missing prerequisite or failed required installer stops the parent command with a nonzero exit status. Homebrew's `codex` cask carries no version pin and is not used.

`config/codex/config.toml` declares the global defaults this repository manages. The supported configuration uses `approval_policy = "on-request"` with `sandbox_mode = "workspace-write"`. The sync uses a pinned TOML parser to update those top-level keys while preserving project trust entries, plugins, MCP servers, and other values written by Codex or the ChatGPT desktop app. Invalid TOML aborts the sync without changing the installed file.

`agent-sentinel` is installed and checked before config sync. The sync puts a read-only copy of `~/.codex/config.toml` in its temporary directory so the generated Codex hook and execution rules can report configuration notices. With `approval_policy = "never"`, approval prompts are disabled and Codex GUI may run commands matched by `prompt` rules without approval, so ASK enforcement is not guaranteed. With `features.hooks = false`, hook DENY rules do not run. The diagnostic does not change the user's config and reports how to restore the supported settings. [OpenAI Docs](https://learn.chatgpt.com/docs/config-file/config-reference) describes `on-request` for interactive runs and `never` for non-interactive runs. The observed GUI and CLI difference is recorded in [agent-sentinel issue #22](https://github.com/tani-shi/agent-sentinel/issues/22#issuecomment-5300085004).

Generation starts from `~/.codex/hooks.json` so unrelated hooks survive, then compares or copies the result into `~/.codex/`. Generated copies do not live in the repository, and `~/.codex/rules/default.rules` remains user- or application-owned. Before writing, sync requires the exact agent-sentinel hook and an explicit `prompt` or `forbidden` decision on every generated rule. `make diff-config` reports notices without changing the config, while `make sync-config` converges the repository-managed values through the normal sync. `make refresh-agent-sentinel` updates the HEAD-tracking tool, refreshes the integrated Claude settings, validates both hosts, runs the tests, and shows the pending user-config diff.

Codex requires manual review before it runs a new or changed non-managed command hook. After a sync that changes the agent-sentinel hook definition, use the interface for the Codex surface you run:

- Codex app: open **Settings > Hooks** and trust the hook. The app does not expose `/hooks` as a slash command, so its absence from the command list is not a configuration error.
- Codex CLI: run `/hooks` and trust the hook.

Trust is recorded for the current hook-definition hash. The same definition remains trusted across tasks; changing the definition requires another review. The sync reports these steps only when it writes a new or changed agent-sentinel hook. A refresh that detects a pending definition change asks you to sync first and repeats that notice while the change remains pending. A refresh with no pending definition change, or an identical sync, reports no trust notice. See the [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks) for the trust model and CLI workflow.

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

Add extensions as `publisher.extension-name` per line. Config sync is the single owner of extension installation, and an installation failure stops the sync.

### Claude Code Plugins (`config/claude/plugins.txt`)

| Plugin | Registry |
| --- | --- |
| code-review | claude-plugins-official |
| context7 | claude-plugins-official |
| playwright | claude-plugins-official |

`make install` / `make update` install plugins listed here and uninstall user-scope plugins that are not. Marketplaces are not managed by this repository; remove an unused one with `claude plugin marketplace remove <name>`.

## 使い方

同期用依存が導入済みの既存環境では、設定を反映する前に `make diff-config` を実行し、コピー・マージ内容、削除対象、外部状態の変更を確認してください。依存が未導入の場合は、[クイックスタート](#クイックスタート)に従って既存のClaude設定を手動で退避してから `make install` を実行します。Claude Codeの削除対象に残したいデータが含まれる場合は、[設定同期の変更範囲](#設定同期の変更範囲)に従って退避またはリポジトリへ追加してから同期します。

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
| `make diff-config` | 管理対象の設定、管理集合、OS/global stateへ反映せず変更予定を表示する（uvキャッシュへは書き込む場合がある） |
| `make sync-config` | リポジトリ管理の設定、管理集合、外部状態を同期する |

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
- Managed via a rewritable Dynamic Profile (`config/iterm2/profile.json`), synced by `make sync-config`; repository additions and updates apply to settings left unchanged locally, while changes made in iTerm2 are preserved
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
