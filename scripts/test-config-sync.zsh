#!/bin/zsh
set -u

REPO="${0:A:h}/.."
[[ -f "$REPO/config.zsh" ]] || { print -u2 "missing $REPO/config.zsh"; exit 1 }
REAL_CONFIG_PYTHON="${OH_MY_MAC_TEST_CONFIG_PYTHON:-$HOME/.local/share/oh-my-mac/config-tools/bin/python}"
[[ -x "$REAL_CONFIG_PYTHON" ]] || { print -u2 "missing oh-my-mac-config-python"; exit 1 }
export REAL_CONFIG_PYTHON

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export STUB_BIN="$tmp/bin"
export STUB_STATE="$tmp/stub-state"
export UV_CACHE_DIR="$tmp/uv-cache"
export UV_NO_PROGRESS=1
mkdir -p "$STUB_STATE"

stub_file() {
  mkdir -p "${1:h}"
  cat > "$1"
  chmod +x "$1"
}

stub() { stub_file "$tmp/bin/$1" }

select_config_tools_test_root() {
  export OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT=$1
  mkdir -p "$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT"
  : > "$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT/.oh-my-mac-config-tools-test-root"
  source "$REPO/scripts/config-tools.zsh"
}

select_config_tools_test_root "$tmp/config-tools-root"
stub_file "$CONFIG_TOOLS_PYTHON" <<'STUB'
#!/bin/zsh
exec "$REAL_CONFIG_PYTHON" "$@"
STUB

# An isolated HOME does not redirect these: `defaults` reads and writes through
# cfprefsd, and duti/code hold state outside the home directory. Each stub keeps
# what it was told in $STUB_STATE so a second sync sees the first one's writes.
stub defaults <<'STUB'
#!/bin/zsh
store="$STUB_STATE/defaults"
case "$1" in
  read)
    value=$(grep -m1 "^$2 $3=" "$store" 2>/dev/null) || exit 1
    print -r -- "${value#*=}"
    ;;
  write)
    value="$5"
    [[ "$4" == "-bool" ]] && { [[ "$value" == "false" ]] && value=0 || value=1 }
    print -r -- "$2 $3=$value" >> "$store"
    ;;
esac
STUB

stub duti <<'STUB'
#!/bin/zsh
store="$STUB_STATE/duti"
case "$1" in
  -x) bundle=$(grep -m1 "^$2=" "$store" 2>/dev/null) || exit 1
      print -rl -- "App" "/Applications/App.app" "${bundle#*=}" ;;
  -s) print -r -- "${3#.}=$2" >> "$store" ;;
esac
STUB

stub code <<'STUB'
#!/bin/zsh
store="$STUB_STATE/vscode-extensions"
case "$1" in
  --list-extensions)
    [[ -f "$STUB_STATE/update-order-enabled" ]] && print code >> "$STUB_STATE/update-order"
    [[ -f "$store" ]] && cat "$store"
    ;;
  --install-extension)
    print -r -- "$2" >> "$STUB_STATE/vscode-extension-attempts"
    [[ -f "$STUB_STATE/vscode-extension-install-fails" ]] && exit 2
    print -r -- "$2" >> "$store"
    ;;
esac
exit 0
STUB

stub agent-sentinel <<'STUB'
#!/bin/zsh
[[ -f "$STUB_STATE/agent-sentinel-unavailable" ]] && exit 127
[[ "${1:-}" == "--help" ]] && exit 0
if [[ "${1:-}" == "install" ]]; then
  target="" config_path=""
  while (( $# > 0 )); do
    case "$1" in
      --target) target="$2"; shift 2 ;;
      --path) config_path="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [[ "$target" == "codex" ]]; then
    mkdir -p "${config_path:h}" "${config_path:h}/rules"
    if [[ -f "$STUB_STATE/agent-sentinel-invalid-codex-hook" ]]; then
      print -r -- '{"hooks":{"PreToolUse":[]}}' > "$config_path"
    else
      [[ -f "$config_path" ]] || print -r -- '{}' > "$config_path"
      sentinel='{"matcher":"*","hooks":[{"type":"command","command":"agent-sentinel --host codex"}]}'
      if [[ -f "$STUB_STATE/agent-sentinel-changed-codex-hook" ]]; then
        sentinel='{"matcher":"Bash","hooks":[{"type":"command","command":"agent-sentinel --host codex","timeout":30}]}'
      fi
      jq --arg command 'agent-sentinel --host codex' \
        --argjson sentinel "$sentinel" '
        .hooks = (.hooks // {}) |
        .hooks.PreToolUse = (
          [(.hooks.PreToolUse // [])[]
            | select([.hooks[]?.command] | index($command) == null)]
          + [$sentinel]
        )
      ' "$config_path" > "$config_path.new"
      mv "$config_path.new" "$config_path"
    fi

    rules_path="${config_path:h}/rules/agent-sentinel.rules"
    if [[ -f "$STUB_STATE/agent-sentinel-missing-codex-rules" ]]; then
      rm -f "$rules_path"
    elif [[ -f "$STUB_STATE/agent-sentinel-default-allow-rule" ]]; then
      print -r -- $'prefix_rule(\n    pattern = ["ssh"],\n)' > "$rules_path"
    elif [[ -f "$STUB_STATE/agent-sentinel-explicit-allow-rule" ]]; then
      print -r -- $'prefix_rule(\n    pattern = ["ssh"],\n    decision="allow",\n)' \
        > "$rules_path"
    elif [[ -f "$STUB_STATE/agent-sentinel-changed-codex-rules" ]]; then
      print -r -- $'prefix_rule(\n    pattern = ["ssh"],\n    decision = "forbidden",\n)' \
        > "$rules_path"
    else
      print -r -- $'prefix_rule(\n    pattern = ["ssh"],\n    decision = "prompt",\n)' \
        > "$rules_path"
    fi

    codex_config="${config_path:h}/config.toml"
    if [[ -f "$codex_config" ]]; then
      if grep -Eq '^approval_policy[[:space:]]*=[[:space:]]*"never"' "$codex_config"; then
        print -r -- 'Warning: approval_policy="never" disables approval prompts. Codex GUI may run commands matched by agent-sentinel prompt rules without approval, so ASK enforcement is not guaranteed. Native approvals and auto-review are also unavailable. Use on-request for the supported configuration.'
      fi
      if grep -Eq '^[[:space:]]*hooks[[:space:]]*=[[:space:]]*false' "$codex_config"; then
        print -r -- "Warning: Codex hooks are disabled in config.toml; agent-sentinel's hook DENY rules will not run."
      fi
    fi
  fi
fi
exit 0
STUB

stub codex <<'STUB'
#!/bin/zsh
if [[ "${1:-}" == "execpolicy" && "${2:-}" == "check" ]]; then
  print -r -- '{"decision":"prompt"}'
fi
exit 0
STUB

stub uv <<'STUB'
#!/bin/zsh
case "$1" in
  run)
    print -u2 "unexpected uv run"
    exit 99
    ;;
  tool)
    [[ -f "$STUB_STATE/update-order-enabled" && "$2" == "list" ]] && \
      print uv-tools >> "$STUB_STATE/update-order"
    case "$2" in
      list)
        [[ -f "$STUB_STATE/claude-sentinel-tool" ]] && print 'claude-sentinel v0.1.0'
        [[ -f "$STUB_STATE/agent-sentinel-tool" ]] && print 'agent-sentinel v2026.08.12.5'
        exit 0
        ;;
      install)
        print -r -- "${*:3}" >> "$STUB_STATE/uv-tool-installs"
        if [[ "${*:3}" == *agent-sentinel* ]]; then
          [[ -f "$STUB_STATE/agent-sentinel-install-fails" ]] && exit 2
          : > "$STUB_STATE/agent-sentinel-tool"
          rm -f "$STUB_STATE/agent-sentinel-unavailable"
        elif [[ -f "$STUB_STATE/uv-tool-install-fails" ]]; then
          exit 2
        fi
        exit 0
        ;;
    esac
    ;;
  venv)
    environment="${@[-1]}"
    print venv >> "$STUB_STATE/config-tool-commands"
    mkdir -p "$environment/bin"
    cat > "$environment/bin/python" <<'PYTHON'
