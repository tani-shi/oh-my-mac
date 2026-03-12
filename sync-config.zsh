#!/bin/zsh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

configs=(
  "config/starship.toml:$HOME/.config/starship.toml"
  "config/sheldon/plugins.toml:$HOME/.config/sheldon/plugins.toml"
  "config/zshrc:$HOME/.zshrc"
  "config/git/ignore:$HOME/.config/git/ignore"
  "config/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "config/summarize/config.json:$HOME/.summarize/config.json"
)

synced=()
for entry in "${configs[@]}"; do
  src="$SCRIPT_DIR/${entry%%:*}"
  dst="${entry##*:}"
  if ! diff -q "$src" "$dst" &>/dev/null; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "Synced: $dst"
    synced+=("$src")
  fi
done

if [[ ${#synced[@]} -eq 0 ]]; then
  echo "Already up to date."
else
  # Post-sync hooks
  for src in "${synced[@]}"; do
    case "$src" in
      */sheldon/plugins.toml)
        echo "Running: sheldon lock --update"
        sheldon lock --update
        ;;
      */zshrc)
        echo "Run 'source ~/.zshrc' to apply changes."
        ;;
    esac
  done
fi

# Merge Claude Code settings.json (idempotent)
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REPO_SETTINGS="$SCRIPT_DIR/config/claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[[ -f "$CLAUDE_SETTINGS" ]] || echo '{}' > "$CLAUDE_SETTINGS"

jq -s '
  .[0] as $user | .[1] as $repo |
  $user |
  .permissions.allow = ((.permissions.allow // []) + ($repo.permissions.allow // []) | unique) |
  .permissions.deny = ((.permissions.deny // []) + ($repo.permissions.deny // []) | unique) |
  .hooks.Notification = ($repo.hooks.Notification // .hooks.Notification) |
  .hooks.Stop = ($repo.hooks.Stop // .hooks.Stop) |
  .preferences.defaultMode = ($repo.preferences.defaultMode // .preferences.defaultMode)
' "$CLAUDE_SETTINGS" "$REPO_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
echo "Merged Claude Code settings into $CLAUDE_SETTINGS"

# Install Claude Code plugins
PLUGIN_LIST="$SCRIPT_DIR/config/claude/plugins.txt"
if [[ -f "$PLUGIN_LIST" ]] && command -v claude &>/dev/null; then
  # Merge extraKnownMarketplaces from repo settings
  if jq -e '.extraKnownMarketplaces' "$REPO_SETTINGS" &>/dev/null; then
    jq -s '.[0].extraKnownMarketplaces = ((.[0].extraKnownMarketplaces // {}) * (.[1].extraKnownMarketplaces // {})) | .[0]' \
      "$CLAUDE_SETTINGS" "$REPO_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
  fi

  while IFS= read -r plugin || [[ -n "$plugin" ]]; do
    [[ -z "$plugin" || "$plugin" == \#* ]] && continue
    if ! jq -e --arg p "$plugin" '.enabledPlugins[$p]' "$CLAUDE_SETTINGS" &>/dev/null; then
      echo "Installing plugin: $plugin"
      claude plugin install "$plugin" 2>/dev/null || echo "Warning: Failed to install $plugin"
    fi
  done < "$PLUGIN_LIST"
  echo "Claude Code plugins synced."
fi

# Install bash-guard
if command -v bash-guard &>/dev/null; then
  bash-guard install
  echo "bash-guard installed."
else
  echo "Warning: bash-guard not found. Skipping bash-guard install."
fi
