#!/bin/zsh
set -eu

if (( $# != 1 )) || [[ "$1" != "diff" && "$1" != "sync" ]]; then
  print -u2 "Usage: $0 diff|sync"
  exit 1
fi
MODE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/agent-sentinel.zsh"
source "$SCRIPT_DIR/scripts/config-tools.zsh"
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
changes=0
staged_sources=()
staged_destinations=()
staged_labels=()
staged_formats=()
claude_orphan_files=()
claude_orphan_dirs=()
codex_orphans=()
codex_affected_skills=()
missing_vscode_extensions=()
pending_git_keys=()
pending_git_values=()
pending_duti_bundles=()
pending_duti_extensions=()
pending_duti_roles=()
duti_unavailable=0
pending_defaults_domains=()
pending_defaults_keys=()
pending_defaults_types=()
pending_defaults_values=()
applied_targets=()
sheldon_lock_pending=0
zshrc_update_pending=0
CODEX_SKILLS_DESIRED="$tmpdir/codex-skills-managed"
CODEX_SKILLS_APPLY_MANIFEST="$tmpdir/codex-skills-apply-managed"
GENERATED_CODEX_HOOKS="$tmpdir/codex/hooks.json"
GENERATED_CODEX_AGENT_SENTINEL_RULES="$tmpdir/codex/rules/agent-sentinel.rules"
SHELDON_LOCK_PENDING="$HOME/.config/sheldon/.oh-my-mac-lock-pending"

require_command() {
  local command=$1 reason=$2
  if ! command -v "$command" &>/dev/null; then
    print -u2 "Error: $command is required $reason"
    return 1
  fi
}

validate_destination() {
  local destination=$1 parent="${1:h}"
  if [[ -d "$destination" ]]; then
    print -u2 "Error: managed file destination is a directory: $destination"
    return 1
  fi
  while [[ ! -e "$parent" && ! -L "$parent" && "$parent" != / ]]; do
    parent="${parent:h}"
  done
  if [[ ! -d "$parent" ]]; then
    print -u2 "Error: managed file parent is not a directory: $parent"
    return 1
  fi
}

stage_file() {
  local source=$1 destination=$2 label=$3 format=${4:-normal}
  local staged="$tmpdir/staged/$(( ${#staged_sources[@]} + 1 ))"
  if [[ ! -f "$source" || ! -r "$source" ]]; then
    print -u2 "Error: managed source is not a readable file: $source"
    return 1
  fi
  validate_destination "$destination"
  mkdir -p "${staged:h}"
  cp "$source" "$staged"
  staged_sources+=("$staged")
  staged_destinations+=("$destination")
  staged_labels+=("$label")
  staged_formats+=("$format")
}

prepare_sync_files() {
  local entry
  for entry in "${configs[@]}"; do
    stage_file "$SCRIPT_DIR/${entry%%:*}" "${entry##*:}" "${entry%%:*}"
  done
}

validate_local_inputs() {
  local input
  for input in "$SCRIPT_DIR"/config/**/*.json(.N); do
    if ! jq empty "$input"; then
      print -u2 "Error: invalid JSON configuration: $input"
      return 1
    fi
  done
  for input in "$SCRIPT_DIR"/config/**/*.toml(.N); do
    if ! PYTHONDONTWRITEBYTECODE=1 "$CONFIG_TOOLS_PYTHON" -c \
      'import pathlib, sys, tomlkit; tomlkit.parse(pathlib.Path(sys.argv[1]).read_text())' \
      "$input"; then
      print -u2 "Error: invalid TOML configuration: $input"
      return 1
    fi
  done
  for input in "$SCRIPT_DIR"/config/**/*.zsh(.N) "$SCRIPT_DIR/config/zshrc"; do
    if ! zsh -n "$input"; then
      print -u2 "Error: invalid zsh configuration: $input"
      return 1
    fi
  done
}

verify_agent_sentinel() {
  if ! command -v agent-sentinel &>/dev/null || ! agent-sentinel --help &>/dev/null; then
    print -u2 "Error: agent-sentinel must be installed before syncing its configuration"
    return 1
  fi
}

prepare_agent_sentinel_codex_config() {
  if [[ -f "$CODEX_HOOKS" ]]; then
    mkdir -p "${GENERATED_CODEX_HOOKS:h}"
    cp "$CODEX_HOOKS" "$GENERATED_CODEX_HOOKS"
  fi
  generate_agent_sentinel_codex_config \
    "$GENERATED_CODEX_HOOKS" "$GENERATED_CODEX_AGENT_SENTINEL_RULES" "$CODEX_CONFIG"
}

prepare_instructions() {
  local specific=$1 dst=$2
  local composed="$tmpdir/${specific:h:t}-instructions.md"
  { cat "$SHARED_INSTRUCTIONS"; echo; cat "$specific" } > "$composed"
  stage_file "$composed" "$dst" "config/agents/instructions.md + ${specific#$SCRIPT_DIR/}"
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
  local discovered="$tmpdir/codex-skills-discovered"
  local apply_managed="$tmpdir/codex-skills-apply-discovered"
  : > "$discovered"
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
      print -r -- "$rel" >> "$discovered"
    done
  done
  LC_ALL=C sort "$discovered" > "$CODEX_SKILLS_DESIRED"
  cp "$CODEX_SKILLS_DESIRED" "$apply_managed"

  if [[ -f "$CODEX_SKILLS_MANIFEST" ]]; then
    while IFS= read -r managed_path || [[ -n "$managed_path" ]]; do
      is_codex_skill_path "$managed_path" || continue
      print -r -- "$managed_path" >> "$apply_managed"
      grep -Fqx -- "$managed_path" "$CODEX_SKILLS_DESIRED" && continue
      orphan="$CODEX_SKILLS_DST/$managed_path"
      if codex_skill_path_has_unsafe_parent "$orphan" || [[ -d "$orphan" && ! -L "$orphan" ]]; then
        print -u2 "Unsafe managed Codex skill file: $orphan"
        return 1
      fi
      codex_orphans+=("$orphan")
      codex_affected_skills+=("${managed_path%%/*}")
    done < "$CODEX_SKILLS_MANIFEST"
  fi
  LC_ALL=C sort -u "$apply_managed" > "$CODEX_SKILLS_APPLY_MANIFEST"
}

prepare_claude_orphans() {
  local orphan_file orphan_dir rel
  for orphan_file in "$HOME"/.claude/agents/*.md(.N) "$HOME"/.claude/scripts/*(.N) \
    "$HOME"/.claude/skills/**/*(.N); do
    rel="${orphan_file#$HOME/.claude/}"
    if [[ ! -f "$SCRIPT_DIR/config/claude/$rel" ]]; then
      claude_orphan_files+=("$orphan_file")
    fi
  done
  for orphan_dir in "$HOME"/.claude/skills/**/*(/NOn); do
    rel="${orphan_dir#$HOME/.claude/}"
    if [[ ! -d "$SCRIPT_DIR/config/claude/$rel" ]]; then
      claude_orphan_dirs+=("$orphan_dir")
    fi
  done
}

prepare_json_config() {
  local label=$1 user_file=$2 repo_file=$3 jq_expr=$4 empty_default=$5
  local merged="$tmpdir/${label// /-}.json" installed="$user_file"
  if [[ ! -f "$user_file" ]]; then
    installed="$tmpdir/${label// /-}-installed.json"
    echo "$empty_default" > "$installed"
  fi
  jq -s "$jq_expr" "$installed" "$repo_file" > "$merged"
  stage_file "$merged" "$user_file" "$label" merged-json
}

prepare_codex_config() {
  local installed="$CODEX_CONFIG" merged="$tmpdir/codex-config.toml"
  if [[ ! -f "$installed" ]]; then
    installed="$tmpdir/codex-config-installed.toml"
    : > "$installed"
  fi
  if [[ ! -x "$CONFIG_TOOLS_PYTHON" ]]; then
    print -u2 "Error: $CONFIG_TOOLS_PYTHON not found; run make install-config-tools"
    return 1
  fi
  PYTHONDONTWRITEBYTECODE=1 "$CONFIG_TOOLS_PYTHON" \
    "$SCRIPT_DIR/scripts/merge-codex-config.py" "$installed" "$REPO_CODEX_CONFIG" > "$merged"
  stage_file "$merged" "$CODEX_CONFIG" "config/codex/config.toml"
}

prepare_iterm_profile() {
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
    guid=$(jq -r '.Profiles[0].Guid // empty' "$merged_profile")
    if [[ -z "$guid" ]]; then
      require_command uuidgen "to prepare the iTerm2 Dynamic Profile"
      guid=$(uuidgen)
    fi
    jq --arg guid "$guid" '.Profiles[0].Guid = $guid' "$merged_profile" \
      > "$tmpdir/prepared-iterm-profile.json"
    stage_file "$tmpdir/prepared-iterm-profile.json" "$ITERM_PROFILE_DST" \
      "iTerm2 Dynamic Profile" iterm
  fi
  stage_file "$ITERM_PROFILE_SRC" "$ITERM_PROFILE_BASE" \
    "iTerm2 profile merge baseline"
}

prepare_vscode_extensions() {
  local extensions_file="$SCRIPT_DIR/config/vscode/extensions.txt"
  if [[ ! -f "$extensions_file" ]]; then
    return 0
  fi
  if ! command -v code &>/dev/null; then
    if [[ "$MODE" == "diff" ]]; then
      missing_vscode_extensions+=("<code command not found>")
      return 0
    fi
    print -u2 "Error: code not found while config/vscode/extensions.txt declares required extensions"
    return 1
  fi
  local installed ext
  if ! installed=$(code --list-extensions 2>/dev/null); then
    print -u2 "Error: failed to list installed VSCode extensions during validation"
    return 1
  fi
  while IFS= read -r ext || [[ -n "$ext" ]]; do
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    if ! echo "$installed" | grep -qix "$ext"; then
      missing_vscode_extensions+=("$ext")
    fi
  done < "$extensions_file"

}

prepare_git_config() {
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
      pending_git_keys+=("$key")
      pending_git_values+=("$expected")
    fi
  done
}

prepare_duti() {
  local duti_file="$SCRIPT_DIR/config/duti/defaults.duti"
  if [[ ! -f "$duti_file" ]]; then
    return 0
  fi
  if ! command -v duti &>/dev/null; then
    if [[ "$MODE" == "diff" ]]; then
      duti_unavailable=1
      return 0
    fi
    print -u2 "Error: duti is required while config/duti/defaults.duti declares default applications"
    return 1
  fi
  local bundle ext role current
  while IFS=' ' read -r bundle ext role; do
    [[ -z "$bundle" || "$bundle" == \#* ]] && continue
    # duti -x prints three lines: app name, app path, bundle id
    current=$(duti -x "${ext#.}" 2>/dev/null | tail -1)
    if [[ "$current" != "$bundle" ]]; then
      pending_duti_bundles+=("$bundle")
      pending_duti_extensions+=("$ext")
      pending_duti_roles+=("$role")
    fi
  done < "$duti_file"
}

prepare_macos_defaults() {
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
      pending_defaults_domains+=("$domain")
      pending_defaults_keys+=("$key")
      pending_defaults_types+=("$type")
      pending_defaults_values+=("$expected")
    fi
  done
}

staged_destination_changed() {
  local destination=$1 index
  for (( index = 1; index <= ${#staged_destinations[@]}; index++ )); do
    if [[ "${staged_destinations[$index]}" == "$destination" ]] && \
      ! diff -q "${staged_sources[$index]}" "$destination" &>/dev/null; then
      return 0
    fi
  done
  return 1
}

validate_required_commands() {
  require_command jq "to validate and merge JSON configuration"
  require_command git "to inspect and update global Git configuration"
  require_command defaults "to inspect and update macOS defaults"
  if [[ ! -x "$CONFIG_TOOLS_PYTHON" ]]; then
    print -u2 "Error: $CONFIG_TOOLS_PYTHON not found; run make install-config-tools"
    return 1
  fi
}

prepare_post_sync_hooks() {
  if [[ -e "$SHELDON_LOCK_PENDING" ]] || \
    staged_destination_changed "$HOME/.config/sheldon/plugins.toml"; then
    sheldon_lock_pending=1
  fi
  if staged_destination_changed "$HOME/.zshrc"; then
    zshrc_update_pending=1
  fi
  if [[ "$MODE" == "sync" && $sheldon_lock_pending -eq 1 ]]; then
    require_command sheldon "to update the plugin lock after syncing plugins.toml"
  fi
}

report_prepared_changes() {
  local index source destination label format current expected bundle extension key value
  for (( index = 1; index <= ${#staged_sources[@]}; index++ )); do
    source="${staged_sources[$index]}"
    destination="${staged_destinations[$index]}"
    label="${staged_labels[$index]}"
    format="${staged_formats[$index]}"
    diff -q "$source" "$destination" &>/dev/null && continue
    if [[ "$format" == merged-json ]]; then
      echo ""
      echo "$label.json:"
      if [[ -e "$destination" || -L "$destination" ]]; then
        git diff --no-index "$destination" "$source" || true
      else
        git diff --no-index /dev/null "$source" || true
      fi
    elif [[ "$format" == iterm ]]; then
      echo ""
      echo "iTerm2 Dynamic Profile:"
      if [[ -f "$destination" ]]; then
        current=$(jq -S 'del(.Profiles[].Guid)' "$destination")
        expected=$(jq -S 'del(.Profiles[].Guid)' "$source")
        diff <(echo "$current") <(echo "$expected") | head -50 || true
      else
        echo "  current:  <not installed>"
        echo "  expected: $ITERM_PROFILE_SRC"
      fi
    elif [[ -e "$destination" || -L "$destination" ]]; then
      git diff --no-index "$destination" "$source" || true
    else
      echo "New: $label -> $destination"
    fi
    diffs=$((diffs + 1))
  done

  for source in "${claude_orphan_files[@]}"; do
    echo "Orphan: $source (no config/claude/${source#$HOME/.claude/})"
    diffs=$((diffs + 1))
  done
  for source in "${claude_orphan_dirs[@]}"; do
    echo "Orphan: $source/ (no config/claude/${source#$HOME/.claude/})"
    diffs=$((diffs + 1))
  done
  for source in "${codex_orphans[@]}"; do
    echo "Orphan: $source (no config/codex/skills/${source#$CODEX_SKILLS_DST/})"
    diffs=$((diffs + 1))
  done

  if (( ${#missing_vscode_extensions[@]} > 0 )); then
    echo ""
    if [[ "${missing_vscode_extensions[1]}" == "<code command not found>" ]]; then
      echo "VSCode extensions: code command not found"
    else
      echo "VSCode extensions (missing):"
      for extension in "${missing_vscode_extensions[@]}"; do
        echo "  + $extension"
      done
    fi
    diffs=$((diffs + 1))
  fi
  for (( index = 1; index <= ${#pending_git_keys[@]}; index++ )); do
    key="${pending_git_keys[$index]}"
    value="${pending_git_values[$index]}"
    current=$(git config --global "$key" 2>/dev/null || echo "")
    echo ""
    echo "git config --global $key:"
    echo "  current:  ${current:-<unset>}"
    echo "  expected: $value"
    diffs=$((diffs + 1))
  done
  for (( index = 1; index <= ${#pending_duti_bundles[@]}; index++ )); do
    bundle="${pending_duti_bundles[$index]}"
    extension="${pending_duti_extensions[$index]}"
    current=$(duti -x "${extension#.}" 2>/dev/null | tail -1)
    echo ""
    echo "duti ${extension}:"
    echo "  current:  ${current:-<unset>}"
    echo "  expected: $bundle"
    diffs=$((diffs + 1))
  done
  if [[ $duti_unavailable -eq 1 ]]; then
    echo ""
    echo "Default applications: duti command not found"
    diffs=$((diffs + 1))
  fi
  for (( index = 1; index <= ${#pending_defaults_domains[@]}; index++ )); do
    echo ""
    echo "defaults ${pending_defaults_domains[$index]} ${pending_defaults_keys[$index]}:"
    echo "  current:  $(defaults read "${pending_defaults_domains[$index]}" "${pending_defaults_keys[$index]}" 2>/dev/null || echo '<unset>')"
    echo "  expected: ${pending_defaults_values[$index]}"
    diffs=$((diffs + 1))
  done
  if [[ -e "$SHELDON_LOCK_PENDING" ]]; then
    echo ""
    echo "Sheldon plugin lock update is pending from an incomplete sync."
    diffs=$((diffs + 1))
  fi
}

record_applied() {
  applied_targets+=("$1")
  changes=$((changes + 1))
}

report_apply_failure() {
  local target=$1 applied
  print -u2 "Error: failed to apply $target"
  if (( ${#applied_targets[@]} > 0 )); then
    print -u2 "Applied before failure:"
    for applied in "${applied_targets[@]}"; do
      print -u2 "  - $applied"
    done
  else
    print -u2 "No changes were applied."
  fi
  print -u2 "Resolve the failure and rerun 'make sync-config'; completed targets are idempotent."
  return 1
}

atomic_replace() {
  local source=$1 destination=$2 replacement_dir replacement
  if ! mkdir -p "${destination:h}"; then
    return 1
  fi
  if ! replacement_dir=$(mktemp -d "${destination:h}/.oh-my-mac-sync.XXXXXX"); then
    return 1
  fi
  replacement="$replacement_dir/${destination:t}"
  if [[ -f "$destination" && ! -L "$destination" ]]; then
    if ! cp -p "$destination" "$replacement" || ! cp "$source" "$replacement"; then
      rm -rf "$replacement_dir"
      return 1
    fi
  elif ! cp "$source" "$replacement"; then
    rm -rf "$replacement_dir"
    return 1
  fi
  if ! mv -f "$replacement" "$destination"; then
    rm -rf "$replacement_dir"
    return 1
  fi
  rmdir "$replacement_dir" 2>/dev/null || true
}

apply_prepared_files() {
  local index source destination label format hook_changed=0
  for (( index = 1; index <= ${#staged_sources[@]}; index++ )); do
    source="${staged_sources[$index]}"
    destination="${staged_destinations[$index]}"
    label="${staged_labels[$index]}"
    format="${staged_formats[$index]}"
    [[ "$destination" == "$CODEX_SKILLS_MANIFEST" ]] && continue
    diff -q "$source" "$destination" &>/dev/null && continue
    if [[ "$destination" == "$CODEX_HOOKS" ]] && \
      agent_sentinel_codex_hook_changed "$CODEX_HOOKS" "$source"; then
      hook_changed=1
    fi
    if ! atomic_replace "$source" "$destination"; then
      report_apply_failure "managed file $destination"
      return 1
    fi
    if [[ "$format" == merged-json ]]; then
      echo "Merged $label into $destination"
    elif [[ "$format" == iterm ]]; then
      echo "Synced iTerm2 Dynamic Profile."
    else
      echo "Synced: $destination"
    fi
    record_applied "managed file $destination"
    if [[ "$destination" == "$CODEX_HOOKS" && $hook_changed -eq 1 ]]; then
      print_codex_hook_trust_instructions applied
    fi
  done
}

apply_codex_skills_ownership() {
  diff -q "$CODEX_SKILLS_APPLY_MANIFEST" "$CODEX_SKILLS_MANIFEST" &>/dev/null && return 0
  if ! atomic_replace "$CODEX_SKILLS_APPLY_MANIFEST" "$CODEX_SKILLS_MANIFEST"; then
    report_apply_failure "Codex skill ownership journal $CODEX_SKILLS_MANIFEST"
    return 1
  fi
  echo "Recorded pending Codex skill ownership: $CODEX_SKILLS_MANIFEST"
  record_applied "Codex skill ownership journal $CODEX_SKILLS_MANIFEST"
}

apply_codex_skills_manifest() {
  local index source
  for (( index = 1; index <= ${#staged_destinations[@]}; index++ )); do
    [[ "${staged_destinations[$index]}" == "$CODEX_SKILLS_MANIFEST" ]] || continue
    source="${staged_sources[$index]}"
    diff -q "$source" "$CODEX_SKILLS_MANIFEST" &>/dev/null && return 0
    if ! atomic_replace "$source" "$CODEX_SKILLS_MANIFEST"; then
      report_apply_failure "managed file $CODEX_SKILLS_MANIFEST"
      return 1
    fi
    echo "Synced: $CODEX_SKILLS_MANIFEST"
    record_applied "managed file $CODEX_SKILLS_MANIFEST"
    return 0
  done
}

apply_orphan_deletions() {
  local orphan skill_name orphan_dir
  local -A affected_skills
  for orphan in "${claude_orphan_files[@]}"; do
    if ! rm -f "$orphan"; then
      report_apply_failure "Claude orphan $orphan"
      return 1
    fi
    echo "Removed: $orphan"
    record_applied "Claude orphan $orphan"
  done
  for orphan in "${claude_orphan_dirs[@]}"; do
    if ! rm -rf "$orphan"; then
      report_apply_failure "Claude orphan $orphan/"
      return 1
    fi
    echo "Removed: $orphan/"
    record_applied "Claude orphan $orphan/"
  done
  for orphan in "${codex_orphans[@]}"; do
    if [[ -e "$orphan" || -L "$orphan" ]]; then
      if ! rm -f "$orphan"; then
        report_apply_failure "managed Codex skill orphan $orphan"
        return 1
      fi
      echo "Removed: $orphan"
      record_applied "managed Codex skill orphan $orphan"
    fi
  done
  for skill_name in "${codex_affected_skills[@]}"; do
    affected_skills[$skill_name]=1
  done
  for skill_name in "${(@k)affected_skills}"; do
    for orphan_dir in "$CODEX_SKILLS_DST/$skill_name"/**/*(/NOn); do
      rmdir "$orphan_dir" 2>/dev/null || true
    done
    rmdir "$CODEX_SKILLS_DST/$skill_name" 2>/dev/null || true
  done
}

apply_external_state() {
  local index extension key value bundle role domain type
  for extension in "${missing_vscode_extensions[@]}"; do
    echo "Installing VSCode extension: $extension"
    if ! code --install-extension "$extension"; then
      report_apply_failure "VSCode extension $extension"
      return 1
    fi
    record_applied "VSCode extension $extension"
  done
  for (( index = 1; index <= ${#pending_git_keys[@]}; index++ )); do
    key="${pending_git_keys[$index]}"
    value="${pending_git_values[$index]}"
    if ! git config --global "$key" "$value"; then
      report_apply_failure "global Git configuration $key"
      return 1
    fi
    echo "Set git config: $key = $value"
    record_applied "global Git configuration $key"
  done
  for (( index = 1; index <= ${#pending_duti_bundles[@]}; index++ )); do
    bundle="${pending_duti_bundles[$index]}"
    extension="${pending_duti_extensions[$index]}"
    role="${pending_duti_roles[$index]}"
    if ! duti -s "$bundle" "$extension" "$role" 2>/dev/null; then
      report_apply_failure "default application for $extension"
      return 1
    fi
    echo "Set default for ${extension} → $bundle"
    record_applied "default application for $extension"
  done
  for (( index = 1; index <= ${#pending_defaults_domains[@]}; index++ )); do
    domain="${pending_defaults_domains[$index]}"
    key="${pending_defaults_keys[$index]}"
    type="${pending_defaults_types[$index]}"
    value="${pending_defaults_values[$index]}"
    if ! defaults write "$domain" "$key" "-$type" "$value"; then
      report_apply_failure "macOS default $domain $key"
      return 1
    fi
    echo "Set defaults: $domain $key = $value"
    record_applied "macOS default $domain $key"
  done
  if [[ $sheldon_lock_pending -eq 1 ]]; then
    echo "Running: sheldon lock --update"
    if ! sheldon lock --update; then
      report_apply_failure "Sheldon plugin lock"
      return 1
    fi
    if ! rm -f "$SHELDON_LOCK_PENDING"; then
      report_apply_failure "Sheldon retry marker $SHELDON_LOCK_PENDING"
      return 1
    fi
    record_applied "Sheldon plugin lock"
  fi
  if [[ $zshrc_update_pending -eq 1 ]]; then
    echo "Run 'source ~/.zshrc' to apply changes."
  fi
}

validate_required_commands
verify_agent_sentinel
validate_local_inputs
prepare_agent_sentinel_codex_config
prepare_codex_skills
prepare_sync_files
stage_file "$GENERATED_CODEX_HOOKS" "$CODEX_HOOKS" "generated agent-sentinel Codex hooks"
stage_file "$GENERATED_CODEX_AGENT_SENTINEL_RULES" "$CODEX_AGENT_SENTINEL_RULES" \
  "generated agent-sentinel Codex rules"
prepare_instructions "$SCRIPT_DIR/config/claude/instructions.md" "$HOME/.claude/CLAUDE.md"
prepare_instructions "$SCRIPT_DIR/config/codex/instructions.md" "$HOME/.codex/AGENTS.md"
prepare_claude_orphans
stage_file "$CODEX_SKILLS_DESIRED" "$CODEX_SKILLS_MANIFEST" "managed Codex skill files manifest"
prepare_json_config "Claude Code settings" "$CLAUDE_SETTINGS" "$REPO_SETTINGS" "$JQ_SETTINGS_MERGE" '{}'
prepare_json_config "Claude Code keybindings" "$CLAUDE_KEYBINDINGS" "$REPO_KEYBINDINGS" "$JQ_KEYBINDINGS_MERGE" '{"bindings":[]}'
prepare_codex_config
prepare_iterm_profile
if [[ -f "$REPO_VSCODE_SETTINGS" ]]; then
  prepare_json_config "VSCode settings" "$VSCODE_SETTINGS" "$REPO_VSCODE_SETTINGS" '.[0] * .[1]' '{}'
fi
prepare_vscode_extensions
prepare_git_config
prepare_duti
prepare_macos_defaults
prepare_post_sync_hooks

if [[ "$MODE" == "diff" ]]; then
  report_prepared_changes
  if [[ $diffs -eq 0 ]]; then
    echo "No differences found."
  fi
  exit 0
fi

if [[ $sheldon_lock_pending -eq 1 && ! -e "$SHELDON_LOCK_PENDING" ]]; then
  if ! mkdir -p "${SHELDON_LOCK_PENDING:h}" || \
    ! atomic_replace /dev/null "$SHELDON_LOCK_PENDING"; then
    report_apply_failure "Sheldon retry marker $SHELDON_LOCK_PENDING"
    exit 1
  fi
  applied_targets+=("Sheldon retry marker $SHELDON_LOCK_PENDING")
fi
apply_codex_skills_ownership
apply_prepared_files
apply_orphan_deletions
apply_codex_skills_manifest
apply_external_state

if [[ $changes -eq 0 ]]; then
  echo "Already up to date."
fi