#!/bin/zsh
if [[ "$1" == "-c" ]]; then
  print 0.15.1
  exit 0
fi
exec "$REAL_CONFIG_PYTHON" "$@"
PYTHON
    chmod +x "$environment/bin/python"
    ;;
  pip)
    print pip >> "$STUB_STATE/config-tool-commands"
    [[ -f "$STUB_STATE/update-order-enabled" ]] && print config-tools >> "$STUB_STATE/update-order"
    ;;
  *)
    print -u2 "unexpected uv command: $1"
    exit 99
    ;;
esac
exit 0
STUB

stub oh-my-mac-config-python <<'STUB'
#!/bin/zsh
print external-config-python >> "$STUB_STATE/external-config-python"
exit 88
STUB

stub brew <<'STUB'
#!/bin/zsh
if [[ "$1" == "trust" && "${2:-}" == "--json" ]]; then
  print '[]'
elif [[ "$1" == "trust" && -f "$STUB_STATE/brew-trust-fails" ]]; then
  exit 2
fi
exit 0
STUB

stub sheldon <<'STUB'
#!/bin/zsh
exit 0
STUB

pass=0 fail=0 home_n=0 current=""

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

check_nonzero() {
  if [[ "$2" != "0" ]]; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    print -u2 "FAIL $current: $1"
    print -u2 "  expected: nonzero"
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

# Command substitution strips trailing newlines from both sides, so a byte-level
# difference at the end of a file only shows up through cmp.
check_files_equal() {
  if cmp -s "$2" "$3"; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    print -u2 "FAIL $current: $1"
    diff "$3" "$2" | head -5 | while IFS= read -r line; do print -u2 "  $line"; done
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
  home_n=$(( home_n + 1 ))
  export HOME="$tmp/home$home_n"
  rm -rf "$STUB_STATE"
  mkdir -p "$HOME" "$STUB_STATE"
  "$2"
}

sync_config() { "$REPO/config.zsh" sync 2>&1 }
diff_config() { "$REPO/config.zsh" diff 2>&1 }
sync_config_from() { "$1/config.zsh" sync 2>&1 }
diff_config_from() { "$1/config.zsh" diff 2>&1 }
make_update() { make -s -C "$REPO" update INSTALL_STEPS= 2>&1 }
make_install_with_steps() { make -s -j4 -C "$REPO" install "INSTALL_STEPS=$1" 2>&1 }
make_update_with_steps() { make -s -C "$REPO" update "INSTALL_STEPS=$1" 2>&1 }
make_upgrade_apply_with_steps() {
  make -s -j4 -C "$REPO" upgrade-apply "UPGRADE_STEPS=$1" 2>&1
}
refresh_agent_sentinel() { "$REPO/scripts/refresh-agent-sentinel.zsh" 2>&1 }
make_refresh_install() {
  make -s -C "$REPO" install-uv-tools AGENT_SENTINEL_UPGRADE=1 2>&1
}

write_enabled_claude_plugins() {
  mkdir -p "$HOME/.claude"
  jq -Rn '
    [inputs | select(length > 0)] |
    {enabledPlugins: map({key: ., value: true}) | from_entries}
  ' < "$REPO/config/claude/plugins.txt" > "$HOME/.claude/settings.json"
}

t_invalid_modes_are_rejected() {
  local output exit_status

  output="$("$REPO/config.zsh" typo 2>&1)"
  exit_status=$?
  check_equals "an unknown mode fails" "$exit_status" "1"
  check_contains "an unknown mode prints usage" "$output" "Usage: $REPO/config.zsh diff|sync"

  output="$("$REPO/config.zsh" 2>&1)"
  exit_status=$?
  check_equals "a missing mode fails" "$exit_status" "1"
  check_contains "a missing mode prints usage" "$output" "Usage: $REPO/config.zsh diff|sync"

  output="$("$REPO/config.zsh" sync extra 2>&1)"
  exit_status=$?
  check_equals "extra arguments fail" "$exit_status" "1"
  check_contains "extra arguments print usage" "$output" "Usage: $REPO/config.zsh diff|sync"

  check_equals "invalid invocations leave HOME untouched" \
    "$(find "$HOME" -mindepth 1 | wc -l | tr -d ' ')" "0"
  check_equals "invalid invocations leave global Git config untouched" \
    "$([[ ! -e "$GIT_CONFIG_GLOBAL" ]] && print yes || print no)" "yes"
  check_equals "invalid invocations leave external settings untouched" \
    "$(find "$STUB_STATE" -mindepth 1 | wc -l | tr -d ' ')" "0"
}

t_diff_uses_prepared_config_python() {
  local output exit_status

  output="$(env -u UV_CACHE_DIR make -s -C "$REPO" diff-config 2>&1)"
  exit_status=$?
  check_equals "offline diff succeeds without an external uv cache setting" "$exit_status" "0"
  check_equals "HOME untouched" "$(find "$HOME" -mindepth 1 | wc -l | tr -d ' ')" "0"
  check_lacks "diff does not invoke uv run" "$output" "unexpected uv run"
}

write_invalid_config_python() {
  local scenario=$1 python=$2
  print -r -- '#!/bin/zsh' > "$python"
  case "$scenario" in
    broken) print -r -- 'exit 1' >> "$python" ;;
    wrong-dependency) print -r -- '[[ "$1" == "-c" ]] && print 0.14.0' >> "$python" ;;
    unsupported-python)
      print -r -- '[[ "$2" == *sys.version_info* ]] && exit 1' >> "$python"
      print -r -- 'print 0.15.1' >> "$python"
      ;;
  esac
  chmod +x "$python"
}

check_config_tools_repair() {
  local scenario=$1 label=$2 output exit_status commands
  select_config_tools_test_root "$HOME/$scenario"
  mkdir -p "$CONFIG_TOOLS_DIR/bin"
  write_invalid_config_python "$scenario" "$CONFIG_TOOLS_PYTHON"
  print stale > "$CONFIG_TOOLS_DIR/stale"
  rm -f "$STUB_STATE/config-tool-commands"

  output="$(make -s -C "$REPO" install-config-tools 2>&1)"
  exit_status=$?
  commands="$(<$STUB_STATE/config-tool-commands)"

  check_equals "$label is repaired" "$exit_status" "0"
  [[ "$exit_status" == "0" ]] || print -u2 -- "$output"
  check_contains "$label repair starts an installation" "$output" "Installing config tools..."
  check_contains "$label repair recreates the environment" "$commands" "venv"
  check_contains "$label repair installs the dependency" "$commands" "pip"
  check_equals "$label repair replaces the old environment" \
    "$([[ ! -e "$CONFIG_TOOLS_DIR/stale" ]] && print yes || print no)" "yes"
  check_equals "$label repair installs a validated environment" \
    "$("$CONFIG_TOOLS_PYTHON" -c ignored)" "0.15.1"
}

t_config_tools_repair_invalid_environments() {
  local original_test_root="$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT"
  check_config_tools_repair broken "a broken config environment"
  check_config_tools_repair wrong-dependency "a mismatched dependency"
  check_config_tools_repair unsupported-python "an unsupported Python"
  select_config_tools_test_root "$original_test_root"
}

