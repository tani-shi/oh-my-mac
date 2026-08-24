#!/bin/zsh
set -u

SOURCE_REPO="${0:A:h}/.."
[[ -f "$SOURCE_REPO/scripts/apply-upgrades.zsh" ]] || {
  print -u2 "missing $SOURCE_REPO/scripts/apply-upgrades.zsh"
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
git_bin_dir="${commands[git]:h}"

REPO="$tmp/repo"
cp -R "$SOURCE_REPO" "$REPO"
rm -rf "$REPO/.git"
git init -q "$REPO"
git -C "$REPO" add .
git -C "$REPO" -c user.name=test -c user.email=test@example.com commit -qm initial
SRC="$REPO/scripts/apply-upgrades.zsh"

export HOME="$tmp/home"
export STUB_STATE="$tmp/state"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM="$tmp/gitconfig-system"
unset GIT_TEMPLATE_DIR
mkdir -p "$HOME" "$tmp/bin" "$STUB_STATE"
: > "$GIT_CONFIG_GLOBAL"
: > "$GIT_CONFIG_SYSTEM"
export PATH="$tmp/bin:$git_bin_dir:/usr/bin:/bin"

stub() {
  local stub_path="$tmp/bin/$1"
  shift
  print -r -- "$@" > "$stub_path"
  chmod +x "$stub_path"
}

stub brew '#!/bin/zsh
case "$1" in
  trust)
    [[ "${2:-}" == "--json" ]] && print "[]"
    ;;
  list)
    [[ "$2" == "--formula" && -f "$STUB_STATE/brew-list-formula-fails" ]] && exit 2
    [[ "$2" == "--cask" && -f "$STUB_STATE/brew-list-cask-fails" ]] && exit 2
    [[ "$2" == "--formula" ]] && cat "$STUB_STATE/brew-formulae"
    [[ "$2" == "--cask" ]] && cat "$STUB_STATE/brew-casks"
    ;;
  deps)
    identifier="${@[-1]}"
    [[ -f "$STUB_STATE/brew-deps-fails-$identifier" ]] && exit 2
    print -r -- "$*" >> "$STUB_STATE/brew-deps-calls"
    if [[ "$*" == *"--os="* && "$*" == *"--arch="* ]]; then
      [[ -f "$STUB_STATE/brew-declared-deps-$identifier" ]] && cat "$STUB_STATE/brew-declared-deps-$identifier"
      [[ -f "$STUB_STATE/brew-deps-$identifier" ]] && cat "$STUB_STATE/brew-deps-$identifier"
    elif [[ -f "$STUB_STATE/brew-runtime-deps-$identifier" ]]; then
      cat "$STUB_STATE/brew-runtime-deps-$identifier"
    fi
    ;;
  outdated)
    identifier="${@[-1]}"
    print -r -- "$*" >> "$STUB_STATE/brew-outdated-calls"
    [[ -f "$STUB_STATE/brew-outdated-fails-$identifier" ]] && exit 2
    if [[ -f "$STUB_STATE/brew-outdated-$identifier" ]]; then
      print -r -- "$identifier"
      exit 1
    fi
    ;;
  upgrade)
    identifier="${@[-1]}"
    print -r -- "$*" >> "$STUB_STATE/brew-calls"
    print -r -- "${HOMEBREW_NO_ASK:-}:${HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:-}:${HOMEBREW_NO_INSTALL_CLEANUP:-}" >> "$STUB_STATE/brew-isolation"
    if [[ -f "$STUB_STATE/brew-fail-$identifier" ]]; then
      if [[ -f "$STUB_STATE/brew-mutate-$identifier" ]]; then
        print "dependency 2.0.0" >> "$STUB_STATE/brew-formulae"
      fi
      exit 2
    fi
    ;;
esac
exit 0'

stub uname '#!/bin/zsh
case "${1:-}" in
  -s) print Darwin ;;
  -m) print arm64 ;;
  *) print Darwin ;;
esac'

