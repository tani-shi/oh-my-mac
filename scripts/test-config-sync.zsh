#!/bin/zsh
set -u

REPO="${0:A:h}/.."
[[ -f "$REPO/config.zsh" ]] || { print -u2 "missing $REPO/config.zsh"; exit 1 }

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
run "codex config merges declared keys"      t_codex_config_merges_declared_keys
run "codex config rejects invalid TOML"      t_codex_config_rejects_invalid_toml
run "codex config rejects a table conflict"  t_codex_config_rejects_a_table_conflict
run "instructions are shared then specific"  t_instructions_are_shared_then_specific
run "project instructions reach each agent"  t_project_instructions_reach_each_agent

print
print "$pass passed, $fail failed"
(( fail == 0 ))