t_config_tools_reject_unmanaged_directory() {
  local unsafe="$HOME/Documents/config-tools" output exit_status
  local original_test_root="$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT"
  mkdir -p "$unsafe"
  print preserve > "$unsafe/personal-data"
  export OH_MY_MAC_CONFIG_TOOLS_DIR="$unsafe"

  output="$(make -s -C "$REPO" install-config-tools 2>&1)"
  exit_status=$?

  check_nonzero "an unmanaged config tools directory is rejected" "$exit_status"
  check_contains "the rejected override is identified" "$output" \
    "OH_MY_MAC_CONFIG_TOOLS_DIR is not supported"
  check_equals "rejection preserves the unmanaged directory" \
    "$(<$unsafe/personal-data)" "preserve"
  check_equals "rejection does not invoke uv" \
    "$([[ ! -e "$STUB_STATE/config-tool-commands" ]] && print yes || print no)" "yes"

  unset OH_MY_MAC_CONFIG_TOOLS_DIR
  export OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT="$HOME/Documents"
  source "$REPO/scripts/config-tools.zsh"

  output="$(make -s -C "$REPO" install-config-tools 2>&1)"
  exit_status=$?

  check_nonzero "an unmarked test directory is rejected" "$exit_status"
  check_contains "the unsafe test root is identified" "$output" \
    "unsafe config tools test root"
  check_equals "unsafe test root rejection preserves user data" \
    "$(<$unsafe/personal-data)" "preserve"
  check_equals "unsafe test root rejection does not invoke uv" \
    "$([[ ! -e "$STUB_STATE/config-tool-commands" ]] && print yes || print no)" "yes"

  select_config_tools_test_root "$original_test_root"
}

t_diff_after_sync_is_clean() {
  sync_config > /dev/null
  check_contains "second pass reports nothing" "$(diff_config)" "No differences found."
}

t_sync_is_idempotent() {
  sync_config > /dev/null
  check_contains "second sync changes nothing" "$(sync_config)" "Already up to date."
}

t_iterm_profile_migrates_without_overwriting_local_values() {
  local profile="$HOME/Library/Application Support/iTerm2/DynamicProfiles/profile.json"
  local baseline="$HOME/Library/Application Support/oh-my-mac/iterm2-profile-baseline.json"
  mkdir -p "${profile:h}"
  jq '
    .Profiles[0].Guid = "existing-guid" |
    .Profiles[0]["Normal Font"] = "Local Font 14" |
    del(.Profiles[0].Rewritable)
  ' "$REPO/config/iterm2/profile.json" > "$profile"

  sync_config > /dev/null

  check_equals "an existing profile keeps its local value during migration" \
    "$(jq -r '.Profiles[0]["Normal Font"]' "$profile")" "Local Font 14"
  check_equals "the migrated profile keeps its Guid" \
    "$(jq -r '.Profiles[0].Guid' "$profile")" "existing-guid"
  check_equals "the migrated profile becomes rewritable" \
    "$(jq -r '.Profiles[0].Rewritable' "$profile")" "true"
  check_files_equal "migration records the repository baseline" \
    "$baseline" "$REPO/config/iterm2/profile.json"
}

t_iterm_profile_three_way_merge_preserves_local_changes() {
  local profile="$HOME/Library/Application Support/iTerm2/DynamicProfiles/profile.json"
  local baseline="$HOME/Library/Application Support/oh-my-mac/iterm2-profile-baseline.json"
  local repo_copy="$tmp/iterm-repo-$home_n" guid output
  sync_config > /dev/null
  guid=$(jq -r '.Profiles[0].Guid' "$profile")
  cp -R "$REPO" "$repo_copy"

  jq '
    .Profiles[0]["Normal Font"] = "Repository Font 13" |
    .Profiles[0]["Scrollback Lines"] = 200000 |
    .Profiles[0]["Keyboard Map"]["repo-new"] = {"Text":"r","Action":10} |
    del(.Profiles[0]["Mouse Reporting"])
  ' "$repo_copy/config/iterm2/profile.json" > "$repo_copy/config/iterm2/profile.json.new"
  mv "$repo_copy/config/iterm2/profile.json.new" "$repo_copy/config/iterm2/profile.json"
  jq '
    .Profiles[0]["Normal Font"] = "Local Font 14" |
    .Profiles[0]["Silence Bell"] = false |
    .Profiles[0]["Keyboard Map"]["0xf728-0x80000"].Text = "local" |
    .Profiles[0]["Local Setting"] = "kept" |
    del(.Profiles[0]["Prompt Before Closing 2"])
  ' "$profile" > "$profile.new"
  mv "$profile.new" "$profile"

  output="$(sync_config_from "$repo_copy")"

  check_contains "the profile is updated after repository changes" \
    "$output" "Synced iTerm2 Dynamic Profile."
  check_equals "a conflicting local scalar wins" \
    "$(jq -r '.Profiles[0]["Normal Font"]' "$profile")" "Local Font 14"
  check_equals "an untouched scalar receives the repository update" \
    "$(jq -r '.Profiles[0]["Scrollback Lines"]' "$profile")" "200000"
  check_equals "a local scalar remains changed" \
    "$(jq -r '.Profiles[0]["Silence Bell"]' "$profile")" "false"
  check_equals "a repository key is added inside a local object" \
    "$(jq -r '.Profiles[0]["Keyboard Map"]["repo-new"].Text' "$profile")" "r"
  check_equals "a local key remains changed inside an updated object" \
    "$(jq -r '.Profiles[0]["Keyboard Map"]["0xf728-0x80000"].Text' "$profile")" "local"
  check_equals "a local-only key is preserved" \
    "$(jq -r '.Profiles[0]["Local Setting"]' "$profile")" "kept"
  check_equals "a locally removed key stays removed" \
    "$(jq -r '.Profiles[0] | has("Prompt Before Closing 2")' "$profile")" "false"
  check_equals "a repository removal applies to an untouched key" \
    "$(jq -r '.Profiles[0] | has("Mouse Reporting")' "$profile")" "false"
  check_equals "the profile Guid remains stable" \
    "$(jq -r '.Profiles[0].Guid' "$profile")" "$guid"
  check_files_equal "the new repository values become the next baseline" \
    "$baseline" "$repo_copy/config/iterm2/profile.json"
  check_contains "the merged profile has a clean diff" \
    "$(diff_config_from "$repo_copy")" "No differences found."
  check_contains "the merged profile is idempotent" \
    "$(sync_config_from "$repo_copy")" "Already up to date."
}

t_claude_script_orphans_are_removed() {
  local scripts="$HOME/.claude/scripts" orphan="$HOME/.claude/scripts/check-docs.zsh" output
  mkdir -p "$scripts"
  print -r -- "stale" > "$orphan"

  output="$(diff_config)"
  check_contains "diff reports the removed Claude script" "$output" \
    "Orphan: $orphan (no config/claude/scripts/check-docs.zsh)"
  check_equals "diff preserves the removed Claude script" \
    "$([[ -f "$orphan" ]] && print yes || print no)" "yes"

  sync_config > /dev/null
  check_equals "sync removes the Claude script orphan" \
    "$([[ ! -e "$orphan" ]] && print yes || print no)" "yes"
  check_lacks "the synced hook no longer calls check-docs" \
    "$(<"$scripts/claude-hook.zsh")" "check-docs"
  check_contains "Claude script orphan removal is idempotent" \
    "$(sync_config)" "Already up to date."
}

t_sync_requires_agent_sentinel() {
  : > "$STUB_STATE/agent-sentinel-unavailable"
  local output exit_status
  output="$(sync_config)"
  exit_status=$?
  check_equals "a missing agent-sentinel fails before writing config" "$exit_status" "1"
  check_contains "the preflight explains the missing tool" "$output" \
    "agent-sentinel must be installed before syncing its configuration"
  check_equals "the failed preflight leaves HOME untouched" \
    "$(find "$HOME" -mindepth 1 | wc -l | tr -d ' ')" "0"
}

