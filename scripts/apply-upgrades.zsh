#!/bin/zsh
set -u
setopt pipefail

repo="${UPGRADE_REPO:-${0:A:h}/..}"
plan="${UPGRADE_PLAN:-${1:-}}"
report="${UPGRADE_REPORT:-${2:-}}"

if [[ -z "$plan" || -z "$report" || ! -f "$plan" ]]; then
  print -u2 "Usage: UPGRADE_PLAN=<path> UPGRADE_REPORT=<path> $0"
  exit 1
fi

if [[ "$plan" == "$report" || "$plan" -ef "$report" ]]; then
  print -u2 "Error: the upgrade plan and report must use different paths"
  exit 1
fi

typeset -A seen
typeset -A planned_decision
typeset -A held_homebrew
typeset -A selected_homebrew_ids
typeset -A held_homebrew_dependencies
typeset -A selected_homebrew_dependencies
typeset -a selected_homebrew

validate_identifier() {
  local kind="$1" identifier="$2"
  case "$kind" in
    homebrew-formula)
      sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "$repo/Brewfile" |
        grep -qxF "$identifier"
      ;;
    homebrew-cask)
      sed -nE 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "$repo/Brewfile" |
        grep -qxF "$identifier"
      ;;
    claude-plugin)
      grep -qxF "$identifier" "$repo/config/claude/plugins.txt"
      ;;
    claude|ntn)
      [[ -s "$repo/config/$kind/version" && "$identifier" == "$kind" ]]
      ;;
    uv-tool)
      grep -qxF "$identifier" "$repo/config/uv/tools.txt"
      ;;
    sheldon-plugin)
      grep -qxF "[plugins.$identifier]" "$repo/config/sheldon/plugins.toml"
      ;;
    *)
      return 1
      ;;
  esac
}

uv_requirement_name() {
  local requirement="$1" name url
  if [[ "$requirement" == *" @ "* ]]; then
    name="${requirement%% @ *}"
    print -r -- "${name%%\[*}"
    return
  fi
  if [[ "$requirement" == git+* ]]; then
    url="${requirement%%.git@*}.git"
    print -r -- "${url:t:r}"
    return
  fi
  name="${requirement%%@*}"
  print -r -- "${name%%\[*}"
}

require_upgrade_plan() {
  local kind="$1" identifier="$2"
  if [[ "${planned_decision[$kind:$identifier]:-}" != "upgrade" ]]; then
    print -u2 "Error: changed pin '$kind:$identifier' requires an upgrade plan row"
    return 1
  fi
}

validate_changed_pins() {
  local kind declaration_path previous diff_status line name plugin
  for kind in claude ntn; do
    declaration_path="config/$kind/version"
    git -C "$repo" diff --quiet HEAD -- "$declaration_path"
    diff_status=$?
    (( diff_status == 0 )) && continue
    (( diff_status == 1 )) || return 1
    require_upgrade_plan "$kind" "$kind" || return 1
  done

  declaration_path="config/uv/tools.txt"
  previous=$(git -C "$repo" show "HEAD:$declaration_path") || return 1
  typeset -A previous_uv current_uv
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    name=$(uv_requirement_name "$line")
    [[ -n "$name" && -z "${previous_uv[$name]:-}" ]] || return 1
    previous_uv[$name]="$line"
  done <<< "$previous"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    name=$(uv_requirement_name "$line")
    [[ -n "$name" && -z "${current_uv[$name]:-}" ]] || return 1
    current_uv[$name]="$line"
  done < "$repo/$declaration_path"
  for name in ${(k)current_uv}; do
    [[ "${current_uv[$name]}" == "${previous_uv[$name]:-}" ]] && continue
    require_upgrade_plan uv-tool "${current_uv[$name]}" || return 1
  done
  for name in ${(k)previous_uv}; do
    if [[ -z "${current_uv[$name]:-}" ]]; then
      print -u2 "Error: removed uv tool pin '$name' has no selectable declaration"
      return 1
    fi
  done

  declaration_path="config/sheldon/plugins.toml"
  previous=$(git -C "$repo" show "HEAD:$declaration_path") || return 1
  typeset -A previous_sheldon current_sheldon
  plugin=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ '^\[plugins\.([^]]+)\]$' ]]; then
      plugin="${match[1]}"
    elif [[ -n "$plugin" && "$line" =~ '^(tag|rev)[[:space:]]*=' ]]; then
      previous_sheldon[$plugin]="$line"
    fi
  done <<< "$previous"
  plugin=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ '^\[plugins\.([^]]+)\]$' ]]; then
      plugin="${match[1]}"
    elif [[ -n "$plugin" && "$line" =~ '^(tag|rev)[[:space:]]*=' ]]; then
      current_sheldon[$plugin]="$line"
    fi
  done < "$repo/$declaration_path"
  for plugin in ${(k)current_sheldon}; do
    [[ "${current_sheldon[$plugin]}" == "${previous_sheldon[$plugin]:-}" ]] && continue
    require_upgrade_plan sheldon-plugin "$plugin" || return 1
  done
  for plugin in ${(k)previous_sheldon}; do
    if [[ -z "${current_sheldon[$plugin]:-}" ]]; then
      print -u2 "Error: removed Sheldon pin '$plugin' has no selectable declaration"
      return 1
    fi
  done
}

