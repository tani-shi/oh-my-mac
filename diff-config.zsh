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

diffs=0
for entry in "${configs[@]}"; do
  src="$SCRIPT_DIR/${entry%%:*}"
  dst="${entry##*:}"
  if ! diff -q "$src" "$dst" &>/dev/null; then
    git diff --no-index "$dst" "$src" || true
    diffs=$((diffs + 1))
  fi
done

if [[ $diffs -eq 0 ]]; then
  echo "No differences found."
fi

# Show diff for Claude Code settings (jq merge result vs current)
settings="$HOME/.claude/settings.json"
repo_settings="$SCRIPT_DIR/config/claude/settings.json"
if [[ -f "$settings" ]]; then
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  jq -s '
    .[0] as $user | .[1] as $repo |
    $user |
    .permissions.allow = ((.permissions.allow // []) + ($repo.permissions.allow // []) | unique) |
    .permissions.deny = ((.permissions.deny // []) + ($repo.permissions.deny // []) | unique) |
    .hooks.Notification = ($repo.hooks.Notification // .hooks.Notification) |
    .hooks.Stop = ($repo.hooks.Stop // .hooks.Stop) |
    .preferences.defaultMode = ($repo.preferences.defaultMode // .preferences.defaultMode) |
    .includeCoAuthoredBy = ($repo.includeCoAuthoredBy // .includeCoAuthoredBy)
  ' "$settings" "$repo_settings" > "$tmpdir/settings.json"
  # Merge extraKnownMarketplaces
  if jq -e '.extraKnownMarketplaces' "$repo_settings" &>/dev/null; then
    jq -s '.[0].extraKnownMarketplaces = ((.[0].extraKnownMarketplaces // {}) * (.[1].extraKnownMarketplaces // {})) | .[0]' \
      "$tmpdir/settings.json" "$repo_settings" > "$tmpdir/settings2.json" && mv "$tmpdir/settings2.json" "$tmpdir/settings.json"
  fi
  if ! diff -q "$settings" "$tmpdir/settings.json" &>/dev/null; then
    echo ""
    echo "Claude Code settings.json:"
    git diff --no-index "$settings" "$tmpdir/settings.json" || true
    diffs=$((diffs + 1))
  fi
fi

# Show plugins to be installed
plugin_list="$SCRIPT_DIR/config/claude/plugins.txt"
if [[ -f "$plugin_list" ]] && [[ -f "$settings" ]]; then
  missing=()
  while IFS= read -r plugin || [[ -n "$plugin" ]]; do
    [[ -z "$plugin" || "$plugin" == \#* ]] && continue
    if ! jq -e --arg p "$plugin" '.enabledPlugins[$p]' "$settings" &>/dev/null; then
      missing+=("$plugin")
    fi
  done < "$plugin_list"
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    echo "Claude Code plugins to install:"
    for p in "${missing[@]}"; do
      echo "  + $p"
    done
    diffs=$((diffs + 1))
  fi
fi