t_agent_sentinel_config_is_synced() {
  mkdir -p "$HOME/.claude/scripts" "$HOME/.codex/rules"
  print -r -- "legacy wrapper" > "$HOME/.claude/scripts/claude-sentinel-wrapper.zsh"
  print -r -- '{"hooks":{"PreToolUse":[{"matcher":"custom","hooks":[{"type":"command","command":"custom-pre-tool-hook"}]}],"Stop":[{"hooks":[{"type":"command","command":"custom-stop-hook"}]}]}}' \
    > "$HOME/.codex/hooks.json"
  print -r -- 'prefix_rule(pattern = ["custom"], decision = "prompt")' \
    > "$HOME/.codex/rules/default.rules"

  sync_config > /dev/null

  check_contains "Codex hooks are generated and synced" \
    "$(<$HOME/.codex/hooks.json)" 'agent-sentinel --host codex'
  check_contains "unrelated Codex PreToolUse hooks are preserved" \
    "$(<$HOME/.codex/hooks.json)" 'custom-pre-tool-hook'
  check_contains "unrelated Codex hook events are preserved" \
    "$(<$HOME/.codex/hooks.json)" 'custom-stop-hook'
  check_contains "agent-sentinel execution rules are generated and synced" \
    "$(<$HOME/.codex/rules/agent-sentinel.rules)" 'decision = "prompt"'
  check_equals "Codex default rules remain application-owned" \
    "$(<$HOME/.codex/rules/default.rules)" \
    'prefix_rule(pattern = ["custom"], decision = "prompt")'
  check_lacks "agent-sentinel rules never allow sandbox bypass" \
    "$(<$HOME/.codex/rules/agent-sentinel.rules)" 'decision = "allow"'
  check_contains "Codex runs the dedicated host protocol" \
    "$(<$HOME/.codex/hooks.json)" 'agent-sentinel --host codex'
  check_contains "Codex keeps on-request approvals" \
    "$(<$HOME/.codex/config.toml)" 'approval_policy = "on-request"'
  check_contains "Codex keeps the workspace-write sandbox" \
    "$(<$HOME/.codex/config.toml)" 'sandbox_mode = "workspace-write"'
  check_files_equal "the renamed Claude wrapper is synced" \
    "$HOME/.claude/scripts/agent-sentinel-wrapper.zsh" \
    "$REPO/config/claude/scripts/agent-sentinel-wrapper.zsh"
  check_equals "the old Claude wrapper is removed" \
    "$([[ ! -e "$HOME/.claude/scripts/claude-sentinel-wrapper.zsh" ]] && print yes || print no)" \
    "yes"
}

t_codex_hook_trust_notice_tracks_definition_changes() {
  local first_output second_output changed_output unchanged_output

  first_output="$(sync_config)"
  check_contains "a new Codex hook requires trust" "$first_output" \
    "Codex hook trust is required."
  check_contains "the trust notice identifies the app workflow" "$first_output" \
    "GUI: Open Settings > Hooks."
  check_contains "the trust notice identifies the CLI workflow" "$first_output" \
    "CLI: Run /hooks."

  second_output="$(sync_config)"
  check_lacks "an identical sync repeats no trust notice" "$second_output" \
    "Codex hook trust is required."

  : > "$STUB_STATE/agent-sentinel-changed-codex-hook"
  changed_output="$(sync_config)"
  check_contains "a changed Codex hook requires trust again" "$changed_output" \
    "Codex hook trust is required."

  unchanged_output="$(sync_config)"
  check_lacks "the changed definition is reported only once" "$unchanged_output" \
    "Codex hook trust is required."
}

t_codex_hook_trust_notice_ignores_rule_changes() {
  sync_config > /dev/null
  : > "$STUB_STATE/agent-sentinel-changed-codex-rules"

  local output
  output="$(sync_config)"
  check_contains "changed execution rules are synced" "$output" \
    "Synced: $HOME/.codex/rules/agent-sentinel.rules"
  check_lacks "execution rules do not require hook trust" "$output" \
    "Codex hook trust is required."
}

t_codex_hook_trust_notice_precedes_later_failures() {
  mkdir -p "$HOME/.codex"
  print -r -- 'sandbox_mode = "unterminated' > "$HOME/.codex/config.toml"

  local failed_output exit_status retry_output
  failed_output="$(sync_config)"
  exit_status=$?
  check_equals "a later merge failure fails the sync" "$exit_status" "1"
  check_contains "a written hook is reported before the later failure" "$failed_output" \
    "Codex hook trust is required."

  print -r -- 'sandbox_mode = "workspace-write"' > "$HOME/.codex/config.toml"
  retry_output="$(sync_config)"
  check_lacks "the retry does not repeat the delivered trust notice" "$retry_output" \
    "Codex hook trust is required."
}

t_refresh_reports_only_pending_hook_changes() {
  sync_config > /dev/null

  local unchanged_output changed_output repeated_output
  unchanged_output="$(refresh_agent_sentinel)"
  check_lacks "a refresh with no pending change reports no trust notice" "$unchanged_output" \
    "The generated Codex hook definition changed."

  : > "$STUB_STATE/agent-sentinel-changed-codex-hook"
  changed_output="$(refresh_agent_sentinel)"
  check_contains "refresh reports a pending hook definition change" "$changed_output" \
    "The generated Codex hook definition changed."
  check_contains "refresh asks for sync before trust" "$changed_output" \
    "Run 'make sync-config', then review and trust the agent-sentinel hook:"
  check_contains "the pending notice identifies the app workflow" "$changed_output" \
    "GUI: Open Settings > Hooks."
  check_contains "the pending notice identifies the CLI workflow" "$changed_output" \
    "CLI: Run /hooks."

  repeated_output="$(refresh_agent_sentinel)"
  check_contains "refresh repeats the notice while the change remains pending" \
    "$repeated_output" "The generated Codex hook definition changed."
}

assert_agent_sentinel_generation_fails() {
  local state_file=$1 expected_error=$2 output exit_status
  print -r -- "existing config" > "$HOME/.zshrc"
  : > "$STUB_STATE/$state_file"

  output="$(sync_config)"
  exit_status=$?

  check_equals "invalid generated config fails before sync" "$exit_status" "1"
  check_contains "the validation error identifies the generated config" \
    "$output" "$expected_error"
  check_equals "the failed validation preserves existing config" \
    "$(<$HOME/.zshrc)" "existing config"
  check_equals "the failed validation creates no Codex config" \
    "$([[ ! -e "$HOME/.codex" ]] && print yes || print no)" "yes"
}

t_sync_rejects_missing_sentinel_hook() {
  assert_agent_sentinel_generation_fails \
    "agent-sentinel-invalid-codex-hook" \
    "agent-sentinel did not generate its Codex PreToolUse hook"
}

t_sync_rejects_default_allow_rule() {
  assert_agent_sentinel_generation_fails \
    "agent-sentinel-default-allow-rule" \
    "every agent-sentinel Codex rule must explicitly use prompt or forbidden"
}

t_sync_rejects_explicit_allow_rule() {
  assert_agent_sentinel_generation_fails \
    "agent-sentinel-explicit-allow-rule" \
    "every agent-sentinel Codex rule must explicitly use prompt or forbidden"
}

t_sync_rejects_missing_sentinel_rules() {
  assert_agent_sentinel_generation_fails \
    "agent-sentinel-missing-codex-rules" \
    "agent-sentinel did not generate Codex execution rules"
}

t_update_migrates_legacy_sentinel_once() {
  mkdir -p "$HOME/.claude/scripts" "$HOME/.codex/rules"
  cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "zsh ~/.claude/scripts/claude-sentinel-wrapper.zsh"
          }
        ]
      }
    ]
  }
}
EOF
  print -r -- "legacy wrapper" > "$HOME/.claude/scripts/claude-sentinel-wrapper.zsh"
  : > "$STUB_STATE/claude-sentinel-tool"
  : > "$STUB_STATE/agent-sentinel-unavailable"

  local first_output second_output installs
  first_output="$(make_update)"
  check_contains "the first update completes the config sync" "$first_output" \
    "Synced: $HOME/.codex/hooks.json"
  installs="$(<$STUB_STATE/uv-tool-installs)"
  check_contains "the legacy executable collision uses force once" "$installs" \
    "--force agent-sentinel[claude] @ git+https://github.com/tani-shi/agent-sentinel.git"
  check_equals "the standalone legacy tool environment remains" \
    "$([[ -f "$STUB_STATE/claude-sentinel-tool" ]] && print yes || print no)" "yes"
  check_contains "Claude switches to the renamed wrapper" \
    "$(<$HOME/.claude/settings.json)" "agent-sentinel-wrapper.zsh"
  check_contains "Codex switches to agent-sentinel" \
    "$(<$HOME/.codex/hooks.json)" "agent-sentinel --host codex"
  check_contains "the first update requests Codex hook trust" "$first_output" \
    "Codex hook trust is required."

  second_output="$(make_update)"
  check_contains "the second update leaves config unchanged" "$second_output" \
    "Already up to date."
  check_lacks "the second update repeats no trust notice" "$second_output" \
    "Codex hook trust is required."
  installs="$(<$STUB_STATE/uv-tool-installs)"
  check_equals "force is used only for the first migration" \
    "$(print -r -- "$installs" | grep -c -- '--force')" "1"
}