stub claude '#!/bin/zsh
case "$1 $2" in
  "plugin list") cat "$STUB_STATE/claude-plugins" ;;
  "plugin update")
    print -r -- "$3" >> "$STUB_STATE/claude-plugin-calls"
    [[ -f "$STUB_STATE/claude-plugin-fail-$3" ]] && exit 2
    ;;
  *)
    if [[ "$1" == "--version" ]]; then
      [[ -f "$STUB_STATE/claude-version-fails" ]] && exit 2
      print "$(<$STUB_STATE/claude-version) (Claude Code)"
    elif [[ "$1" == "install" ]]; then
      print -r -- "$2" >> "$STUB_STATE/claude-installs"
      print -r -- "$2" > "$STUB_STATE/claude-version"
    fi
    ;;
esac
exit 0'

stub npm '#!/bin/zsh
[[ "${FNM_UPGRADE_TEST:-}" == "1" ]] || exit 9
if [[ "$1" == "ls" ]]; then
  ntn_version=$(<$STUB_STATE/ntn-version)
  codex_version=$(<$STUB_STATE/codex-version)
  transitive_version=$(<$STUB_STATE/npm-transitive-version)
  print -r -- "$*" >> "$STUB_STATE/npm-list-calls"
  print -r -- "{\"dependencies\":{\"ntn\":{\"version\":\"$ntn_version\",\"dependencies\":{\"shared\":{\"version\":\"$transitive_version\"}}},\"@openai/codex\":{\"version\":\"$codex_version\",\"dependencies\":{\"shared\":{\"version\":\"$transitive_version\"}}}}}"
elif [[ "$1 $2" == "install -g" ]]; then
  print -r -- "$3" >> "$STUB_STATE/npm-installs"
  package=ntn
  [[ "$3" == @openai/codex@* ]] && package=codex
  if [[ -f "$STUB_STATE/npm-fail-$package" ]]; then
    [[ -f "$STUB_STATE/npm-mutate-transitive-$package" ]] && print 2.0.0 > "$STUB_STATE/npm-transitive-version"
    exit 2
  fi
  if [[ ! -f "$STUB_STATE/npm-preserve-state" ]]; then
    case "$3" in
      ntn@*) print -r -- "${3#ntn@}" > "$STUB_STATE/ntn-version" ;;
      @openai/codex@*) print -r -- "${3#@openai/codex@}" > "$STUB_STATE/codex-version" ;;
    esac
  fi
fi
exit 0'

stub ntn '#!/bin/zsh
print -r -- "ntn $(<$STUB_STATE/ntn-version)"'

stub fnm '#!/bin/zsh
if [[ "$1" == "env" ]]; then
  print "export FNM_UPGRADE_TEST=1"
fi
exit 0'

stub uv '#!/bin/zsh
if [[ "$1 $2" == "tool list" ]]; then
  cat "$STUB_STATE/uv-tools"
elif [[ "$1 $2" == "tool install" ]]; then
  print -r -- "${*:3}" >> "$STUB_STATE/uv-installs"
fi
exit 0'

pass=0 fail=0 case_n=0 current="" plan="" report=""

check_equals() {
  if [[ "$2" == "$3" ]]; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    print -u2 "FAIL $current: $1"
    print -u2 "  expected: $3"
    print -u2 "  actual:   $2"
  fi
}

check_contains() {
  if [[ "$2" == *"$3"* ]]; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    print -u2 "FAIL $current: $1"
    print -u2 "  expected to contain: $3"
    print -u2 "  actual:              $2"
  fi
}

check_lacks() {
  if [[ "$2" != *"$3"* ]]; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    print -u2 "FAIL $current: $1"
    print -u2 "  expected to lack: $3"
    print -u2 "  actual:           $2"
  fi
}

