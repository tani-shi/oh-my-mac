#!/bin/zsh
set -eu

MODE="${1:?Usage: $0 diff|sync}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

configs=(
  "config/starship.toml:$HOME/.config/starship.toml"
  "config/sheldon/plugins.toml:$HOME/.config/sheldon/plugins.toml"
  "config/mise/config.toml:$HOME/.config/mise/config.toml"
  "config/zshrc:$HOME/.zshrc"
  "config/git/ignore:$HOME/.config/git/ignore"
  "config/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md")

for f in "$SCRIPT_DIR"/config/claude/agents/*.md(N) "$SCRIPT_DIR"/config/claude/scripts/*(.N) "$SCRIPT_DIR"/config/claude/skills/**/*(.N); do
  rel="${f#$SCRIPT_DIR/config/claude/}"
  configs+=("config/claude/$rel:$HOME/.claude/$rel")
done

JQ_SETTINGS_MERGE='
  .[0] as $user | .[1] as $repo |
  $user |
  .hooks = ((.hooks // {}) * ($repo.hooks // {})) |
  .env = ((.env // {}) * ($repo.env // {})) |
  (if $repo | has("extraKnownMarketplaces")
    then .extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) * $repo.extraKnownMarketplaces)
    else . end) |
  .permissions = ($repo.permissions // .permissions) |
  reduce ["includeCoAuthoredBy", "teammateMode", "tui"][] as $k
    (.; if $repo | has($k) then .[$k] = $repo[$k] else . end) |
  del(.preferences)
'

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

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REPO_SETTINGS="$SCRIPT_DIR/config/claude/settings.json"
CLAUDE_KEYBINDINGS="$HOME/.claude/keybindings.json"
REPO_KEYBINDINGS="$SCRIPT_DIR/config/claude/keybindings.json"
ITERM_PROFILE_SRC="$SCRIPT_DIR/config/iterm2/profile.json"
ITERM_PROFILE_DST="$HOME/Library/Application Support/iTerm2/DynamicProfiles/profile.json"
VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
REPO_VSCODE_SETTINGS="$SCRIPT_DIR/config/vscode/settings.json"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

diffs=0
synced=()
removed=0

sync_files() {
  local entry src dst
  for entry in "${configs[@]}"; do
    src="$SCRIPT_DIR/${entry%%:*}"
    dst="${entry##*:}"
    if ! diff -q "$src" "$dst" &>/dev/null; then
      if [[ "$MODE" == "diff" ]]; then
        if [[ -e "$dst" || -L "$dst" ]]; then
          git diff --no-index "$dst" "$src" || true
        else
          echo "New: ${entry%%:*} -> $dst"
        fi
        diffs=$((diffs + 1))
      else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "Synced: $dst"
        synced+=("$src")
      fi
    fi
  done
}

# Claude Code loads any file present in ~/.claude/agents/ and ~/.claude/skills/
# regardless of repo state, so orphans must be deleted, not merely left unsynced.
remove_orphans() {
  local dst rel
  for dst in "$HOME"/.claude/agents/*.md(.N) "$HOME"/.claude/skills/**/*(.N); do
    rel="${dst#$HOME/.claude/}"
    if [[ ! -f "$SCRIPT_DIR/config/claude/$rel" ]]; then
      if [[ "$MODE" == "diff" ]]; then
        echo "Orphan: $dst (no config/claude/$rel)"
        diffs=$((diffs + 1))
      else
        trash "$dst"
        echo "Removed: $dst"
        removed=$((removed + 1))
      fi
    fi
  done
}

run_post_sync_hooks() {
  if [[ "$MODE" != "sync" ]]; then
    return 0
  fi
  if [[ ${#synced[@]} -eq 0 && $removed -eq 0 ]]; then
    echo "Already up to date."
    return 0
  fi
  local src
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
}

merge_json_config() {
  local label=$1 user_file=$2 repo_file=$3 jq_expr=$4 empty_default=$5
  local merged="$tmpdir/${label// /-}.json"
  mkdir -p "$(dirname "$user_file")"
  [[ -f "$user_file" ]] || echo "$empty_default" > "$user_file"
  jq -s "$jq_expr" "$user_file" "$repo_file" > "$merged"
  if ! diff -q "$user_file" "$merged" &>/dev/null; then
    if [[ "$MODE" == "diff" ]]; then
      echo ""
      echo "$label.json:"
      git diff --no-index "$user_file" "$merged" || true
      diffs=$((diffs + 1))
    else
      cp "$merged" "$user_file"
      echo "Merged $label into $user_file"
    fi
  fi
}

sync_iterm_profile() {
  if [[ ! -f "$ITERM_PROFILE_SRC" ]]; then
    return 0
  fi
  local strip_machine_specific_guid='del(.Profiles[].Guid)'
  local src_sans_guid dst_sans_guid guid
  src_sans_guid=$(jq "$strip_machine_specific_guid" "$ITERM_PROFILE_SRC")
  dst_sans_guid=""
  if [[ -f "$ITERM_PROFILE_DST" ]]; then
    dst_sans_guid=$(jq "$strip_machine_specific_guid" "$ITERM_PROFILE_DST")
  fi
  if [[ "$src_sans_guid" == "$dst_sans_guid" ]]; then
    return 0
  fi
  if [[ "$MODE" == "diff" ]]; then
    echo ""
    echo "iTerm2 Dynamic Profile:"
    if [[ -f "$ITERM_PROFILE_DST" ]]; then
      diff <(echo "$dst_sans_guid") <(echo "$src_sans_guid") | head -50 || true
    else
      echo "  current:  <not installed>"
      echo "  expected: $ITERM_PROFILE_SRC"
    fi
    diffs=$((diffs + 1))
  else
    mkdir -p "$(dirname "$ITERM_PROFILE_DST")"
    # iTerm2 identifies dynamic profiles by Guid; reusing the installed Guid
    # updates the profile in place instead of adding a duplicate.
    guid=""
    if [[ -f "$ITERM_PROFILE_DST" ]]; then
      guid=$(jq -r '.Profiles[0].Guid // empty' "$ITERM_PROFILE_DST" 2>/dev/null || true)
    fi
    [[ -n "$guid" ]] || guid=$(uuidgen)
    jq --arg guid "$guid" '.Profiles[0].Guid = $guid' "$ITERM_PROFILE_SRC" \
      > "$ITERM_PROFILE_DST.tmp" && mv "$ITERM_PROFILE_DST.tmp" "$ITERM_PROFILE_DST"
    echo "Synced iTerm2 Dynamic Profile."
  fi
}

install_vscode_extensions() {
  local extensions_file="$SCRIPT_DIR/config/vscode/extensions.txt"
  if ! command -v code &>/dev/null || [[ ! -f "$extensions_file" ]]; then
    return 0
  fi
  local installed ext
  local -a missing
  missing=()
  installed=$(code --list-extensions 2>/dev/null)
  while IFS= read -r ext || [[ -n "$ext" ]]; do
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    if ! echo "$installed" | grep -qix "$ext"; then
      missing+=("$ext")
    fi
  done < "$extensions_file"

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi
  if [[ "$MODE" == "diff" ]]; then
    echo ""
    echo "VSCode extensions (missing):"
    for ext in "${missing[@]}"; do
      echo "  + $ext"
    done
    diffs=$((diffs + 1))
  else
    for ext in "${missing[@]}"; do
      echo "Installing VSCode extension: $ext"
      code --install-extension "$ext" 2>/dev/null || echo "Warning: failed to install $ext"
    done
  fi
}

apply_git_config() {
  local -a git_config_keys
  git_config_keys=(
    "core.quotepath:false"
    "core.pager:delta"
    "interactive.diffFilter:delta --color-only"
    "delta.navigate:true"
    "delta.side-by-side:false"
    "delta.line-numbers:true"
    "delta.hunk-header-style:omit"
    "merge.conflictstyle:diff3"
    "filter.lfs.clean:git-lfs clean -- %f"
    "filter.lfs.smudge:git-lfs smudge -- %f"
    "filter.lfs.process:git-lfs filter-process"
    "filter.lfs.required:true"
  )
  local entry key expected current
  for entry in "${git_config_keys[@]}"; do
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
}

apply_duti() {
  local duti_file="$SCRIPT_DIR/config/duti/defaults.duti"
  if ! command -v duti &>/dev/null || [[ ! -f "$duti_file" ]]; then
    return 0
  fi
  local bundle ext role current
  while IFS=' ' read -r bundle ext role; do
    [[ -z "$bundle" || "$bundle" == \#* ]] && continue
    # duti -x prints three lines: app name, app path, bundle id
    current=$(duti -x "${ext#.}" 2>/dev/null | tail -1)
    if [[ "$current" != "$bundle" ]]; then
      if [[ "$MODE" == "diff" ]]; then
        echo ""
        echo "duti ${ext}:"
        echo "  current:  ${current:-<unset>}"
        echo "  expected: $bundle"
        diffs=$((diffs + 1))
      else
        if duti -s "$bundle" "$ext" "$role" 2>/dev/null; then
          echo "Set default for ${ext} → $bundle"
        else
          echo "Warning: failed to set default for ${ext} (skipped)"
        fi
      fi
    fi
  done < "$duti_file"
}

apply_macos_defaults() {
  local -a macos_defaults
  macos_defaults=(
    "NSGlobalDomain:NSAutomaticWindowAnimationsEnabled:bool:false"
  )
  local entry domain rest key type expected current norm_expected
  for entry in "${macos_defaults[@]}"; do
    domain="${entry%%:*}"; rest="${entry#*:}"
    key="${rest%%:*}"; rest="${rest#*:}"
    type="${rest%%:*}"; expected="${rest#*:}"
    current=$(defaults read "$domain" "$key" 2>/dev/null || echo "<unset>")
    # defaults(1) prints booleans as 0/1
    if [[ "$type" == "bool" ]]; then
      [[ "$expected" == "false" ]] && norm_expected="0" || norm_expected="1"
    else
      norm_expected="$expected"
    fi
    if [[ "$current" != "$norm_expected" ]]; then
      if [[ "$MODE" == "diff" ]]; then
        echo ""
        echo "defaults $domain $key:"
        echo "  current:  $current"
        echo "  expected: $expected"
        diffs=$((diffs + 1))
      else
        defaults write "$domain" "$key" "-$type" "$expected"
        echo "Set defaults: $domain $key = $expected"
      fi
    fi
  done
}

sync_files
remove_orphans
run_post_sync_hooks
merge_json_config "Claude Code settings" "$CLAUDE_SETTINGS" "$REPO_SETTINGS" "$JQ_SETTINGS_MERGE" '{}'
merge_json_config "Claude Code keybindings" "$CLAUDE_KEYBINDINGS" "$REPO_KEYBINDINGS" "$JQ_KEYBINDINGS_MERGE" '{"bindings":[]}'
sync_iterm_profile
if [[ -f "$REPO_VSCODE_SETTINGS" ]]; then
  merge_json_config "VSCode settings" "$VSCODE_SETTINGS" "$REPO_VSCODE_SETTINGS" '.[0] * .[1]' '{}'
fi
install_vscode_extensions
apply_git_config
apply_duti
apply_macos_defaults

if [[ "$MODE" == "diff" && $diffs -eq 0 ]]; then
  echo "No differences found."
fi