t_update_stops_before_sync_when_sentinel_install_fails() {
  mkdir -p "$HOME/.claude"
  print -r -- '{"legacy":"claude-sentinel"}' > "$HOME/.claude/settings.json"
  local before="$tmp/legacy-settings.json" output exit_status
  cp "$HOME/.claude/settings.json" "$before"
  : > "$STUB_STATE/claude-sentinel-tool"
  : > "$STUB_STATE/agent-sentinel-unavailable"
  : > "$STUB_STATE/agent-sentinel-install-fails"

  output="$(make_update)"
  exit_status=$?
  check_equals "an agent-sentinel install failure fails make update" "$exit_status" "2"
  check_files_equal "the failed install preserves Claude settings" \
    "$HOME/.claude/settings.json" "$before"
  check_equals "the failed install creates no Codex hook" \
    "$([[ ! -e "$HOME/.codex/hooks.json" ]] && print yes || print no)" "yes"
  check_lacks "config sync never starts after the failed install" "$output" "Synced:"
}

t_refresh_requests_agent_sentinel_upgrade() {
  make_refresh_install > /dev/null
  check_contains "refresh explicitly upgrades the HEAD-tracking tool" \
    "$(<$STUB_STATE/uv-tool-installs)" \
    "--upgrade agent-sentinel[claude] @ git+https://github.com/tani-shi/agent-sentinel.git"
}

t_codex_skills_are_synced() {
  sync_config > /dev/null
  local source rel expected="$tmp/expected-codex-skills-manifest"
  : > "$expected"
  for source in "$REPO"/config/codex/skills/**/*(.N); do
    rel="${source#$REPO/config/codex/skills/}"
    check_files_equal "$rel is synced into the user skill directory" \
      "$HOME/.agents/skills/$rel" "$source"
    print -r -- "$rel" >> "$expected"
  done
  check_files_equal "the manifest lists repository-managed skill files" \
    "$HOME/.agents/skills/.oh-my-mac-managed" "$expected"
  check_contains "the skill requires explicit invocation" \
    "$(<$HOME/.agents/skills/refactor-review/agents/openai.yaml)" \
    "allow_implicit_invocation: false"
  check_contains "review mode is read-only" \
    "$(<$HOME/.agents/skills/refactor-review/SKILL.md)" "Do not modify files."
  check_contains "apply mode uses only the preceding review" \
    "$(<$HOME/.agents/skills/refactor-review/SKILL.md)" \
    "immediately preceding Refactor Review"
}

t_codex_skill_name_collisions_are_rejected() {
  local skill="$HOME/.agents/skills/refactor-review" output exit_status
  mkdir -p "$skill"
  print -r -- "personal skill" > "$skill/SKILL.md"

  output="$(sync_config)"
  exit_status=$?
  check_equals "an unmanaged same-name skill fails the sync" "$exit_status" "1"
  check_contains "the collision identifies the unmanaged skill" "$output" \
    "Unmanaged Codex skill already exists: $skill"
  check_equals "the personal skill remains unchanged" "$(<$skill/SKILL.md)" "personal skill"
  check_equals "the collision aborts before other config is written" \
    "$([[ ! -e "$HOME/.zshrc" ]] && print yes || print no)" "yes"
}

t_codex_skill_file_collisions_are_rejected() {
  local skill="$HOME/.agents/skills/refactor-review" output exit_status
  mkdir -p "$skill/agents"
  cp "$REPO/config/codex/skills/refactor-review/SKILL.md" "$skill/SKILL.md"
  print -r -- "refactor-review/SKILL.md" > "$HOME/.agents/skills/.oh-my-mac-managed"
  print -r -- "personal metadata" > "$skill/agents/openai.yaml"

  output="$(sync_config)"
  exit_status=$?
  check_equals "an unmanaged file in a managed skill fails the sync" "$exit_status" "1"
  check_contains "the collision identifies the unmanaged file" "$output" \
    "Unmanaged Codex skill file already exists: $skill/agents/openai.yaml"
  check_equals "the personal skill file remains unchanged" \
    "$(<$skill/agents/openai.yaml)" "personal metadata"
  check_equals "the file collision aborts before other config is written" \
    "$([[ ! -e "$HOME/.zshrc" ]] && print yes || print no)" "yes"
}

t_codex_skill_orphans_are_scoped() {
  local skills="$HOME/.agents/skills" output
  mkdir -p "$skills/refactor-review/agents" "$skills/removed-skill" \
    "$skills/personal-skill" "$HOME/.agents/outside-skill"
  print -r -- "stale" > "$skills/refactor-review/agents/removed.yaml"
  print -r -- "stale" > "$skills/removed-skill/SKILL.md"
  print -r -- "personal" > "$skills/personal-skill/SKILL.md"
  print -r -- "outside" > "$HOME/.agents/outside-skill/SKILL.md"
  print -rl -- "refactor-review/agents/removed.yaml" "removed-skill/SKILL.md" \
    "../outside-skill/SKILL.md" > "$skills/.oh-my-mac-managed"

  output="$(diff_config)"
  check_contains "diff reports a removed file in a current skill" "$output" \
    "Orphan: $skills/refactor-review/agents/removed.yaml"
  check_contains "diff reports a file in a removed skill" "$output" \
    "Orphan: $skills/removed-skill/SKILL.md"
  check_equals "diff preserves the removed skill" \
    "$([[ -d "$skills/removed-skill" ]] && print yes || print no)" "yes"
  check_equals "diff preserves the removed file" \
    "$([[ -f "$skills/refactor-review/agents/removed.yaml" ]] && print yes || print no)" "yes"

  sync_config > /dev/null
  check_equals "sync removes the previously managed skill" \
    "$([[ ! -e "$skills/removed-skill" ]] && print yes || print no)" "yes"
  check_equals "sync removes a deleted file from a current skill" \
    "$([[ ! -e "$skills/refactor-review/agents/removed.yaml" ]] && print yes || print no)" "yes"
  check_equals "sync preserves an unmanaged personal skill" \
    "$([[ -d "$skills/personal-skill" ]] && print yes || print no)" "yes"
  check_equals "sync ignores a manifest path outside the skill directory" \
    "$([[ -d "$HOME/.agents/outside-skill" ]] && print yes || print no)" "yes"
  check_contains "orphan reconciliation is idempotent" "$(sync_config)" "Already up to date."
}

t_codex_config_merges_declared_keys() {
  mkdir -p "$HOME/.codex"
  cat > "$HOME/.codex/config.toml" <<'EOF'
notify = ["client", "turn-ended"]
sandbox_mode = "danger-full-access"

# Written by Codex and the ChatGPT desktop app.
[projects."/some/repo"]
trust_level = "trusted"
EOF
  local app_owned_before
  app_owned_before=$(sed -n '/^# Written by Codex/,$p' "$HOME/.codex/config.toml")
  sync_config > /dev/null
  local merged="$(<"$HOME/.codex/config.toml")"
  check_contains "a declared key is replaced" "$merged" 'sandbox_mode = "workspace-write"'
  check_lacks "the previous declared value is removed" "$merged" 'danger-full-access'
  check_contains "an undeclared top-level key survives" "$merged" 'notify = ["client", "turn-ended"]'
  check_equals "the application-owned table remains byte-for-byte" \
    "$(sed -n '/^# Written by Codex/,$p' "$HOME/.codex/config.toml")" "$app_owned_before"
  local first_merge="$tmp/first-codex-merge.toml"
  cp "$HOME/.codex/config.toml" "$first_merge"
  check_contains "a repeated merge changes nothing" "$(sync_config)" "Already up to date."
  check_files_equal "a repeated merge preserves the config byte-for-byte" \
    "$HOME/.codex/config.toml" "$first_merge"
}