run() {
  current="$1"
  case_n=$(( case_n + 1 ))
  rm -rf "$STUB_STATE"
  mkdir -p "$STUB_STATE"
  print -r -- $'ripgrep 14.1.1\nfzf 0.60.3' > "$STUB_STATE/brew-formulae"
  print -r -- 'chatgpt 1.0.0' > "$STUB_STATE/brew-casks"
  print -r -- '[{"scope":"user","id":"code-review@claude-plugins-official","version":"1"},{"scope":"user","id":"context7@claude-plugins-official","version":"1"}]' > "$STUB_STATE/claude-plugins"
  print 0.0.0 > "$STUB_STATE/claude-version"
  print 0.0.0 > "$STUB_STATE/ntn-version"
  print 0.0.0 > "$STUB_STATE/codex-version"
  print 1.0.0 > "$STUB_STATE/npm-transitive-version"
  : > "$STUB_STATE/uv-tools"
  plan="$tmp/plan$case_n.tsv"
  report="$tmp/report$case_n.tsv"
  "$2"
}

apply_plan() {
  UPGRADE_PLAN="$plan" UPGRADE_REPORT="$report" "$SRC" 2>&1
}

init_pin_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/config/claude" "$fixture/config/ntn" "$fixture/config/codex" \
    "$fixture/config/uv" "$fixture/config/sheldon"
  print 0.0.0 > "$fixture/config/claude/version"
  print 0.0.0 > "$fixture/config/ntn/version"
  print 0.0.0 > "$fixture/config/codex/version"
  print 'ruff@1.0.0' > "$fixture/config/uv/tools.txt"
  print -r -- $'[plugins]\n' > "$fixture/config/sheldon/plugins.toml"
  git init -q "$fixture"
  git -C "$fixture" add config
  git -C "$fixture" -c user.name=test -c user.email=test@example.com commit -qm initial
}

t_risky_chatgpt_is_held_independently() {
  print -r -- $'homebrew-cask\tchatgpt\trisk-hold\tcurrent GUI regression\nhomebrew-formula\tripgrep\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "safe Homebrew candidate succeeds" "$result_status" "0"
  check_contains "the safe formula is upgraded" "$(<$STUB_STATE/brew-calls)" "upgrade ripgrep"
  check_equals "Homebrew prompts and dependency side effects are disabled" "$(<$STUB_STATE/brew-isolation)" "1:1:1"
  check_lacks "the risky ChatGPT cask is not touched" "$(<$STUB_STATE/brew-calls)" "chatgpt"
  check_contains "the ChatGPT hold is reported" "$(<$report)" $'homebrew-cask\tchatgpt\trisk-hold'
}

t_risky_claude_plugin_is_held_independently() {
  print -r -- $'claude-plugin\tcode-review@claude-plugins-official\trisk-hold\tcurrent regression\nclaude-plugin\tcontext7@claude-plugins-official\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "safe Claude plugin succeeds" "$result_status" "0"
  check_equals "only the safe plugin is updated" "$(<$STUB_STATE/claude-plugin-calls)" "context7@claude-plugins-official"
  check_contains "the risky plugin hold is reported" "$(<$report)" $'claude-plugin\tcode-review@claude-plugins-official\trisk-hold'
  check_contains "the unchanged plugin state is not called upgraded" "$(<$report)" $'context7@claude-plugins-official\tunchanged\tverified'
}

t_held_pin_does_not_block_other_pins() {
  print -r -- $'claude\tclaude\tincompatibility-hold\thook contract changed\nntn\tntn\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "safe pin succeeds" "$result_status" "0"
  check_contains "the independent pin is installed" "$(<$STUB_STATE/npm-installs)" "ntn@"
  check_contains "npm state includes transitive dependencies" "$(<$STUB_STATE/npm-list-calls)" "ls -g --all --json"
  check_equals "the held Claude pin is not installed" "$([[ ! -e $STUB_STATE/claude-installs ]] && print yes || print no)" "yes"
  check_contains "the incompatibility is reported" "$(<$report)" $'claude\tclaude\tincompatibility-hold'
}

t_blocked_assessment_is_localized() {
  print -r -- $'homebrew-cask\tchatgpt\texecution-blocked-hold\tCodex safeguard blocked assessment\nhomebrew-formula\tfzf\tupgrade\tsafe evidence remained available' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "blocked evidence path does not fail the plan" "$result_status" "0"
  check_contains "the independent candidate still runs" "$(<$STUB_STATE/brew-calls)" "upgrade fzf"
  check_contains "the blocked assessment is reported separately" "$(<$report)" $'chatgpt\texecution-blocked-hold'
}

