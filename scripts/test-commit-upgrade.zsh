#!/bin/zsh
set -u

SRC="${0:A:h}/commit-upgrade.zsh"
[[ -f "$SRC" ]] || { print -u2 "missing $SRC"; exit 1 }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

export HOME="$tmp/home"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$HOME"

git config --global init.defaultBranch main

pass=0 fail=0 repo_n=0 current=""

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

new_repo() {
  repo_n=$(( repo_n + 1 ))
  local repo="$tmp/repo$repo_n"
  git init -q "$repo"
  cd "$repo"
  mkdir -p config/{claude,ntn,codex,sheldon,uv}
  print 1.0.0 > config/claude/version
  print 1.0.0 > config/ntn/version
  print 1.0.0 > config/codex/version
  print 'tag = "v1.0.0"' > config/sheldon/plugins.toml
  print 'example@v1.0.0' > config/uv/tools.txt
  print initial > README.md
  git add .
  git commit -qm init
}

run() {
  current="$1"
  new_repo
  "$2"
}

t_commits_only_approved_files() {
  local output
  print 2.0.0 > config/claude/version

  output="$("$SRC" prepare)"
  check_contains "prepare shows the cached diff" "$output" "+2.0.0"
  check_equals "only the pin is staged" "$(git diff --cached --name-only)" \
    "config/claude/version"

  output="$("$SRC" commit)"
  check_contains "commit reports the derived message" "$output" \
    "Committed: chore: upgrade claude"
  check_equals "commit contains only the pin" "$(git diff-tree --no-commit-id --name-only -r HEAD)" \
    "config/claude/version"
}

t_rejects_unstaged_outside_change() {
  local output exit_status
  print 2.0.0 > config/claude/version
  print changed > README.md

  output="$("$SRC" prepare 2>&1)"
  exit_status=$?
  check_equals "prepare fails" "$exit_status" "1"
  check_contains "prepare identifies the outside path" "$output" "README.md"
  check_equals "prepare leaves the index untouched" "$(git diff --cached --name-only)" ""
}

t_rejects_untracked_outside_change() {
  local output exit_status
  print 2.0.0 > config/claude/version
  print private > unrelated-untracked.txt

  output="$("$SRC" prepare 2>&1)"
  exit_status=$?
  check_equals "prepare fails" "$exit_status" "1"
  check_contains "prepare identifies the untracked path" "$output" \
    "unrelated-untracked.txt"
  check_equals "prepare leaves the pin unstaged" "$(git diff --cached --name-only)" ""
}

t_rejects_staged_outside_change_without_mutation() {
  local output exit_status
  print changed > README.md
  git add README.md
  print 2.0.0 > config/claude/version

  output="$("$SRC" prepare 2>&1)"
  exit_status=$?
  check_equals "prepare fails" "$exit_status" "1"
  check_contains "prepare identifies the staged path" "$output" "README.md"
  check_equals "the existing index is preserved" "$(git diff --cached --name-only)" "README.md"
  check_equals "the pin remains unstaged" "$(git diff --name-only -- config/claude/version)" \
    "config/claude/version"
}

t_rejects_changes_after_preparation() {
  local output exit_status
  print 2.0.0 > config/claude/version
  "$SRC" prepare > /dev/null
  print 3.0.0 > config/claude/version

  output="$("$SRC" commit 2>&1)"
  exit_status=$?
  check_equals "commit fails" "$exit_status" "1"
  check_contains "commit reports the changed preparation" "$output" \
    "approved files changed after preparation"
  check_equals "no commit is created" "$(git rev-list --count HEAD)" "1"
}

t_rejects_restaged_changes_after_preparation() {
  local output exit_status
  print 2.0.0 > config/claude/version
  "$SRC" prepare > /dev/null
  print 3.0.0 > config/claude/version
  git add config/claude/version

  output="$("$SRC" commit 2>&1)"
  exit_status=$?
  check_equals "commit fails" "$exit_status" "1"
  check_contains "commit reports the replaced cached diff" "$output" \
    "staged changes changed after preparation"
  check_equals "no commit is created" "$(git rev-list --count HEAD)" "1"
}

t_abort_preserves_working_tree_changes() {
  local output prepared_state_file
  print 2.0.0 > config/claude/version
  "$SRC" prepare > /dev/null
  prepared_state_file="$(git rev-parse --git-path commit-upgrade.prepared)"

  output="$("$SRC" abort)"
  check_contains "abort reports preserved changes" "$output" \
    "Working tree changes were preserved"
  check_equals "abort clears the index" "$(git diff --cached --name-only)" ""
  check_equals "abort preserves the pin change" "$(git diff --name-only)" \
    "config/claude/version"
  check_equals "abort removes the prepared state" \
    "$([[ ! -e "$prepared_state_file" ]] && print yes || print no)" "yes"
}

t_abort_preserves_unrelated_staged_changes() {
  print 2.0.0 > config/claude/version
  "$SRC" prepare > /dev/null
  print changed > README.md
  git add README.md

  "$SRC" abort > /dev/null
  check_equals "abort unstages only the pin" "$(git diff --cached --name-only)" "README.md"
  check_equals "abort preserves the pin change" "$(git diff --name-only -- config/claude/version)" \
    "config/claude/version"
}

t_abort_without_preparation_preserves_index() {
  local output
  print 2.0.0 > config/claude/version
  git add config/claude/version

  output="$("$SRC" abort)"
  check_contains "abort reports no prepared changes" "$output" \
    "No prepared upgrade changes to abort"
  check_equals "abort preserves an independently staged pin" \
    "$(git diff --cached --name-only)" "config/claude/version"
}

t_no_changes_is_a_noop() {
  check_contains "prepare is a no-op" "$("$SRC" prepare)" "No changes to commit."
  check_contains "commit is a no-op" "$("$SRC" commit)" "No changes to commit."
  check_equals "no commit is created" "$(git rev-list --count HEAD)" "1"
}

run "commits only approved files"             t_commits_only_approved_files
run "rejects unstaged outside changes"        t_rejects_unstaged_outside_change
run "rejects untracked outside changes"       t_rejects_untracked_outside_change
run "rejects staged outside changes"          t_rejects_staged_outside_change_without_mutation
run "rejects changes after preparation"       t_rejects_changes_after_preparation
run "rejects restaged prepared changes"        t_rejects_restaged_changes_after_preparation
run "abort preserves working tree changes"     t_abort_preserves_working_tree_changes
run "abort preserves unrelated staged changes" t_abort_preserves_unrelated_staged_changes
run "abort without preparation preserves index" t_abort_without_preparation_preserves_index
run "no changes is a no-op"                   t_no_changes_is_a_noop

print "$pass passed, $fail failed"
(( fail == 0 ))
