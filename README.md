# oh-my-mac

My Mac setup guide.

## Prerequisites

### iTerm2

Download from [https://iterm2.com](https://iterm2.com) or:

```bash
brew install --cask iterm2
```

## Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Add the following to `~/.zshrc`:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## Shell

### Starship (prompt)

```bash
brew install starship
```

### Sheldon (plugin manager)

```bash
brew install sheldon
sheldon init --shell zsh
```

### fzf (fuzzy finder)

```bash
brew install fzf
```

### ripgrep (fast search)

```bash
brew install ripgrep
```

### Font

```bash
brew install font-jetbrains-mono-nerd-font
```

Set in iTerm2: Settings > Profiles > Text > Font: **JetBrainsMono Nerd Font Mono**

## Development Tools

### Node.js (fnm + pnpm)

```bash
brew install fnm
brew install pnpm
```

### Python (uv)

```bash
brew install uv
uv python install 3.12
uv python pin 3.12
```

## Git / GitHub

```bash
brew install gh
```

### SSH key setup and GitHub auth

```bash
ssh-keygen
gh auth login
# Protocol: SSH / Key: id_ed25519
```

### Git alias

```bash
git config --global alias.st status\ --short
```

## Config Files

| Source | Destination |
| --- | --- |
| `config/starship.toml` | `~/.config/starship.toml` |
| `config/sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `config/zshrc` | `~/.zshrc` |
| `config/git/ignore` | `~/.config/git/ignore` |
| `config/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `config/claude/settings.json` | `~/.claude/settings.json` |

Check differences between this repo and local config:

```bash
./diff-config.zsh
```

Sync config files (only copies files with differences):

```bash
./sync-config.zsh
```

## Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

### gogcli (Google Workspace CLI)

```bash
brew install steipete/tap/gogcli
```

Setup OAuth and authorize your account:

```bash
# Store OAuth2 credentials (download from Google Cloud Console)
gog auth credentials ~/Downloads/client_secret_*.json

# Authorize your account
gog auth add you@gmail.com
```

### Skills

Open Claude Code and run:

```
# Add skill marketplaces
/plugin marketplace add anthropics/skills
/plugin marketplace add git@github.com:tani-shi/skills.git

# Install official skills (pdf, pptx, docx, xlsx, frontend-design, etc.)
/plugin install example-skills@anthropic-agent-skills

# Install Google Workspace integration (Gmail, Calendar, Drive, etc.)
/plugin install gogcli@tani-shi-skills
```