t_isolated_application_failure_continues() {
  : > "$STUB_STATE/brew-fail-ripgrep"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe before application\nhomebrew-formula\tfzf\tupgrade\tsafe release' > "$plan"
  local output result_status calls
  output=$(apply_plan)
  result_status=$?
  calls=$(<$STUB_STATE/brew-calls)

  check_equals "unchanged state localizes the failure" "$result_status" "0"
  check_contains "the failed formula is held" "$(<$report)" $'ripgrep\texecution-blocked-hold'
  check_contains "a later independent formula proceeds" "$calls" "upgrade fzf"
}

t_uncertain_application_failure_stops() {
  : > "$STUB_STATE/brew-fail-ripgrep"
  : > "$STUB_STATE/brew-mutate-ripgrep"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe before application\nhomebrew-formula\tfzf\tupgrade\tsafe release' > "$plan"
  local output result_status calls
  output=$(apply_plan)
  result_status=$?
  calls=$(<$STUB_STATE/brew-calls)

  check_equals "changed package state fails the plan" "$result_status" "1"
  check_contains "the systemic failure is reported" "$(<$report)" $'ripgrep\tsystemic-failure'
  check_lacks "later candidates do not run after systemic failure" "$calls" "upgrade fzf"
}

t_transitive_npm_mutation_stops() {
  : > "$STUB_STATE/npm-fail-codex"
  : > "$STUB_STATE/npm-mutate-transitive-codex"
  print -r -- $'codex\tcodex\tupgrade\tsafe before application\nntn\tntn\tupgrade\tsafe release' > "$plan"
  local output result_status calls
  output=$(apply_plan)
  result_status=$?
  calls=$(<$STUB_STATE/npm-installs)

  check_equals "a transitive npm mutation fails the plan" "$result_status" "1"
  check_contains "the uncertain npm state is reported" "$(<$report)" $'codex\tsystemic-failure'
  check_lacks "later npm candidates do not run" "$calls" "ntn@"
}

t_held_shared_dependency_stops_before_application() {
  print fzf > "$STUB_STATE/brew-deps-ripgrep"
  : > "$STUB_STATE/brew-outdated-fzf"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release\nhomebrew-formula\tfzf\trisk-hold\tshared dependency regression' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "held dependency fails the plan" "$result_status" "1"
  check_contains "the dependency conflict is reported" "$(<$report)" "requires outdated held Homebrew dependency fzf"
  check_equals "dependency validation precedes application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_held_dependent_stops_before_application() {
  print sqlite > "$STUB_STATE/brew-deps-awscli"
  : > "$STUB_STATE/brew-outdated-sqlite"
  print -r -- $'homebrew-formula\tsqlite\tupgrade\tsafe release\nhomebrew-formula\tawscli\trisk-hold\tdependent regression' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a held dependent fails the plan" "$result_status" "1"
  check_contains "the reverse dependency conflict is reported" "$(<$report)" "held candidate depends on selected Homebrew upgrade sqlite"
  check_equals "reverse dependency validation precedes application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_outdated_shared_dependency_stops_before_application() {
  print sqlite > "$STUB_STATE/brew-deps-ripgrep"
  print sqlite > "$STUB_STATE/brew-deps-awscli"
  : > "$STUB_STATE/brew-outdated-sqlite"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release\nhomebrew-formula\tawscli\trisk-hold\tshared dependency regression' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "an outdated shared dependency fails the plan" "$result_status" "1"
  check_contains "the shared dependency conflict is reported" "$(<$report)" "share outdated Homebrew dependency sqlite"
  check_equals "shared dependency validation precedes application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_new_declared_shared_dependency_stops_before_application() {
  : > "$STUB_STATE/brew-runtime-deps-ripgrep"
  print sqlite > "$STUB_STATE/brew-declared-deps-ripgrep"
  print sqlite > "$STUB_STATE/brew-declared-deps-awscli"
  : > "$STUB_STATE/brew-outdated-sqlite"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release\nhomebrew-formula\tawscli\trisk-hold\tshared dependency regression' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a new declared shared dependency fails the plan" "$result_status" "1"
  check_contains "the selected formula uses the declared graph" "$(<$STUB_STATE/brew-deps-calls)" "deps --formula --os=macos --arch=arm ripgrep"
  check_contains "the declared dependency conflict is reported" "$(<$report)" "share outdated Homebrew dependency sqlite"
  check_equals "the new dependency validation precedes application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_current_shared_dependency_allows_application() {
  print sqlite > "$STUB_STATE/brew-deps-ripgrep"
  print sqlite > "$STUB_STATE/brew-deps-awscli"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release\nhomebrew-formula\tawscli\trisk-hold\tshared current dependency' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a current shared dependency preserves isolation" "$result_status" "0"
  check_contains "the selected candidate is applied" "$(<$STUB_STATE/brew-calls)" "upgrade ripgrep"
  check_lacks "the held candidate remains untouched" "$(<$STUB_STATE/brew-calls)" "awscli"
}