line_number=0
while IFS=$'\t' read -r kind identifier decision evidence ||
    [[ -n "$kind$identifier$decision$evidence" ]]; do
  line_number=$(( line_number + 1 ))
  [[ -z "$kind$identifier$decision$evidence" ]] && continue
  if [[ -z "$kind" || -z "$identifier" || -z "$decision" || -z "$evidence" || "$evidence" == *$'\t'* ]]; then
    print -u2 "Error: plan line $line_number must have four non-empty tab-separated fields"
    exit 1
  fi
  case "$decision" in
    upgrade|risk-hold|incompatibility-hold|execution-blocked-hold|unchanged) ;;
    *)
      print -u2 "Error: invalid decision '$decision' on plan line $line_number"
      exit 1
      ;;
  esac
  if ! validate_identifier "$kind" "$identifier"; then
    print -u2 "Error: undeclared upgrade candidate '$kind:$identifier' on plan line $line_number"
    exit 1
  fi
  if [[ "$kind" == "uv-tool" && "$decision" == "upgrade" &&
      "$identifier" == *"git+"* && "$identifier" != *".git@"* ]]; then
    print -u2 "Error: HEAD-tracking uv tool requirements cannot be upgraded by the routine plan: $identifier"
    exit 1
  fi
  key="$kind:$identifier"
  if [[ -n "${seen[$key]:-}" ]]; then
    print -u2 "Error: duplicate upgrade candidate '$key'"
    exit 1
  fi
  seen[$key]=1
  planned_decision[$key]="$decision"
  if [[ "$kind" == homebrew-* ]]; then
    if [[ "$decision" == "upgrade" ]]; then
      selected_homebrew+=("$kind"$'\t'"$identifier")
      selected_homebrew_ids[$identifier]="$kind"
    elif [[ "$decision" == *-hold ]]; then
      held_homebrew[$identifier]="$kind"
    fi
  fi
done < "$plan"

if ! validate_changed_pins; then
  print -u2 "Error: changed dependency pins do not match the selective plan"
  exit 1
fi

if ! : > "$report"; then
  print -u2 "Error: cannot initialize upgrade report $report"
  exit 1
fi

record() {
  if ! print -r -- "$1"$'\t'"$2"$'\t'"$3"$'\t'"$4" >> "$report"; then
    print -u2 "Error: cannot append to upgrade report $report"
    exit 1
  fi
}

probe_state() {
  local kind="$1"
  case "$kind" in
    homebrew-formula|homebrew-cask)
      local formulae casks
      formulae=$(brew list --formula --versions) || return 1
      casks=$(brew list --cask --versions) || return 1
      print -rl -- "$formulae" "$casks" | LC_ALL=C sort
      ;;
    claude-plugin)
      local plugins
      plugins=$(claude plugin list --json) || return 1
      print -r -- "$plugins" | jq -cS .
      ;;
    claude)
      local version
      if ! command -v claude >/dev/null 2>&1; then
        print -r -- "not-installed"
        return 0
      fi
      version=$(claude --version 2>/dev/null | awk '{print $1}') || return 1
      [[ -n "$version" ]] || return 1
      print -r -- "$version"
      ;;
    ntn)
      if command -v fnm >/dev/null 2>&1; then
        local environment
        environment=$(fnm env) || return 1
        eval "$environment" || return 1
      fi
      command -v npm >/dev/null 2>&1 || return 1
      npm ls -g --all --json 2>/dev/null | jq -cS .
      ;;
    uv-tool)
      uv tool list --show-version-specifiers --show-with --show-extras 2>&1
      ;;
  esac
}

apply_candidate() {
  local kind="$1" identifier="$2"
  case "$kind" in
    homebrew-formula)
      HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 \
        HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
        brew upgrade "$identifier"
      ;;
    homebrew-cask)
      HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 \
        HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
        brew upgrade --cask --greedy "$identifier"
      ;;
    claude-plugin)
      claude plugin update "$identifier"
      ;;
    claude|ntn)
      make -s -C "$repo" "install-$kind"
      ;;
    uv-tool)
      make -s -C "$repo" install-uv-tool "UV_TOOL=$identifier"
      ;;
  esac
}

