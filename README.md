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