t_unreadable_shared_dependency_state_stops() {
  print sqlite > "$STUB_STATE/brew-deps-ripgrep"
  print sqlite > "$STUB_STATE/brew-deps-awscli"
  : > "$STUB_STATE/brew-outdated-fails-sqlite"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release\nhomebrew-formula\tawscli\trisk-hold\tshared dependency regression' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "an unreadable shared dependency fails the plan" "$result_status" "1"
  check_contains "the unreadable dependency state is reported" "$(<$report)" "shared Homebrew dependency state could not be read"
  check_equals "an unreadable dependency prevents application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_homebrew_probe_failure_stops_before_application() {
  : > "$STUB_STATE/brew-list-formula-fails"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a partial Homebrew probe fails the plan" "$result_status" "1"
  check_contains "the unreadable initial state is reported" "$(<$report)" "pre-application state could not be read"
  check_equals "a failed probe prevents application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_claude_probe_failure_stops_before_application() {
  : > "$STUB_STATE/claude-version-fails"
  print -r -- $'claude\tclaude\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a broken Claude executable fails the plan" "$result_status" "1"
  check_contains "the executable failure is reported as unreadable state" "$(<$report)" "pre-application state could not be read"
  check_equals "a failed Claude probe prevents installation" "$([[ ! -e $STUB_STATE/claude-installs ]] && print yes || print no)" "yes"
}

t_unverified_pin_application_stops() {
  : > "$STUB_STATE/npm-preserve-state"
  print -r -- $'codex\tcodex\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a mismatched installed pin fails the plan" "$result_status" "1"
  check_contains "the verification failure is reported" "$(<$report)" "installed state did not verify"
}

t_failed_fixed_pin_restores_the_declaration() {
  local fixture="$tmp/pin-fixture" output result_status
  init_pin_fixture "$fixture"
  print 1.0.0 > "$fixture/config/codex/version"
  stub make '#!/bin/zsh
exit 2'
  print -r -- $'codex\tcodex\tupgrade\tsafe before application' > "$plan"

  output=$(UPGRADE_REPO="$fixture" apply_plan)
  result_status=$?
  rm "$tmp/bin/make"

  check_equals "the isolated install failure remains a hold" "$result_status" "0"
  check_equals "the selected pin is restored" "$(<$fixture/config/codex/version)" "0.0.0"
  check_contains "the restored hold is reported" "$(<$report)" "any selected pin was restored"
}

t_changed_pin_requires_an_upgrade_plan_row() {
  local fixture="$tmp/complete-plan-fixture" output result_status
  init_pin_fixture "$fixture"
  print 1.0.0 > "$fixture/config/codex/version"
  print -r -- $'codex\tcodex\trisk-hold\tunsafe release' > "$plan"

  output=$(UPGRADE_REPO="$fixture" apply_plan)
  result_status=$?

  check_equals "a changed pin cannot be held after mutation" "$result_status" "1"
  check_contains "the missing upgrade selection is explicit" "$output" "changed pin 'codex:codex' requires an upgrade plan row"
  check_equals "plan completeness is checked before application" "$([[ ! -e $STUB_STATE/npm-installs ]] && print yes || print no)" "yes"
}

