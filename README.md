# oh-my-mac

My Mac setup. Apple Silicon only.

## Prerequisites

### Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Initialize the current shell:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## Quick Start

```bash
mkdir -p ~/dev
git clone https://github.com/tani-shi/oh-my-mac.git ~/dev/oh-my-mac
cd ~/dev/oh-my-mac
make install
```

On an existing Mac, back up `~/.claude/agents/`, `~/.claude/scripts/`, and `~/.claude/skills/` first. Install and update delete entries absent from this repository.

## What's Included

### Homebrew Packages ([Brewfile](Brewfile))

| Category | Packages |
| --- | --- |
| Shell | starship, sheldon, fzf, ripgrep, shellcheck, shfmt |
| Modern CLI replacements | bat, eza, fd, delta, zoxide |
| Terminal | iterm2, tmux |
| Utilities | jq, sqlite, tree, btop, duti |
| Font | font-jetbrains-mono-nerd-font |
| Development | fnm, uv, ruff, terraform, awscli, gcloud-cli, visual-studio-code, chatgpt |
| Git / GitHub | gh, git-lfs |

### CLI Tools

| Tool | Version |
| --- | --- |
| Claude Code | [config/claude/version](config/claude/version) |
| Node.js (fnm) | [config/fnm/version](config/fnm/version) |
| Notion CLI | [config/ntn/version](config/ntn/version) |
| Codex CLI | Installed if missing |

### Config Files

| Source | Destination |
| --- | --- |
| `config/starship.toml` | `~/.config/starship.toml` |
| `config/sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `config/zshrc` | `~/.zshrc` |
| `config/git/ignore` | `~/.config/git/ignore` |
| `config/claude/settings.json` | `~/.claude/settings.json` |
| `config/claude/keybindings.json` | `~/.claude/keybindings.json` |
| `config/codex/config.toml` | `~/.codex/config.toml` |
| `config/vscode/settings.json` | `~/Library/Application Support/Code/User/settings.json` |
| `config/iterm2/profile.json` | `~/Library/Application Support/iTerm2/DynamicProfiles/profile.json` |

### uv Tools ([config/uv/tools.txt](config/uv/tools.txt))

| Tool | Source |
| --- | --- |
| agent-sentinel | [tani-shi/agent-sentinel](https://github.com/tani-shi/agent-sentinel) |
| claude-sessions | [tani-shi/claude-sessions](https://github.com/tani-shi/claude-sessions) |

### VSCode Extensions ([config/vscode/extensions.txt](config/vscode/extensions.txt))

| Extension | Description |
| --- | --- |
| kaiwood.center-editor-window | Center the active line in the editor |
| ms-dotnettools.csharp | C# language support |
| ms-dotnettools.csdevkit | C# Dev Kit |

### Claude Code Plugins ([config/claude/plugins.txt](config/claude/plugins.txt))

| Plugin | Registry |
| --- | --- |
| code-review | claude-plugins-official |
| context7 | claude-plugins-official |
| playwright | claude-plugins-official |

## Usage

| Command | Description |
| --- | --- |
| `make install` | Install packages + sync config + install plugins |
| `make update` | Update Homebrew packages + apply declared tools and config |

VS Code and the Codex desktop app (`chatgpt`) are declared in [Brewfile.install-only](config/homebrew/Brewfile.install-only). Both commands install them only if missing; update them through the apps. VS Code is configured for manual update checks.

For pinned version updates, run `$upgrade` in Codex. Review and merge the PR, pull the changes, then run `make update`.

## Post-install Setup

### SSH key + GitHub auth

```bash
ssh-keygen
gh auth login
# Protocol: SSH / Key: id_ed25519
```

### Notion CLI

```bash
ntn login
```

### Codex CLI

```bash
codex login
```

Trust the installed hooks in **Settings → Hooks** (Codex app) or `/hooks` (CLI).

### iTerm2

Set **Profiles → oh-my-mac → Other Actions… → Set as Default**.

![Set as Default](docs/iterm2-set-as-default.png)

For SSH with native tabs and splits:

```bash
ssh host -t 'tmux -CC new -A -s main'
```

In **Settings → General → tmux**:

- **Attaching**: Tabs in the attaching window
- **Automatically bury the tmux client session after connecting**: ON

In **Settings → Appearance → General**:

- **Auto-hide menu bar in non-native fullscreen**: ON
- **Exclude from Dock and ⌘-Tab Application Switcher**: ON
- **…but only if all windows are hotkey windows**: ON

![Appearance settings](docs/iterm2-appearance-manual-settings.png)

### macOS

In **System Settings → Accessibility → Display**:

- **Reduce Motion**: ON
- **Reduce Transparency**: ON