t_codex_config_warns_when_approval_policy_is_never() {
  mkdir -p "$HOME/.codex"
  print -r -- 'approval_policy = "never"' > "$HOME/.codex/config.toml"
  local before="$tmp/codex-config-before-warning.toml" diff_output refresh_output
  cp "$HOME/.codex/config.toml" "$before"

  diff_output="$(diff_config)"
  check_contains "never warns about the Codex GUI behavior" "$diff_output" "Codex GUI"
  check_contains "never identifies the unenforced boundary" "$diff_output" \
    "ASK enforcement is not guaranteed"
  check_contains "never recommends the supported policy" "$diff_output" \
    "Use on-request for the supported configuration."
  check_files_equal "the diagnostic leaves Codex config unchanged" \
    "$HOME/.codex/config.toml" "$before"

  refresh_output="$(refresh_agent_sentinel)"
  check_contains "refresh uses the same Codex policy diagnostic" "$refresh_output" \
    "ASK enforcement is not guaranteed"
  check_files_equal "refresh leaves Codex config unchanged" \
    "$HOME/.codex/config.toml" "$before"
}

t_codex_config_accepts_on_request_approval_policy() {
  mkdir -p "$HOME/.codex"
  print -r -- 'approval_policy = "on-request"' > "$HOME/.codex/config.toml"

  local output
  output="$(diff_config)"
  check_lacks "on-request needs no ASK enforcement warning" "$output" \
    "ASK enforcement is not guaranteed"
}

t_codex_config_warns_when_hooks_are_disabled() {
  mkdir -p "$HOME/.codex"
  print -r -- $'approval_policy = "on-request"\n\n[features]\nhooks = false' \
    > "$HOME/.codex/config.toml"

  local output
  output="$(diff_config)"
  check_contains "disabled hooks use the Codex configuration diagnostic" "$output" \
    "Codex hooks are disabled in config.toml"
}

t_codex_config_rejects_invalid_toml() {
  mkdir -p "$HOME/.codex"
  print -r -- 'sandbox_mode = "unterminated' > "$HOME/.codex/config.toml"
  local before="$(<"$HOME/.codex/config.toml")" exit_status
  sync_config > /dev/null
  exit_status=$?
  check_equals "an invalid config fails the sync" "$exit_status" "1"
  check_equals "a failed merge leaves the installed file unchanged" \
    "$(<"$HOME/.codex/config.toml")" "$before"
}

t_codex_config_rejects_a_table_conflict() {
  mkdir -p "$HOME/.codex"
  print -r -- $'[sandbox_mode]\nmode = "application-owned"' > "$HOME/.codex/config.toml"
  local before="$(<"$HOME/.codex/config.toml")" exit_status
  sync_config > /dev/null
  exit_status=$?
  check_equals "a table at a managed key fails the sync" "$exit_status" "1"
  check_equals "a conflicting table remains unchanged" \
    "$(<"$HOME/.codex/config.toml")" "$before"
}

t_instructions_are_shared_then_specific() {
  sync_config > /dev/null
  local expected="$tmp/expected-instructions.md" source
  for pair in "$HOME/.claude/CLAUDE.md:config/claude" "$HOME/.codex/AGENTS.md:config/codex"; do
    { cat "$REPO/config/agents/instructions.md"; echo; cat "$REPO/${pair#*:}/instructions.md" } > "$expected"
    check_files_equal "${pair%%:*} is the shared file then ${pair#*:}/instructions.md" \
      "${pair%%:*}" "$expected"
  done
  for source in agents claude codex; do
    check_equals "config/$source/instructions.md ends with a newline" \
      "$(tail -c1 "$REPO/config/$source/instructions.md" | xxd -p)" "0a"
  done
  check_lacks "codex does not get the Claude rules" \
    "$(<"$HOME/.codex/AGENTS.md")" "$(head -1 "$REPO/config/claude/instructions.md")"
}

t_project_instructions_reach_each_agent() {
  check_contains "CLAUDE.md imports AGENTS.md" "$(<"$REPO/CLAUDE.md")" "@AGENTS.md"
  check_contains "the Codex project scope carries instructions" \
    "$(<"$REPO/.codex/config.toml")" "developer_instructions"
  local shared_section
  shared_section=$(grep -m1 '^## ' "$REPO/AGENTS.md")
  check_contains "AGENTS.md has a section to compare against" "$shared_section" "## "
  check_lacks "shared sections are not duplicated into CLAUDE.md" \
    "$(<"$REPO/CLAUDE.md")" "$shared_section"
}

t_claude_installer_fallback_uses_the_pin() {
  stub claude <<'STUB'
#!/bin/zsh
case "$1" in
  --version)
    [[ -f "$STUB_STATE/claude-version" ]] && cat "$STUB_STATE/claude-version" || print 0.0.0
    ;;
  install)
    print -r -- "$*" > "$STUB_STATE/claude-install-args"
    exit 1
    ;;
esac
STUB
  stub curl <<'STUB'
#!/bin/zsh
cat <<'INSTALLER'
#!/bin/sh
printf '%s\n' "$#" > "$STUB_STATE/claude-installer-argc"
printf '%s\n' "$*" > "$STUB_STATE/claude-installer-args"
printf '%s\n' "$1" > "$STUB_STATE/claude-version"
INSTALLER
STUB

  local version="$(<"$REPO/config/claude/version")" output exit_status
  output="$(make -s -C "$REPO" install-claude 2>&1)"
  exit_status=$?

  check_equals "the fallback installation succeeds" "$exit_status" "0"
  check_equals "the regular installer receives the pin" \
    "$(<"$STUB_STATE/claude-install-args")" "install $version"
  check_equals "the fallback receives one argument" \
    "$(<"$STUB_STATE/claude-installer-argc")" "1"
  check_equals "the fallback receives the pin" \
    "$(<"$STUB_STATE/claude-installer-args")" "$version"
}

t_claude_installer_rejects_a_version_mismatch() {
  stub claude <<'STUB'
#!/bin/zsh
case "$1" in
  --version)
    [[ -f "$STUB_STATE/claude-version" ]] && cat "$STUB_STATE/claude-version" || print 0.0.0
    ;;
  install) exit 1 ;;
esac
STUB
  stub curl <<'STUB'
#!/bin/zsh
cat <<'INSTALLER'
#!/bin/sh
printf '%s\n' 9.9.9 > "$STUB_STATE/claude-version"
INSTALLER
STUB

  local version="$(<"$REPO/config/claude/version")" output exit_status
  output="$(make -s -C "$REPO" install-claude 2>&1)"
  exit_status=$?

  check_equals "a mismatched installed version fails" "$exit_status" "2"
  check_contains "the mismatch identifies both versions" "$output" \
    "Error: installed Claude Code version 9.9.9, expected $version"
}

t_update_converges_after_homebrew_installs_prerequisites() {
  local original_path="$PATH" staged="$STUB_STATE/homebrew-stubs"
  local original_test_root="$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT"
  local jq_path="$(command -v jq)" output exit_status expected_order actual_order
  mkdir -p "$staged"
  cp "$STUB_BIN/brew" "$staged/original-brew"
  cp "$STUB_BIN/uv" "$staged/uv"
  cp "$STUB_BIN/code" "$staged/code"

  stub fnm <<'STUB'
#!/bin/zsh
case "$1" in
  env) exit 0 ;;
  list)
    [[ -f "$STUB_STATE/node-default" ]] && \
      print "v$(<$STUB_STATE/node-default) default"
    ;;
  install)
    print fnm >> "$STUB_STATE/update-order"
    print -r -- "$2" > "$STUB_STATE/node-version"
    cp "$STUB_STATE/homebrew-stubs/npm" "$STUB_BIN/npm"
    chmod +x "$STUB_BIN/npm"
    ;;
  default) print -r -- "$2" > "$STUB_STATE/node-default" ;;