t_changed_uv_pin_requires_an_upgrade_plan_row() {
  local fixture="$tmp/complete-uv-plan-fixture" output result_status
  init_pin_fixture "$fixture"
  print 'ruff@2.0.0' > "$fixture/config/uv/tools.txt"
  print -r -- $'uv-tool\truff@2.0.0\trisk-hold\tunsafe release' > "$plan"

  output=$(UPGRADE_REPO="$fixture" apply_plan)
  result_status=$?

  check_equals "a changed uv pin cannot be held after mutation" "$result_status" "1"
  check_contains "the changed uv requirement is named" "$output" "changed pin 'uv-tool:ruff@2.0.0' requires an upgrade plan row"
  check_equals "uv completeness is checked before application" "$([[ ! -e $STUB_STATE/uv-installs ]] && print yes || print no)" "yes"
}

t_changed_sheldon_pin_requires_an_upgrade_plan_row() {
  local fixture="$tmp/complete-sheldon-plan-fixture" output result_status
  init_pin_fixture "$fixture"
  print -r -- $'[plugins]\n\n[plugins.example]\ngithub = "example/example"\ntag = "1.0.0"' > "$fixture/config/sheldon/plugins.toml"
  git -C "$fixture" add config/sheldon/plugins.toml
  git -C "$fixture" -c user.name=test -c user.email=test@example.com commit -qm 'add plugin pin'
  print -r -- $'[plugins]\n\n[plugins.example]\ngithub = "example/example"\ntag = "2.0.0"' > "$fixture/config/sheldon/plugins.toml"
  print -r -- $'sheldon-plugin\texample\tincompatibility-hold\tunsafe release' > "$plan"

  output=$(UPGRADE_REPO="$fixture" apply_plan)
  result_status=$?

  check_equals "a changed Sheldon pin cannot be held after mutation" "$result_status" "1"
  check_contains "the changed Sheldon plugin is named" "$output" "changed pin 'sheldon-plugin:example' requires an upgrade plan row"
  check_equals "Sheldon completeness is checked before the report" "$([[ ! -e $report ]] && print yes || print no)" "yes"
}

t_failed_uv_tool_restores_only_its_declaration() {
  local fixture="$tmp/uv-pin-fixture" output result_status
  init_pin_fixture "$fixture"
  print -r -- $'ruff@2.0.0\nuvicorn@1.0.0' > "$fixture/config/uv/tools.txt"
  git -C "$fixture" add config/uv/tools.txt
  git -C "$fixture" -c user.name=test -c user.email=test@example.com commit -qm 'add independent tool'
  print -r -- $'ruff@3.0.0\nuvicorn@2.0.0' > "$fixture/config/uv/tools.txt"
  print -r -- $'uv-tool\truff@3.0.0\tupgrade\tsafe release\nuv-tool\tuvicorn@2.0.0\tupgrade\tsafe release' > "$plan"

  output=$(UPGRADE_REPO="$fixture" apply_plan)
  result_status=$?

  check_equals "isolated uv application failures remain holds" "$result_status" "0"
  check_equals "each failed uv declaration returns to HEAD" "$(<$fixture/config/uv/tools.txt)" $'ruff@2.0.0\nuvicorn@1.0.0'
  check_contains "the failed uv candidate is reported as held" "$(<$report)" $'uv-tool\truff@3.0.0\texecution-blocked-hold'
  check_contains "the independent uv candidate is also attempted" "$(<$report)" $'uv-tool\tuvicorn@2.0.0\texecution-blocked-hold'
}

t_successful_noop_is_reported_unchanged() {
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tstale selection' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a verified no-op succeeds" "$result_status" "0"
  check_contains "the no-op result is accurate" "$(<$report)" $'ripgrep\tunchanged\tverified'
}

t_still_outdated_homebrew_result_stops() {
  : > "$STUB_STATE/brew-outdated-ripgrep"
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "an outdated result fails verification" "$result_status" "1"
  check_contains "the failed verification is reported" "$(<$report)" "installed state did not verify"
}