verify_candidate() {
  local kind="$1" state="$2" expected actual
  case "$kind" in
    claude)
      expected=$(<"$repo/config/claude/version")
      [[ "$state" == "$expected" ]]
      ;;
    ntn)
      expected=$(<"$repo/config/ntn/version")
      actual=$(print -r -- "$state" | jq -r '.dependencies.ntn.version // empty')
      [[ "$actual" == "$expected" ]]
      ;;
    *)
      return 0
      ;;
  esac
}

classify_verified_result() {
  local kind="$1" identifier="$2" before="$3" after="$4" outdated
  case "$kind" in
    homebrew-formula)
      outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula "$identifier") || return 1
      [[ -z "$outdated" ]] || return 1
      ;;
    homebrew-cask)
      outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask --greedy "$identifier") || return 1
      [[ -z "$outdated" ]] || return 1
      ;;
    claude-plugin|uv-tool) ;;
    *)
      verify_candidate "$kind" "$after" || return 1
      print upgraded
      return 0
      ;;
  esac

  if [[ "$after" == "$before" ]]; then
    print unchanged
  else
    print upgraded
  fi
}

restore_failed_pin() {
  local kind="$1" identifier="$2" declaration_path previous old_line name temporary
  case "$kind" in
    claude|ntn)
      declaration_path="config/$kind/version"
      previous=$(git -C "$repo" show "HEAD:$declaration_path") || return 1
      print -r -- "$previous" > "$repo/$declaration_path"
      ;;
    uv-tool)
      declaration_path="config/uv/tools.txt"
      name=$(uv_requirement_name "$identifier")
      previous=$(git -C "$repo" show "HEAD:$declaration_path") || return 1
      old_line=""
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$(uv_requirement_name "$line")" == "$name" ]]; then
          old_line="$line"
          break
        fi
      done <<< "$previous"
      temporary=$(mktemp "$repo/config/uv/.tools.txt.XXXXXX") || return 1
      if ! awk -v selected="$identifier" -v restored="$old_line" '
        $0 == selected { if (restored != "") print restored; next }
        { print }
      ' "$repo/$declaration_path" > "$temporary" || ! cp "$temporary" "$repo/$declaration_path"; then
        rm -f "$temporary"
        return 1
      fi
      rm -f "$temporary"
      ;;
    *)
      return 0
      ;;
  esac
}

read_declared_homebrew_dependencies() {
  local kind="$1" identifier="$2" option="--formula" brew_os brew_arch
  [[ "$kind" == "homebrew-cask" ]] && option="--cask"
  case "$(uname -s)" in
    Darwin) brew_os=macos ;;
    Linux) brew_os=linux ;;
    *) return 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) brew_arch=arm ;;
    x86_64) brew_arch=intel ;;
    *) return 1 ;;
  esac
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 \
    brew deps "$option" "--os=$brew_os" "--arch=$brew_arch" "$identifier"
}

homebrew_dependency_is_outdated() {
  local dependency="$1" outdated outdated_status
  outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula "$dependency")
  outdated_status=$?
  [[ -n "$outdated" ]] && return 0
  (( outdated_status == 0 )) && return 1
  return 2
}