esac
exit 0
STUB
  stub npm <<'STUB'
#!/bin/zsh
[[ -f "$STUB_STATE/node-default" ]] || exit 2
case "$1" in
  ls) print '{}' ;;
  install)
    case "$3" in
      ntn@*) print ntn >> "$STUB_STATE/update-order" ;;
      @openai/codex@*) print codex >> "$STUB_STATE/update-order" ;;
    esac
    ;;
esac
exit 0
STUB
  stub sheldon <<'STUB'
#!/bin/zsh
exit 0
STUB
  cp "$STUB_BIN/fnm" "$staged/fnm"
  cp "$STUB_BIN/npm" "$staged/npm"
  cp "$STUB_BIN/sheldon" "$staged/sheldon"
  rm -f "$STUB_BIN/fnm" "$STUB_BIN/npm" "$STUB_BIN/uv" "$STUB_BIN/code" \
    "$STUB_BIN/sheldon"

  stub brew <<'STUB'
#!/bin/zsh
case "$1" in
  trust)
    if [[ "${2:-}" == "--json" ]]; then
      print '[]'
    else
      print brew-trust >> "$STUB_STATE/update-order"
    fi
    ;;
  bundle)
    print brew-bundle >> "$STUB_STATE/update-order"
    for command in fnm uv code sheldon; do
      cp "$STUB_STATE/homebrew-stubs/$command" "$STUB_BIN/$command"
      chmod +x "$STUB_BIN/$command"
    done
    ;;
  cleanup) print brew-cleanup >> "$STUB_STATE/update-order" ;;
esac
exit 0
STUB
  ln -sf "$jq_path" "$STUB_BIN/jq"
  : > "$STUB_STATE/update-order-enabled"
  PATH="$STUB_BIN:/usr/bin:/bin"
  select_config_tools_test_root "$HOME/config-tools-root"
  hash -r

  check_nonzero "fnm is unavailable before Homebrew bundle" \
    "$(command -v fnm >/dev/null 2>&1; print $?)"
  check_nonzero "uv is unavailable before Homebrew bundle" \
    "$(command -v uv >/dev/null 2>&1; print $?)"
  check_nonzero "code is unavailable before Homebrew bundle" \
    "$(command -v code >/dev/null 2>&1; print $?)"

  output="$(make -s -j4 -C "$REPO" update \
    "INSTALL_STEPS=install-node install-ntn install-codex" 2>&1)"
  exit_status=$?

  PATH="$original_path"
  select_config_tools_test_root "$original_test_root"
  hash -r
  cp "$staged/original-brew" "$STUB_BIN/brew"
  cp "$staged/uv" "$STUB_BIN/uv"
  cp "$staged/code" "$STUB_BIN/code"
  rm -f "$STUB_BIN/fnm" "$STUB_BIN/npm"

  expected_order=$'brew-trust\nbrew-bundle\nuv-tools\nconfig-tools\ncode\nfnm\nntn\ncodex\nbrew-cleanup'
  actual_order="$(<$STUB_STATE/update-order)"
  check_equals "one parallel update succeeds" "$exit_status" "0"
  check_equals "update preserves prerequisite order under parallel make" \
    "$actual_order" "$expected_order"
  check_equals "the pinned Node version is installed" \
    "$(<$STUB_STATE/node-version)" "$(<$REPO/config/fnm/version)"
  check_equals "the pinned Node version becomes the default" \
    "$(<$STUB_STATE/node-default)" "$(<$REPO/config/fnm/version)"
  check_equals "uv tools are installed after uv becomes available" \
    "$([[ -s "$STUB_STATE/uv-tool-installs" ]] && print yes || print no)" "yes"
  check_equals "fresh convergence ignores a same-named PATH command" \
    "$([[ ! -e "$STUB_STATE/external-config-python" ]] && print yes || print no)" "yes"
  check_equals "VSCode extensions are installed after code becomes available" \
    "$(sort -u "$STUB_STATE/vscode-extensions" | wc -l | tr -d ' ')" \
    "$(grep -Ev '^[[:space:]]*(#|$)' "$REPO/config/vscode/extensions.txt" | wc -l | tr -d ' ')"
  check_lacks "update reports no missing Homebrew prerequisite" "$output" "not found"
}

t_tap_trust_failure_stops_update() {
  : > "$STUB_STATE/brew-trust-fails"
  local output exit_status

  output="$(make_update_with_steps "")"
  exit_status=$?

  check_nonzero "a tap trust failure fails make update" "$exit_status"
  check_contains "the failed tap is identified" "$output" \
    "Error: failed to trust hashicorp/tap"
  check_lacks "Homebrew bundle does not run after failed trust" "$output" \
    "Installing uv tool:"
}

t_uv_tool_failure_stops_update() {
  : > "$STUB_STATE/uv-tool-install-fails"
  local output exit_status

  output="$(make_update_with_steps "")"
  exit_status=$?

  check_nonzero "a uv tool failure fails make update" "$exit_status"
  check_lacks "config sync does not run after a failed uv tool" "$output" "Synced:"
}

t_claude_plugin_install_failure_stops_update() {
  stub claude <<'STUB'
#!/bin/zsh
case "$1 $2" in
  "plugin install") exit 2 ;;
  "plugin list") print '[]' ;;
esac
exit 0
STUB
  local output exit_status

  output="$(make_update_with_steps "sync-claude-plugins")"
  exit_status=$?

  check_nonzero "a Claude plugin install failure fails make update" "$exit_status"
  check_contains "the failed plugin was attempted" "$output" \
    "Installing plugin: code-review@claude-plugins-official"
}

t_claude_plugin_uninstall_failure_stops_update() {
  mkdir -p "$HOME/.claude"
  print -r -- '{"enabledPlugins":{"code-review@claude-plugins-official":true,"context7@claude-plugins-official":true,"playwright@claude-plugins-official":true}}' \
    > "$HOME/.claude/settings.json"
  stub claude <<'STUB'
#!/bin/zsh
case "$1 $2" in
  "plugin list") print '[{"scope":"user","id":"orphan@example"}]' ;;
  "plugin uninstall") exit 2 ;;
esac
exit 0
STUB
  local output exit_status

  output="$(make_update_with_steps "sync-claude-plugins")"
  exit_status=$?

  check_nonzero "a Claude plugin uninstall failure fails make update" "$exit_status"
  check_contains "the orphaned plugin was attempted" "$output" \
    "Uninstalling plugin: orphan@example"
}

t_claude_plugins_update_only_during_upgrade() {
  write_enabled_claude_plugins
  stub claude <<'STUB'
#!/bin/zsh
print -r -- "$*" >> "$STUB_STATE/claude-plugin-calls"
[[ "$1 $2" == "plugin list" ]] && print '[]'
exit 0
STUB
  local install_output install_status update_output update_status
  local upgrade_output upgrade_status expected="$STUB_STATE/expected-plugin-calls"

  install_output="$(make_install_with_steps "sync-claude-plugins")"
  install_status=$?
  update_output="$(make -s -j4 -C "$REPO" update \
    "INSTALL_STEPS=sync-claude-plugins" 2>&1)"
  update_status=$?

  check_equals "make install succeeds" "$install_status" "0"
  check_equals "make update succeeds" "$update_status" "0"
  check_lacks "make install does not update plugins" "$install_output" \
    "Updating plugin:"
  check_lacks "make update does not update plugins" "$update_output" \
    "Updating plugin:"
  check_lacks "regular convergence never invokes plugin update" \
    "$(<$STUB_STATE/claude-plugin-calls)" "plugin update"

  : > "$STUB_STATE/claude-plugin-calls"
  print -r -- "plugin list --json" > "$expected"
  while IFS= read -r plugin || [[ -n "$plugin" ]]; do
    [[ -z "$plugin" ]] && continue
    print -r -- "plugin update $plugin" >> "$expected"
  done < "$REPO/config/claude/plugins.txt"

  upgrade_output="$(make_upgrade_apply_with_steps \
    "sync-claude-plugins update-claude-plugins")"
  upgrade_status=$?

  check_equals "parallel make upgrade-apply succeeds" "$upgrade_status" "0"
  check_files_equal "upgrade reconciles before updating every declared plugin in order" \
    "$STUB_STATE/claude-plugin-calls" "$expected"
  check_contains "upgrade reports the enabled plugin update" "$upgrade_output" \
    "Updating plugin: code-review@claude-plugins-official"
}