t_cask_verification_includes_auto_updates() {
  print -r -- $'homebrew-cask\tchatgpt\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "the cask application succeeds" "$result_status" "0"
  check_contains "auto-updating casks use greedy application" "$(<$STUB_STATE/brew-calls)" "upgrade --cask --greedy chatgpt"
  check_contains "auto-updating casks use greedy verification" "$(<$STUB_STATE/brew-outdated-calls)" "outdated --cask --greedy chatgpt"
}

t_sheldon_update_is_reported_as_deferred() {
  print -r -- $'sheldon-plugin\tzsh-completions\tupgrade\tsafe tag' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "declaration-only update succeeds" "$result_status" "0"
  check_contains "the deferred result is explicit" "$(<$report)" $'zsh-completions\tdeclaration-updated'
  check_contains "the runtime boundary is reported" "$(<$report)" "local checkout deferred until config sync"
}

t_unwritable_report_stops_before_application() {
  print -r -- $'homebrew-formula\tripgrep\tupgrade\tsafe release' > "$plan"
  report="$tmp/missing-parent/report.tsv"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "an unavailable report fails the plan" "$result_status" "1"
  check_contains "the report failure is identified" "$output" "cannot initialize upgrade report"
  check_equals "report validation precedes application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_report_alias_is_rejected_before_truncation() {
  local output result_status original
  original=$'homebrew-formula\tripgrep\tupgrade\tsafe release'
  print -r -- "$original" > "$plan"
  ln -s "$plan" "$report"

  output=$(apply_plan)
  result_status=$?

  check_equals "a report alias fails validation" "$result_status" "1"
  check_contains "the alias rejection is explicit" "$output" "plan and report must use different paths"
  check_equals "the plan survives alias rejection" "$(<$plan)" "$original"
  check_equals "alias validation precedes application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_safe_changes_remain_mergeable_with_holds() {
  print -r -- $'homebrew-cask\tchatgpt\trisk-hold\tcurrent GUI regression\ncodex\tcodex\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "holds do not fail the apply gate" "$result_status" "0"
  check_contains "the hold remains visible" "$(<$report)" $'chatgpt\trisk-hold'
  check_contains "the safe change is verified" "$(<$report)" $'codex\tupgraded\tverified'
}

t_all_held_homebrew_skips_dependency_checks() {
  : > "$STUB_STATE/brew-deps-fails-chatgpt"
  print -r -- $'homebrew-cask\tchatgpt\trisk-hold	current GUI regression\ncodex\tcodex\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "held-only Homebrew candidates do not block other kinds" "$result_status" "0"
  check_equals "held-only Homebrew dependencies are not queried" "$([[ ! -e $STUB_STATE/brew-deps-calls ]] && print yes || print no)" "yes"
  check_contains "the independent pin is still verified" "$(<$report)" $'codex\tupgraded\tverified'
}

t_undeclared_candidate_is_rejected_before_application() {
  print -r -- $'homebrew-formula\tnot-declared\tupgrade\tunknown candidate\nhomebrew-formula\tripgrep\tupgrade\tsafe release' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "invalid identifiers fail validation" "$result_status" "1"
  check_contains "the undeclared identifier is named" "$output" "not-declared"
  check_equals "validation finishes before any application" "$([[ ! -e $STUB_STATE/brew-calls ]] && print yes || print no)" "yes"
}

t_agent_sentinel_unpinned_upgrade_is_rejected() {
  print -r -- $'uv-tool\tagent-sentinel[claude] @ git+https://github.com/tani-shi/agent-sentinel.git\tupgrade\tnew HEAD' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "agent-sentinel without a commit cannot enter routine upgrade" "$result_status" "1"
  check_contains "the full commit policy rejection is explicit" "$output" "Git uv tool upgrades require a full commit SHA"
  check_equals "rejection precedes uv application" "$([[ ! -e $STUB_STATE/uv-installs ]] && print yes || print no)" "yes"
}

