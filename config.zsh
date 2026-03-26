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
  "config/claude/scripts/check-docs.zsh:$HOME/.claude/scripts/check-docs.zsh")

JQ_MERGE_EXPR='
  .[0] as $user | .[1] as $repo |
  $user |
  .hooks.Notification = ($repo.hooks.Notification // .hooks.Notification) |
  .hooks.Stop = ($repo.hooks.Stop // .hooks.Stop) |
  .hooks.PermissionRequest = ($repo.hooks.PermissionRequest // .hooks.PermissionRequest) |
  .includeCoAuthoredBy = (if $repo | has("includeCoAuthoredBy") then $repo.includeCoAuthoredBy else .includeCoAuthoredBy end) |
  .permissions = ($repo.permissions // .permissions) |
  del(.preferences)
'

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REPO_SETTINGS="$SCRIPT_DIR/config/claude/settings.json"
CLAUDE_KEYBINDINGS="$HOME/.claude/keybindings.json"
REPO_KEYBINDINGS="$SCRIPT_DIR/config/claude/keybindings.json"
ITERM_PROFILE_SRC="$SCRIPT_DIR/config/iterm2/profile.json"
ITERM_PROFILE_DST="$HOME/Library/Application Support/iTerm2/DynamicProfiles/profile.json"

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

# === Claude Code keybindings.json ===
[[ -f "$CLAUDE_KEYBINDINGS" ]] || echo '{"bindings":[]}' > "$CLAUDE_KEYBINDINGS"

JQ_KEYBINDINGS_MERGE='
  .[0] as $user | .[1] as $repo |
  $user | .bindings = [
    .bindings[] | . as $ub |
    ($repo.bindings | map(select(.context == $ub.context)) | first // null) as $rb |
    if $rb then .bindings = ((.bindings * $rb.bindings) | with_entries(select(.value != null)))
    else . end
  ] + [
    $repo.bindings[] | select(
      .context as $c | $user.bindings | map(.context) | index($c) | not
    )
  ]
'

jq -s "$JQ_KEYBINDINGS_MERGE" "$CLAUDE_KEYBINDINGS" "$REPO_KEYBINDINGS" > "$tmpdir/keybindings.json"

if ! diff -q "$CLAUDE_KEYBINDINGS" "$tmpdir/keybindings.json" &>/dev/null; then
  if [[ "$MODE" == "diff" ]]; then
    echo ""
    echo "Claude Code keybindings.json:"
    git diff --no-index "$CLAUDE_KEYBINDINGS" "$tmpdir/keybindings.json" || true
    diffs=$((diffs + 1))
  else
    cp "$tmpdir/keybindings.json" "$CLAUDE_KEYBINDINGS"
    echo "Merged Claude Code keybindings into $CLAUDE_KEYBINDINGS"
  fi
fi

# === iTerm2 Dynamic Profile ===
if [[ -f "$ITERM_PROFILE_SRC" ]]; then
  # Compare ignoring Guid (machine-specific)
  _iterm_normalize='del(.Profiles[].Guid)'
  _src_norm=$(jq "$_iterm_normalize" "$ITERM_PROFILE_SRC")
  _dst_norm=""
  if [[ -f "$ITERM_PROFILE_DST" ]]; then
    _dst_norm=$(jq "$_iterm_normalize" "$ITERM_PROFILE_DST")
  fi

  if [[ "$_src_norm" != "$_dst_norm" ]]; then
    if [[ "$MODE" == "diff" ]]; then
      echo ""
      echo "iTerm2 Dynamic Profile:"
      if [[ -f "$ITERM_PROFILE_DST" ]]; then
        diff <(echo "$_dst_norm") <(echo "$_src_norm") | head -50 || true
      else
        echo "  current:  <not installed>"
        echo "  expected: $ITERM_PROFILE_SRC"
      fi
      diffs=$((diffs + 1))
    else
      mkdir -p "$(dirname "$ITERM_PROFILE_DST")"
      if [[ -f "$ITERM_PROFILE_DST" ]]; then
        # Merge: overwrite with src settings but preserve dst's Guid
        jq -n --slurpfile dst "$ITERM_PROFILE_DST" --slurpfile src "$ITERM_PROFILE_SRC" '
          $src[0] | .Profiles[0].Guid = $dst[0].Profiles[0].Guid
        ' > "$ITERM_PROFILE_DST.tmp" && mv "$ITERM_PROFILE_DST.tmp" "$ITERM_PROFILE_DST"
      else
        # No existing file: generate a new Guid
        jq --arg guid "$(uuidgen)" '
          .Profiles[0].Guid = $guid
        ' "$ITERM_PROFILE_SRC" > "$ITERM_PROFILE_DST"
      fi
      echo "Synced iTerm2 Dynamic Profile."
    fi
  fi
fi

# === git-delta pager config ===
git_delta_keys=(
  "core.pager:delta"
  "interactive.diffFilter:delta --color-only"
  "delta.navigate:true"
  "delta.side-by-side:true"
  "delta.line-numbers:true"
  "delta.hunk-header-style:omit"
  "merge.conflictstyle:diff3"
)

for entry in "${git_delta_keys[@]}"; do
  key="${entry%%:*}"
  expected="${entry#*:}"
  current=$(git config --global "$key" 2>/dev/null || echo "")
  if [[ "$current" != "$expected" ]]; then
    if [[ "$MODE" == "diff" ]]; then
      echo ""
      echo "git config --global $key:"
      echo "  current:  ${current:-<unset>}"
      echo "  expected: $expected"
      diffs=$((diffs + 1))
    else
      git config --global "$key" "$expected"
      echo "Set git config: $key = $expected"
    fi
  fi
done

# === duti file associations ===
DUTI_FILE="$SCRIPT_DIR/config/duti/defaults.duti"
if command -v duti &>/dev/null && [[ -f "$DUTI_FILE" ]]; then
  while IFS=' ' read -r bundle ext role; do
    [[ -z "$bundle" || "$bundle" == \#* ]] && continue
    current=$(duti -x "${ext#.}" 2>/dev/null | head -1 || echo "")
    if [[ "$current" != "Visual Studio Code" ]]; then
      if [[ "$MODE" == "diff" ]]; then
        echo ""
        echo "duti ${ext}:"
        echo "  current:  ${current:-<unset>}"
        echo "  expected: Visual Studio Code ($bundle)"
        diffs=$((diffs + 1))
      else
        if duti -s "$bundle" "$ext" "$role" 2>/dev/null; then
          echo "Set default for ${ext} → Visual Studio Code"
        else
          echo "Warning: failed to set default for ${ext} (skipped)"
        fi
      fi
    fi
  done < "$DUTI_FILE"
fi

# === diff summary ===
if [[ "$MODE" == "diff" && $diffs -eq 0 ]]; then
  echo "No differences found."
fi
