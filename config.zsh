#!/bin/zsh
set -eu

if (( $# != 1 )) || [[ "$1" != "diff" && "$1" != "sync" ]]; then
  print -u2 "Usage: $0 diff|sync"
  exit 1
fi
MODE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/agent-sentinel.zsh"
CODEX_SKILLS_SRC="$SCRIPT_DIR/config/codex/skills"
CODEX_SKILLS_DST="$HOME/.agents/skills"
CODEX_SKILLS_MANIFEST="$CODEX_SKILLS_DST/.oh-my-mac-managed"

is_codex_skill_name() {
  local name=$1
  [[ -n "$name" && "$name" != *[^a-z0-9-]* && "$name" != -* && "$name" != *- && "$name" != *--* ]]
}

is_codex_skill_path() {
  local path=$1 skill_name="${1%%/*}"
  [[ "$path" == */* && "$path" != /* && "$path" != */ && "$path" != *//* && "$path" != *$'\n'* ]] || return 1
  [[ "/$path/" != *"/../"* && "/$path/" != *"/./"* ]] || return 1
  is_codex_skill_name "$skill_name"
}

configs=(
  "config/starship.toml:$HOME/.config/starship.toml"
  "config/sheldon/plugins.toml:$HOME/.config/sheldon/plugins.toml"
  "config/zshrc:$HOME/.zshrc"
  "config/git/ignore:$HOME/.config/git/ignore"
  "config/git/discard.zsh:$HOME/.config/git/discard.zsh")

for f in "$SCRIPT_DIR"/config/claude/agents/*.md(N) "$SCRIPT_DIR"/config/claude/scripts/*(.N) "$SCRIPT_DIR"/config/claude/skills/**/*(.N); do
  rel="${f#$SCRIPT_DIR/config/claude/}"
  configs+=("config/claude/$rel:$HOME/.claude/$rel")
done

for skill_dir in "$CODEX_SKILLS_SRC"/*(/N); do
  skill_name="${skill_dir:t}"
  if ! is_codex_skill_name "$skill_name"; then
    print -u2 "Invalid Codex skill directory: $skill_dir"
    exit 1
  fi
  for f in "$skill_dir"/**/*(.N); do
    rel="${f#$CODEX_SKILLS_SRC/}"
    configs+=("config/codex/skills/$rel:$CODEX_SKILLS_DST/$rel")
  done
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

# null is a meaningful value here, not an absence: Claude Code reads it as an explicit
# unbind of a default key, so the merge preserves it instead of dropping the entry.
JQ_KEYBINDINGS_MERGE='
  .[0] as $user | .[1] as $repo |
  $user | .bindings = [
    .bindings[] | . as $ub |
    ($repo.bindings | map(select(.context == $ub.context)) | first // null) as $rb |
    if $rb then .bindings = (.bindings * $rb.bindings)
    else . end
  ] + [
    $repo.bindings[] | select(
      .context as $c | $user.bindings | map(.context) | index($c) | not
    )
  ]
'

JQ_ITERM_PROFILE_MERGE='
  def merge($base; $local; $repo):
    reduce (((($base | keys) + ($local | keys) + ($repo | keys)) | unique)[]) as $key
      ({};
        ($base | has($key)) as $base_has |
        ($local | has($key)) as $local_has |
        ($repo | has($key)) as $repo_has |
        if $local_has and $repo_has
          and ($local[$key] | type) == "object"
          and ($repo[$key] | type) == "object"
          and (($base_has | not) or ($base[$key] | type) == "object")
        then .[$key] = merge(
          (if $base_has then $base[$key] else {} end);
          $local[$key];
          $repo[$key]
        )
        elif ($local_has == $base_has)
          and (($local_has | not) or $local[$key] == $base[$key])
        then if $repo_has then .[$key] = $repo[$key] else . end
        else if $local_has then .[$key] = $local[$key] else . end
        end
      );

  (.[0].Profiles[0] // {}) as $base |
  (.[1].Profiles[0] // {}) as $local |
  (.[2].Profiles[0] // {}) as $repo |
  {Profiles: [merge($base; $local; $repo)]}
'

SHARED_INSTRUCTIONS="$SCRIPT_DIR/config/agents/instructions.md"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
REPO_SETTINGS="$SCRIPT_DIR/config/claude/settings.json"
CLAUDE_KEYBINDINGS="$HOME/.claude/keybindings.json"
REPO_KEYBINDINGS="$SCRIPT_DIR/config/claude/keybindings.json"
ITERM_PROFILE_SRC="$SCRIPT_DIR/config/iterm2/profile.json"
ITERM_PROFILE_DST="$HOME/Library/Application Support/iTerm2/DynamicProfiles/profile.json"
ITERM_PROFILE_BASE="$HOME/Library/Application Support/oh-my-mac/iterm2-profile-baseline.json"
VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json"
REPO_VSCODE_SETTINGS="$SCRIPT_DIR/config/vscode/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
REPO_CODEX_CONFIG="$SCRIPT_DIR/config/codex/config.toml"
CODEX_HOOKS="$HOME/.codex/hooks.json"
CODEX_AGENT_SENTINEL_RULES="$HOME/.codex/rules/agent-sentinel.rules"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

diffs=0
synced=()
changes=0
CODEX_SKILLS_DESIRED="$tmpdir/codex-skills-managed"
GENERATED_CODEX_HOOKS="$tmpdir/codex/hooks.json"
GENERATED_CODEX_AGENT_SENTINEL_RULES="$tmpdir/codex/rules/agent-sentinel.rules"

sync_file() {
  local src=$1 dst=$2 label=$3
  if diff -q "$src" "$dst" &>/dev/null; then
    return 0
  fi
  if [[ "$MODE" == "diff" ]]; then
    if [[ -e "$dst" || -L "$dst" ]]; then
      git diff --no-index "$dst" "$src" || true
    else
      echo "New: $label -> $dst"
    fi
    diffs=$((diffs + 1))
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "Synced: $dst"
    synced+=("$src")
    changes=$((changes + 1))
  fi
}

sync_files() {
  local entry
  for entry in "${configs[@]}"; do
    sync_file "$SCRIPT_DIR/${entry%%:*}" "${entry##*:}" "${entry%%:*}"
  done
}

verify_agent_sentinel() {
  if ! command -v agent-sentinel &>/dev/null || ! agent-sentinel --help &>/dev/null; then
    print -u2 "Error: agent-sentinel must be installed before syncing its configuration"
    return 1
  fi
}

generate_agent_sentinel_codex_config() {
  mkdir -p "${GENERATED_CODEX_HOOKS:h}"
  if [[ -f "$CODEX_HOOKS" ]]; then
    cp "$CODEX_HOOKS" "$GENERATED_CODEX_HOOKS"
  fi
  agent-sentinel install --target codex --path "$GENERATED_CODEX_HOOKS" >/dev/null
  validate_agent_sentinel_codex_config \
    "$GENERATED_CODEX_HOOKS" "$GENERATED_CODEX_AGENT_SENTINEL_RULES"
}

sync_instructions() {
  local specific=$1 dst=$2
  local composed="$tmpdir/${specific:h:t}-instructions.md"
  { cat "$SHARED_INSTRUCTIONS"; echo; cat "$specific" } > "$composed"
  sync_file "$composed" "$dst" "config/agents/instructions.md + ${specific#$SCRIPT_DIR/}"
}

codex_skill_was_managed() {
  local expected=$1 managed_path
  [[ -f "$CODEX_SKILLS_MANIFEST" ]] || return 1
  while IFS= read -r managed_path || [[ -n "$managed_path" ]]; do
    if is_codex_skill_path "$managed_path" && [[ "${managed_path%%/*}" == "$expected" ]]; then
      return 0
    fi
  done < "$CODEX_SKILLS_MANIFEST"
  return 1
}

codex_skill_file_was_managed() {
  local expected=$1
  [[ -f "$CODEX_SKILLS_MANIFEST" ]] && grep -Fqx -- "$expected" "$CODEX_SKILLS_MANIFEST"
}

codex_skill_path_has_unsafe_parent() {
  local parent="${1:h}"
  while [[ "$parent" != "$CODEX_SKILLS_DST" ]]; do
    if [[ "$parent" == / || -L "$parent" || (-e "$parent" && ! -d "$parent") ]]; then
      return 0
    fi
    parent="${parent:h}"
  done
  return 1
}

prepare_codex_skills() {
  local skill_dir skill_name source rel destination managed_path orphan
  : > "$CODEX_SKILLS_DESIRED"
  for skill_dir in "$CODEX_SKILLS_SRC"/*(/N); do
    skill_name="${skill_dir:t}"
    destination="$CODEX_SKILLS_DST/$skill_name"
    if [[ -L "$destination" || (-e "$destination" && ! -d "$destination") ]]; then
      print -u2 "Unsafe Codex skill destination: $destination"
      return 1
    fi
    if [[ -d "$destination" ]] && ! codex_skill_was_managed "$skill_name"; then
      print -u2 "Unmanaged Codex skill already exists: $destination"
      return 1
    fi
    for source in "$skill_dir"/**/*(.N); do
      rel="${source#$CODEX_SKILLS_SRC/}"
      if ! is_codex_skill_path "$rel"; then
        print -u2 "Invalid Codex skill file: $source"
        return 1
      fi
      if codex_skill_path_has_unsafe_parent "$CODEX_SKILLS_DST/$rel"; then
        print -u2 "Unsafe Codex skill destination: $CODEX_SKILLS_DST/$rel"
        return 1
      fi
      destination="$CODEX_SKILLS_DST/$rel"
      if [[ -L "$destination" || -d "$destination" ]]; then
        print -u2 "Unsafe Codex skill file destination: $destination"
        return 1
      fi
      if [[ -e "$destination" ]] && ! codex_skill_file_was_managed "$rel"; then
        print -u2 "Unmanaged Codex skill file already exists: $destination"
        return 1
      fi
      print -r -- "$rel" >> "$CODEX_SKILLS_DESIRED"
    done
  done

  if [[ -f "$CODEX_SKILLS_MANIFEST" ]]; then
    while IFS= read -r managed_path || [[ -n "$managed_path" ]]; do
      is_codex_skill_path "$managed_path" || continue
      grep -Fqx -- "$managed_path" "$CODEX_SKILLS_DESIRED" && continue
      orphan="$CODEX_SKILLS_DST/$managed_path"
      if codex_skill_path_has_unsafe_parent "$orphan" || [[ -d "$orphan" && ! -L "$orphan" ]]; then
        print -u2 "Unsafe managed Codex skill file: $orphan"
        return 1
      fi
    done < "$CODEX_SKILLS_MANIFEST"
  fi
}

# Claude Code can keep using removed agents, scripts, and skills from ~/.claude,
# so orphans must be deleted, not merely left unsynced.
remove_claude_orphans() {
  local orphan_file orphan_dir rel
  for orphan_file in "$HOME"/.claude/agents/*.md(.N) "$HOME"/.claude/scripts/*(.N) \
    "$HOME"/.claude/skills/**/*(.N); do
    rel="${orphan_file#$HOME/.claude/}"
    if [[ ! -f "$SCRIPT_DIR/config/claude/$rel" ]]; then
      if [[ "$MODE" == "diff" ]]; then
        echo "Orphan: $orphan_file (no config/claude/$rel)"
        diffs=$((diffs + 1))
      else
        rm -f "$orphan_file"
        echo "Removed: $orphan_file"
        changes=$((changes + 1))
      fi
    fi
  done
  # On visits deepest-first: parent-first would report a nested directory its
  # parent already took.
  for orphan_dir in "$HOME"/.claude/skills/**/*(/NOn); do
    rel="${orphan_dir#$HOME/.claude/}"
    if [[ ! -d "$SCRIPT_DIR/config/claude/$rel" ]]; then
      if [[ "$MODE" == "diff" ]]; then
        echo "Orphan: $orphan_dir/ (no config/claude/$rel)"
        diffs=$((diffs + 1))
      else
        # rmdir would fail on a .DS_Store, which the file loop's (.N) glob skips.
        rm -rf "$orphan_dir"
        echo "Removed: $orphan_dir/"
        changes=$((changes + 1))
      fi
    fi
  done
}

# ~/.agents/skills is shared with independently installed skills, so only files
# recorded by this repository are eligible for removal.
reconcile_codex_skills() {
  local managed_path orphan skill_name orphan_dir
  local -A affected_skills
  if [[ -f "$CODEX_SKILLS_MANIFEST" ]]; then
    while IFS= read -r managed_path || [[ -n "$managed_path" ]]; do
      if ! is_codex_skill_path "$managed_path"; then
        echo "Ignored invalid managed Codex skill file: $managed_path"
        continue
      fi
      grep -Fqx -- "$managed_path" "$CODEX_SKILLS_DESIRED" && continue
      skill_name="${managed_path%%/*}"
      affected_skills[$skill_name]=1
      orphan="$CODEX_SKILLS_DST/$managed_path"
      if [[ ! -e "$orphan" && ! -L "$orphan" ]]; then
        continue
      fi
      if [[ "$MODE" == "diff" ]]; then
        echo "Orphan: $orphan (no config/codex/skills/$managed_path)"
        diffs=$((diffs + 1))
      else
        rm -f "$orphan"
        echo "Removed: $orphan"
        changes=$((changes + 1))
      fi
    done < "$CODEX_SKILLS_MANIFEST"
  fi

  if [[ "$MODE" == "sync" ]]; then
    for skill_name in "${(@k)affected_skills}"; do
      for orphan_dir in "$CODEX_SKILLS_DST/$skill_name"/**/*(/NOn); do
        rmdir "$orphan_dir" 2>/dev/null || true
      done
      rmdir "$CODEX_SKILLS_DST/$skill_name" 2>/dev/null || true
    done
  fi

  sync_file "$CODEX_SKILLS_DESIRED" "$CODEX_SKILLS_MANIFEST" "managed Codex skill files manifest"
}

run_post_sync_hooks() {
  if [[ "$MODE" != "sync" ]]; then
    return 0
  fi
  if [[ $changes -eq 0 ]]; then
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
  local merged="$tmpdir/${label// /-}.json" installed="$user_file"
  if [[ ! -f "$user_file" ]]; then
    installed="$tmpdir/${label// /-}-installed.json"
    echo "$empty_default" > "$installed"
  fi
  jq -s "$jq_expr" "$installed" "$repo_file" > "$merged"
  if ! diff -q "$installed" "$merged" &>/dev/null; then
    if [[ "$MODE" == "diff" ]]; then
      echo ""
      echo "$label.json:"
      git diff --no-index "$installed" "$merged" || true
      diffs=$((diffs + 1))
    else
      mkdir -p "$(dirname "$user_file")"
      cp "$merged" "$user_file"
      echo "Merged $label into $user_file"
      changes=$((changes + 1))
    fi
  fi
}

merge_codex_config() {
  local installed="$CODEX_CONFIG" merged="$tmpdir/codex-config.toml"
  if [[ ! -f "$installed" ]]; then
    installed="$tmpdir/codex-config-installed.toml"
    : > "$installed"
  fi
  uv run "$SCRIPT_DIR/scripts/merge-codex-config.py" "$installed" "$REPO_CODEX_CONFIG" > "$merged"
  sync_file "$merged" "$CODEX_CONFIG" "config/codex/config.toml"
}

sync_iterm_profile() {
  if [[ ! -f "$ITERM_PROFILE_SRC" ]]; then
    return 0
  fi
  local empty_profile="$tmpdir/empty-iterm-profile.json"
  local base_profile="$ITERM_PROFILE_BASE"
  local local_profile="$ITERM_PROFILE_DST"
  local merged_profile="$tmpdir/merged-iterm-profile.json"
  local strip_machine_specific_guid='del(.Profiles[].Guid)'
  local desired_sans_guid current_sans_guid guid
  print -r -- '{"Profiles":[{}]}' > "$empty_profile"
  [[ -f "$base_profile" ]] || base_profile="$empty_profile"
  [[ -f "$local_profile" ]] || local_profile="$empty_profile"
  jq -s "$JQ_ITERM_PROFILE_MERGE" \
    "$base_profile" "$local_profile" "$ITERM_PROFILE_SRC" > "$merged_profile"

  desired_sans_guid=$(jq -S "$strip_machine_specific_guid" "$merged_profile")
  current_sans_guid=""
  if [[ -f "$ITERM_PROFILE_DST" ]]; then
    current_sans_guid=$(jq -S "$strip_machine_specific_guid" "$ITERM_PROFILE_DST")
  fi
  if [[ "$desired_sans_guid" != "$current_sans_guid" ]]; then
    if [[ "$MODE" == "diff" ]]; then
      echo ""
      echo "iTerm2 Dynamic Profile:"
      if [[ -f "$ITERM_PROFILE_DST" ]]; then
        diff <(echo "$current_sans_guid") <(echo "$desired_sans_guid") | head -50 || true
      else
        echo "  current:  <not installed>"
        echo "  expected: $ITERM_PROFILE_SRC"
      fi
      diffs=$((diffs + 1))
    else
      mkdir -p "$(dirname "$ITERM_PROFILE_DST")"
      # iTerm2 identifies dynamic profiles by Guid; reusing the installed Guid
      # updates the profile in place instead of adding a duplicate.
      guid=$(jq -r '.Profiles[0].Guid // empty' "$merged_profile")
      [[ -n "$guid" ]] || guid=$(uuidgen)
      jq --arg guid "$guid" '.Profiles[0].Guid = $guid' "$merged_profile" \
        > "$ITERM_PROFILE_DST.tmp" && mv "$ITERM_PROFILE_DST.tmp" "$ITERM_PROFILE_DST"
      echo "Synced iTerm2 Dynamic Profile."
      changes=$((changes + 1))
    fi
  fi
  sync_file "$ITERM_PROFILE_SRC" "$ITERM_PROFILE_BASE" \
    "iTerm2 profile merge baseline"
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
      changes=$((changes + 1))
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
    "alias.st:status --short"
    "alias.discard:!zsh ~/.config/git/discard.zsh"
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
        changes=$((changes + 1))
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
          changes=$((changes + 1))
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
        changes=$((changes + 1))
      fi
    fi
  done
}

verify_agent_sentinel
generate_agent_sentinel_codex_config
prepare_codex_skills
sync_files
codex_hook_changed=0
if agent_sentinel_codex_hook_changed "$CODEX_HOOKS" "$GENERATED_CODEX_HOOKS"; then
  codex_hook_changed=1
fi
sync_file "$GENERATED_CODEX_HOOKS" "$CODEX_HOOKS" "generated agent-sentinel Codex hooks"
if [[ "$MODE" == "sync" && $codex_hook_changed -eq 1 ]]; then
  print_codex_hook_trust_instructions applied
fi
sync_file "$GENERATED_CODEX_AGENT_SENTINEL_RULES" "$CODEX_AGENT_SENTINEL_RULES" \
  "generated agent-sentinel Codex rules"
sync_instructions "$SCRIPT_DIR/config/claude/instructions.md" "$HOME/.claude/CLAUDE.md"
sync_instructions "$SCRIPT_DIR/config/codex/instructions.md" "$HOME/.codex/AGENTS.md"
remove_claude_orphans
reconcile_codex_skills
merge_json_config "Claude Code settings" "$CLAUDE_SETTINGS" "$REPO_SETTINGS" "$JQ_SETTINGS_MERGE" '{}'
merge_json_config "Claude Code keybindings" "$CLAUDE_KEYBINDINGS" "$REPO_KEYBINDINGS" "$JQ_KEYBINDINGS_MERGE" '{"bindings":[]}'
merge_codex_config
sync_iterm_profile
if [[ -f "$REPO_VSCODE_SETTINGS" ]]; then
  merge_json_config "VSCode settings" "$VSCODE_SETTINGS" "$REPO_VSCODE_SETTINGS" '.[0] * .[1]' '{}'
fi
install_vscode_extensions
apply_git_config
apply_duti
apply_macos_defaults
run_post_sync_hooks

if [[ "$MODE" == "diff" && $diffs -eq 0 ]]; then
  echo "No differences found."
fi
