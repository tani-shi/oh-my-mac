#!/bin/zsh
set -eu

MODE="${1:?Usage: $0 diff|sync}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# === Shared definitions ===
configs=(
  "config/starship.toml:$HOME/.config/starship.toml"
  "config/sheldon/plugins.toml:$HOME/.config/sheldon/plugins.toml"
  "config/zshrc:$HOME/.zshrc"
  "config/git/ignore:$HOME/.config/git/ignore"
  "config/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "config/summarize/config.json:$HOME/.summarize/config.json"
)

JQ_MERGE_EXPR='
  .[0] as $user | .[1] as $repo |
  $user |
  .hooks.Notification = ($repo.hooks.Notification // .hooks.Notification) |
  .hooks.Stop = ($repo.hooks.Stop // .hooks.Stop) |
  .hooks.PermissionRequest = ($repo.hooks.PermissionRequest // .hooks.PermissionRequest) |
  .preferences.defaultMode = ($repo.preferences.defaultMode // .preferences.defaultMode) |
  .includeCoAuthoredBy = (if $repo | has("includeCoAuthoredBy") then $repo.includeCoAuthoredBy else .includeCoAuthoredBy end) |
  .permissions = ($repo.permissions // .permissions)
'

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REPO_SETTINGS="$SCRIPT_DIR/config/claude/settings.json"
ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
ITERM_KEY=":New Bookmarks:0:Title Components"
ITERM_EXPECTED="1"

# === File sync ===
diffs=0
synced=()
for entry in "${configs[@]}"; do
  src="$SCRIPT_DIR/${entry%%:*}"
  dst="${entry##*:}"
  if ! diff -q "$src" "$dst" &>/dev/null; then
    if [[ "$MODE" == "diff" ]]; then
      git diff --no-index "$dst" "$src" || true
      diffs=$((diffs + 1))
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "Synced: $dst"
      synced+=("$src")
    fi
  fi
done

if [[ "$MODE" == "sync" ]]; then
  if [[ ${#synced[@]} -eq 0 ]]; then
    echo "Already up to date."
  else
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
fi

# === Claude Code settings.json ===
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[[ -f "$CLAUDE_SETTINGS" ]] || echo '{}' > "$CLAUDE_SETTINGS"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

jq -s "$JQ_MERGE_EXPR" "$CLAUDE_SETTINGS" "$REPO_SETTINGS" > "$tmpdir/settings.json"

if jq -e '.extraKnownMarketplaces' "$REPO_SETTINGS" &>/dev/null; then
  jq -s '.[0].extraKnownMarketplaces = ((.[0].extraKnownMarketplaces // {}) * (.[1].extraKnownMarketplaces // {})) | .[0]' \
    "$tmpdir/settings.json" "$REPO_SETTINGS" > "$tmpdir/settings2.json" && mv "$tmpdir/settings2.json" "$tmpdir/settings.json"
fi

if ! diff -q "$CLAUDE_SETTINGS" "$tmpdir/settings.json" &>/dev/null; then
  if [[ "$MODE" == "diff" ]]; then
    echo ""
    echo "Claude Code settings.json:"
    git diff --no-index "$CLAUDE_SETTINGS" "$tmpdir/settings.json" || true
    diffs=$((diffs + 1))
  else
    cp "$tmpdir/settings.json" "$CLAUDE_SETTINGS"
    echo "Merged Claude Code settings into $CLAUDE_SETTINGS"
  fi
fi


# === iTerm2 plist ===
if [[ -f "$ITERM_PLIST" ]]; then
  current=$(/usr/libexec/PlistBuddy -c "Print '$ITERM_KEY'" "$ITERM_PLIST" 2>/dev/null || echo "")
  if [[ "$current" != "$ITERM_EXPECTED" ]]; then
    if [[ "$MODE" == "diff" ]]; then
      echo ""
      echo "iTerm2 Title Components:"
      echo "  current: ${current:-<unset>}"
      echo "  expected: $ITERM_EXPECTED (Session Name only)"
      diffs=$((diffs + 1))
    else
      /usr/libexec/PlistBuddy -c "Set '$ITERM_KEY' $ITERM_EXPECTED" "$ITERM_PLIST" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c "Add '$ITERM_KEY' integer $ITERM_EXPECTED" "$ITERM_PLIST"
      echo "iTerm2: Tab title set to Session Name only."
    fi
  fi
fi

# === diff summary ===
if [[ "$MODE" == "diff" && $diffs -eq 0 ]]; then
  echo "No differences found."
fi