if (( ${#selected_homebrew} > 0 )); then
for candidate in "${selected_homebrew[@]}"; do
  IFS=$'\t' read -r kind identifier <<< "$candidate"
  dependencies=$(read_declared_homebrew_dependencies "$kind" "$identifier")
  dependency_status=$?
  if (( dependency_status != 0 )); then
    record "$kind" "$identifier" systemic-failure "Homebrew dependencies could not be read"
    print -u2 "Error: cannot isolate Homebrew dependencies for $identifier"
    exit 1
  fi
  selected_homebrew_dependencies[$identifier]="$dependencies"
  for dependency in ${(f)dependencies}; do
    for held in ${(k)held_homebrew}; do
      if [[ "${held_homebrew[$held]}" == "homebrew-formula" &&
          ( "$dependency" == "$held" || "${dependency:t}" == "${held:t}" ) ]]; then
        if homebrew_dependency_is_outdated "$dependency"; then
          record "$kind" "$identifier" systemic-failure "selected upgrade requires outdated held Homebrew dependency $held"
          print -u2 "Error: $identifier cannot be upgraded without outdated held dependency $held"
          exit 1
        elif (( $? == 2 )); then
          record "$kind" "$identifier" systemic-failure "held Homebrew dependency state could not be read"
          print -u2 "Error: cannot determine whether held dependency $held would be updated"
          exit 1
        fi
      fi
    done
  done
done

for held in ${(k)held_homebrew}; do
  kind="${held_homebrew[$held]}"
  dependencies=$(read_declared_homebrew_dependencies "$kind" "$held")
  dependency_status=$?
  if (( dependency_status != 0 )); then
    record "$kind" "$held" systemic-failure "held Homebrew dependencies could not be read"
    print -u2 "Error: cannot isolate Homebrew dependencies for held candidate $held"
    exit 1
  fi
  held_homebrew_dependencies[$held]="$dependencies"
  for dependency in ${(f)dependencies}; do
    for selected in ${(k)selected_homebrew_ids}; do
      if [[ "${selected_homebrew_ids[$selected]}" == "homebrew-formula" &&
          ( "$dependency" == "$selected" || "${dependency:t}" == "${selected:t}" ) ]]; then
        if homebrew_dependency_is_outdated "$selected"; then
          record "$kind" "$held" systemic-failure "held candidate depends on selected Homebrew upgrade $selected"
          print -u2 "Error: held candidate $held shares selected dependency $selected"
          exit 1
        elif (( $? == 2 )); then
          record "$kind" "$held" systemic-failure "selected Homebrew dependency state could not be read"
          print -u2 "Error: cannot determine whether selected dependency $selected would be updated"
          exit 1
        fi
      fi
    done
  done
done

for selected in ${(k)selected_homebrew_dependencies}; do
  for held in ${(k)held_homebrew_dependencies}; do
    for dependency in ${(f)selected_homebrew_dependencies[$selected]}; do
      for held_dependency in ${(f)held_homebrew_dependencies[$held]}; do
        if [[ "$dependency" != "$held_dependency" && "${dependency:t}" != "${held_dependency:t}" ]]; then
          continue
        fi
        if homebrew_dependency_is_outdated "$dependency"; then
          record homebrew "$selected" systemic-failure "selected and held candidates share outdated Homebrew dependency $dependency"
          print -u2 "Error: selected candidate $selected and held candidate $held share outdated dependency $dependency"
          exit 1
        elif (( $? == 2 )); then
          record homebrew "$selected" systemic-failure "shared Homebrew dependency state could not be read"
          print -u2 "Error: cannot determine whether shared dependency $dependency would be updated"
          exit 1
        fi
      done
    done
  done
done

if ! make -s -C "$repo" trust-taps; then
  record workflow trust-taps systemic-failure "Homebrew tap trust could not be established"
  print -u2 "Error: selective Homebrew application cannot start without trusted taps"
  exit 1
fi
fi

while IFS=$'\t' read -r kind identifier decision evidence ||
    [[ -n "$kind$identifier$decision$evidence" ]]; do
  [[ -z "$kind$identifier$decision$evidence" ]] && continue
  if [[ "$decision" != "upgrade" ]]; then
    record "$kind" "$identifier" "$decision" "$evidence"
    continue
  fi
  if [[ "$kind" == "sheldon-plugin" ]]; then
    record "$kind" "$identifier" declaration-updated "repository reference validated; local checkout deferred until config sync; $evidence"
    continue
  fi

  before=$(probe_state "$kind")
  probe_status=$?
  if (( probe_status != 0 )); then
    record "$kind" "$identifier" systemic-failure "pre-application state could not be read"
    print -u2 "Error: cannot isolate $kind:$identifier without a readable initial state"
    exit 1
  fi

  print -r -- "Applying upgrade: $kind:$identifier"
  if apply_candidate "$kind" "$identifier"; then
    after=$(probe_state "$kind")
    probe_status=$?
    if (( probe_status != 0 )); then
      record "$kind" "$identifier" systemic-failure "post-application verification could not be read"
      print -u2 "Error: cannot verify $kind:$identifier after application"
      exit 1
    fi
    verified_result=$(classify_verified_result "$kind" "$identifier" "$before" "$after")
    verification_status=$?
    if (( verification_status != 0 )); then
      record "$kind" "$identifier" systemic-failure "installed state did not verify the selected candidate"
      print -u2 "Error: $kind:$identifier did not reach a verified state"
      exit 1
    fi
    record "$kind" "$identifier" "$verified_result" "verified after selective application; $evidence"
    continue
  fi

  after=$(probe_state "$kind")
  probe_status=$?
  if (( probe_status == 0 )) && [[ "$after" == "$before" ]]; then
    if ! restore_failed_pin "$kind" "$identifier"; then
      record "$kind" "$identifier" systemic-failure "application failed and the selected pin could not be restored"
      print -u2 "Error: failed to restore the held pin for $kind:$identifier"
      exit 1
    fi
    record "$kind" "$identifier" execution-blocked-hold "application failed with unchanged package-manager state and any selected pin was restored; $evidence"
    print -u2 "Holding $kind:$identifier after an isolated application failure"
    continue
  fi

  record "$kind" "$identifier" systemic-failure "application failed and package-manager state is uncertain"
  print -u2 "Error: application failure left unisolatable state for $kind:$identifier"
  exit 1
done < "$plan"
