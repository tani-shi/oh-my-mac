#!/bin/zsh
set -u

REPO="${0:A:h}/.."
[[ -f "$REPO/config.zsh" ]] || { print -u2 "missing $REPO/config.zsh"; exit 1 }
REAL_UV=$(command -v uv)
export REAL_UV

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export STUB_STATE="$tmp/stub-state"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$(uv cache dir)}"
export UV_NO_PROGRESS=1
mkdir -p "$STUB_STATE"

stub() {
  cat > "$tmp/bin/$1"
  chmod +x "$tmp/bin/$1"
}

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
  --list-extensions) [[ -f "$store" ]] && cat "$store" ;;
  --install-extension) print -r -- "$2" >> "$store" ;;
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
      jq --arg command 'agent-sentinel --host codex' \
        --argjson sentinel '{"matcher":"*","hooks":[{"type":"command","command":"agent-sentinel --host codex"}]}' '
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
    else
      print -r -- $'prefix_rule(\n    pattern = ["ssh"],\n    decision = "prompt",\n)' \
        > "$rules_path"
    fi
  fi
fi
exit 0
STUB

stub uv <<'STUB'
#!/bin/zsh
case "$1" in
  run)
    exec "$REAL_UV" "$@"
    ;;
  tool)
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
        fi
        exit 0
        ;;
    esac
    ;;
  *)
    exec "$REAL_UV" "$@"
    ;;
esac
STUB

stub brew <<'STUB'
#!/bin/zsh
if [[ "$1" == "trust" && "${2:-}" == "--json" ]]; then
  print '[]'
fi
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
make_update() { make -s -C "$REPO" update INSTALL_STEPS= 2>&1 }
make_refresh_install() {
  make -s -C "$REPO" install-uv-tools AGENT_SENTINEL_UPGRADE=1 2>&1
}

t_diff_writes_nothing() {
  diff_config > /dev/null
  check_equals "HOME untouched" "$(find "$HOME" -mindepth 1 | wc -l | tr -d ' ')" "0"
}

t_diff_after_sync_is_clean() {
  sync_config > /dev/null
  check_contains "second pass reports nothing" "$(diff_config)" "No differences found."
}

t_sync_is_idempotent() {
  sync_config > /dev/null
  check_contains "second sync changes nothing" "$(sync_config)" "Already up to date."
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

  second_output="$(make_update)"
  check_contains "the second update leaves config unchanged" "$second_output" \
    "Already up to date."
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

run "diff writes nothing"                    t_diff_writes_nothing
run "diff after sync is clean"               t_diff_after_sync_is_clean
run "sync is idempotent"                     t_sync_is_idempotent
run "sync requires agent-sentinel"           t_sync_requires_agent_sentinel
run "agent-sentinel config is synced"        t_agent_sentinel_config_is_synced
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
run "codex config rejects invalid TOML"      t_codex_config_rejects_invalid_toml
run "codex config rejects a table conflict"  t_codex_config_rejects_a_table_conflict
run "instructions are shared then specific"  t_instructions_are_shared_then_specific
run "project instructions reach each agent"  t_project_instructions_reach_each_agent

print
print "$pass passed, $fail failed"
(( fail == 0 ))