t_claude_plugin_update_failure_stops_upgrade() {
  write_enabled_claude_plugins
  stub claude <<'STUB'
#!/bin/zsh
print -r -- "$*" >> "$STUB_STATE/claude-plugin-calls"
case "$1 $2" in
  "plugin list") print '[]' ;;
  "plugin update")
    [[ "$3" == "context7@claude-plugins-official" ]] && exit 2
    ;;
esac
exit 0
STUB
  stub fnm <<'STUB'
#!/bin/zsh
[[ "$1" == "env" ]] && exit 0
exit 0
STUB
  stub npm <<'STUB'
#!/bin/zsh
print -r -- "$*" >> "$STUB_STATE/npm-calls"
exit 0
STUB
  local output exit_status

  output="$(make_upgrade_apply_with_steps \
    "sync-claude-plugins update-claude-plugins install-codex")"
  exit_status=$?

  check_nonzero "a Claude plugin update failure fails upgrade-apply" "$exit_status"
  check_contains "the failing declared plugin is attempted" \
    "$(<$STUB_STATE/claude-plugin-calls)" \
    "plugin update context7@claude-plugins-official"
  check_lacks "later declared plugins are not attempted after a failure" \
    "$(<$STUB_STATE/claude-plugin-calls)" \
    "plugin update playwright@claude-plugins-official"
  check_equals "later upgrade steps do not start after a plugin failure" \
    "$([[ ! -e "$STUB_STATE/npm-calls" ]] && print yes || print no)" "yes"
  check_contains "the failed update is reported" "$output" \
    "Updating plugin: context7@claude-plugins-official"
}

t_node_failure_stops_update() {
  stub fnm <<'STUB'
#!/bin/zsh
case "$1" in
  env) exit 0 ;;
  list) exit 0 ;;
  install) exit 2 ;;
esac
exit 0
STUB
  local output exit_status

  output="$(make_update_with_steps "install-node")"
  exit_status=$?

  check_nonzero "a Node install failure fails make update" "$exit_status"
  check_contains "the failed Node installation was attempted" "$output" \
    "Installing Node v$(<"$REPO/config/fnm/version")"
}

t_ntn_failure_stops_update() {
  stub fnm <<'STUB'
#!/bin/zsh
[[ "$1" == "env" ]] && exit 0
exit 0
STUB
  stub ntn <<'STUB'
#!/bin/zsh
print 0.0.0
STUB
  stub npm <<'STUB'
#!/bin/zsh
[[ "$1" == "install" ]] && exit 2
exit 0
STUB
  local output exit_status

  output="$(make_update_with_steps "install-ntn")"
  exit_status=$?

  check_nonzero "an ntn install failure fails make update" "$exit_status"
  check_contains "the failed ntn installation was attempted" "$output" \
    "Installing Notion CLI (ntn) $(<"$REPO/config/ntn/version")"
}

t_vscode_extension_failure_stops_update_once() {
  : > "$STUB_STATE/vscode-extension-install-fails"
  local output exit_status attempts

  output="$(make_update_with_steps "")"
  exit_status=$?
  attempts=$(wc -l < "$STUB_STATE/vscode-extension-attempts" | tr -d ' ')

  check_nonzero "a VSCode extension failure fails make update" "$exit_status"
  check_equals "the failed extension is attempted once" "$attempts" "1"
  check_contains "the failed extension is identified" "$output" \
    "Installing VSCode extension: kaiwood.center-editor-window"
}

run "invalid modes are rejected"             t_invalid_modes_are_rejected
run "diff uses prepared config Python"       t_diff_uses_prepared_config_python
run "unmanaged config tools are rejected"    t_config_tools_reject_unmanaged_directory
run "invalid config tools are repaired"      t_config_tools_repair_invalid_environments
run "diff after sync is clean"               t_diff_after_sync_is_clean
run "sync is idempotent"                     t_sync_is_idempotent
run "iTerm profile migration preserves local values" t_iterm_profile_migrates_without_overwriting_local_values
run "iTerm profile changes are three-way merged" t_iterm_profile_three_way_merge_preserves_local_changes
run "Claude script orphans are removed"       t_claude_script_orphans_are_removed
run "sync requires agent-sentinel"           t_sync_requires_agent_sentinel
run "agent-sentinel config is synced"        t_agent_sentinel_config_is_synced
run "Codex hook trust follows definitions"   t_codex_hook_trust_notice_tracks_definition_changes
run "Codex rule changes need no hook trust"  t_codex_hook_trust_notice_ignores_rule_changes
run "Codex hook trust precedes later failures" t_codex_hook_trust_notice_precedes_later_failures
run "refresh reports pending hook changes"   t_refresh_reports_only_pending_hook_changes
run "sync rejects a missing sentinel hook"   t_sync_rejects_missing_sentinel_hook
run "sync rejects default-allow rules"       t_sync_rejects_default_allow_rule
run "sync rejects explicit allow rules"       t_sync_rejects_explicit_allow_rule
run "sync rejects missing sentinel rules"    t_sync_rejects_missing_sentinel_rules
run "update migrates legacy sentinel once"   t_update_migrates_legacy_sentinel_once
run "failed sentinel install stops update"   t_update_stops_before_sync_when_sentinel_install_fails
run "refresh upgrades agent-sentinel"        t_refresh_requests_agent_sentinel_upgrade
run "codex skills are synced"                t_codex_skills_are_synced
run "codex skill name collisions are rejected" t_codex_skill_name_collisions_are_rejected
run "codex skill file collisions are rejected" t_codex_skill_file_collisions_are_rejected
run "codex skill orphans are scoped"         t_codex_skill_orphans_are_scoped
run "codex config merges declared keys"      t_codex_config_merges_declared_keys
run "codex config warns for never approvals" t_codex_config_warns_when_approval_policy_is_never
run "codex config accepts on-request"         t_codex_config_accepts_on_request_approval_policy
run "codex config warns for disabled hooks"   t_codex_config_warns_when_hooks_are_disabled
run "codex config rejects invalid TOML"      t_codex_config_rejects_invalid_toml
run "codex config rejects a table conflict"  t_codex_config_rejects_a_table_conflict
run "instructions are shared then specific"  t_instructions_are_shared_then_specific
run "project instructions reach each agent"  t_project_instructions_reach_each_agent
run "Claude fallback uses the pin"            t_claude_installer_fallback_uses_the_pin
run "Claude install verifies the pin"         t_claude_installer_rejects_a_version_mismatch
run "update converges after Homebrew bundle"  t_update_converges_after_homebrew_installs_prerequisites
run "failed tap trust stops update"           t_tap_trust_failure_stops_update
run "failed uv tool stops update"             t_uv_tool_failure_stops_update
run "failed plugin install stops update"      t_claude_plugin_install_failure_stops_update
run "failed plugin uninstall stops update"    t_claude_plugin_uninstall_failure_stops_update
run "plugins update only during upgrade"      t_claude_plugins_update_only_during_upgrade
run "failed plugin update stops upgrade"      t_claude_plugin_update_failure_stops_upgrade
run "failed Node install stops update"        t_node_failure_stops_update
run "failed ntn install stops update"         t_ntn_failure_stops_update
run "failed VSCode extension stops once"      t_vscode_extension_failure_stops_update_once

print
print "$pass passed, $fail failed"
(( fail == 0 ))