t_claude_sessions_unpinned_upgrade_is_rejected() {
  print -r -- $'uv-tool\tgit+https://github.com/tani-shi/claude-sessions.git\tupgrade\tnew HEAD' > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "claude-sessions without a commit cannot enter routine upgrade" "$result_status" "1"
  check_contains "the second full commit policy rejection is explicit" "$output" "Git uv tool upgrades require a full commit SHA"
  check_equals "the second rejection precedes uv application" "$([[ ! -e $STUB_STATE/uv-installs ]] && print yes || print no)" "yes"
}

t_full_commit_uv_upgrade_is_allowed() {
  local identifier=$(grep 'claude-sessions' "$REPO/config/uv/tools.txt")
  print -r -- "uv-tool"$'\t'"$identifier"$'\t'"upgrade"$'\t'"reviewed commit" > "$plan"
  local output result_status
  output=$(apply_plan)
  result_status=$?

  check_equals "a full commit uv tool passes validation" "$result_status" "0"
  check_contains "the exact pinned requirement is installed" \
    "$(<$STUB_STATE/uv-installs)" "$identifier"
  check_contains "the full commit application is attempted" "$output" \
    "Applying upgrade: uv-tool:$identifier"
  check_contains "the full commit application is verified" "$(<$report)" \
    "$identifier"$'\t'"unchanged"$'\t'"verified"
}

run "risky ChatGPT cask is held independently"        t_risky_chatgpt_is_held_independently
run "risky Claude plugin is held independently"       t_risky_claude_plugin_is_held_independently
run "held pin does not block other pins"              t_held_pin_does_not_block_other_pins
run "blocked assessment is localized"                 t_blocked_assessment_is_localized
run "isolated application failure continues"          t_isolated_application_failure_continues
run "uncertain application failure stops"             t_uncertain_application_failure_stops
run "transitive npm mutation stops"                    t_transitive_npm_mutation_stops
run "held shared dependency stops before application" t_held_shared_dependency_stops_before_application
run "held dependent stops before application"         t_held_dependent_stops_before_application
run "outdated shared dependency stops early"          t_outdated_shared_dependency_stops_before_application
run "new declared shared dependency stops early"      t_new_declared_shared_dependency_stops_before_application
run "current shared dependency remains isolated"      t_current_shared_dependency_allows_application
run "unreadable shared dependency stops"              t_unreadable_shared_dependency_state_stops
run "Homebrew probe failure stops before application" t_homebrew_probe_failure_stops_before_application
run "Claude probe failure stops before application"   t_claude_probe_failure_stops_before_application
run "unverified pin application stops"                t_unverified_pin_application_stops
run "failed fixed pin restores its declaration"       t_failed_fixed_pin_restores_the_declaration
run "changed pin requires upgrade selection"          t_changed_pin_requires_an_upgrade_plan_row
run "changed uv pin requires upgrade selection"       t_changed_uv_pin_requires_an_upgrade_plan_row
run "changed Sheldon pin requires upgrade selection"  t_changed_sheldon_pin_requires_an_upgrade_plan_row
run "failed uv tools restore their declarations"      t_failed_uv_tool_restores_only_its_declaration
run "successful no-op is reported unchanged"          t_successful_noop_is_reported_unchanged
run "still-outdated Homebrew result stops"             t_still_outdated_homebrew_result_stops
run "cask verification includes auto-updates"          t_cask_verification_includes_auto_updates
run "Sheldon update is reported as deferred"          t_sheldon_update_is_reported_as_deferred
run "unwritable report stops before application"      t_unwritable_report_stops_before_application
run "report alias stops before truncation"            t_report_alias_is_rejected_before_truncation
run "safe changes remain mergeable with holds"        t_safe_changes_remain_mergeable_with_holds
run "held-only Homebrew skips dependency checks"      t_all_held_homebrew_skips_dependency_checks
run "undeclared candidates are rejected first"        t_undeclared_candidate_is_rejected_before_application
run "unpinned agent-sentinel upgrade is rejected"    t_agent_sentinel_unpinned_upgrade_is_rejected
run "unpinned claude-sessions upgrade is rejected"   t_claude_sessions_unpinned_upgrade_is_rejected
run "full commit uv upgrade is allowed"              t_full_commit_uv_upgrade_is_allowed

print "$pass passed, $fail failed"
(( fail == 0 ))
