#!/bin/zsh
set -u

SRC="${0:A:h}/../config/git/discard.zsh"
[[ -f "$SRC" ]] || { print -u2 "missing $SRC"; exit 1 }

tmp=$(mktemp -d)
# A sandbox created per run is not user data, and trashing one per run would
# pile them up in the Trash.
trap 'rm -rf "$tmp"' EXIT INT TERM

export HOME="$tmp/home"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export TRASH_LOG="$tmp/trashed"
mkdir -p "$HOME" "$tmp/bin"

# The script calls `trash` by name, so a stub earlier in PATH keeps test files
# out of the real Trash without a test-only branch in the script.
cat > "$tmp/bin/trash" <<'STUB'
#!/bin/zsh
print -rl -- "$@" >> "$TRASH_LOG"
rm -rf -- "$@"
STUB
chmod +x "$tmp/bin/trash"
export PATH="$tmp/bin:$PATH"

git config --global init.defaultBranch main
git config --global alias.discard "!zsh $SRC"

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
  local d="$tmp/repo$repo_n"
  git init -q "$d"
  cd "$d"
  print a > f
  mkdir sub
  print A > sub/g
  git add .
  git commit -qm init
}

run() {
  current="$1"
  new_repo
  "$2"
}

snapshot_count() {
  git for-each-ref refs/discard | wc -l | tr -d ' '
}


t_discards_and_restores() {
  print b > f
  git discard f > /dev/null
  check_equals "worktree reset to HEAD" "$(<f)" "a"
  check_equals "snapshot taken" "$(snapshot_count)" "1"
  git discard --undo > /dev/null
  check_equals "undo brings the change back" "$(<f)" "b"
}

t_leaves_other_paths_alone() {
  print b > f
  print B > sub/g
  git discard f > /dev/null
  check_equals "scoped discard" "$(<f)" "a"
  check_equals "other path untouched" "$(<sub/g)" "B"
  git discard --undo > /dev/null
  check_equals "undo restores the discarded path" "$(<f)" "b"
  check_equals "undo leaves the dirty path" "$(<sub/g)" "B"
}

t_undo_skips_paths_edited_since() {
  print b > f
  git discard f > /dev/null
  print later > f
  local out
  out=$(git discard --undo 2>&1)
  check_equals "worktree keeps the newer edit" "$(<f)" "later"
  check_contains "skip is reported" "$out" "Skipped:"
}

t_relative_pathspec_from_subdir() {
  print b > f
  print B > sub/g
  cd sub
  git discard g > /dev/null
  check_equals "pathspec resolves against the caller's directory" "$(<g)" "A"
  check_equals "path outside the pathspec untouched" "$(<../f)" "b"
}

t_bare_discard_from_subdir_covers_repo() {
  print b > f
  print B > sub/g
  cd sub
  git discard > /dev/null
  check_equals "whole repository reset" "$(<../f)" "a"
  check_equals "including the caller's directory" "$(<g)" "A"
}

t_staged_new_file() {
  print n > new.txt
  git add new.txt
  git discard new.txt > /dev/null
  check_equals "staged addition removed" "$(test -e new.txt && print yes || print no)" "no"
  git discard --undo > /dev/null
  check_equals "undo recreates it" "$(<new.txt)" "n"
  check_equals "restored content comes back staged" "$(git status --porcelain)" "A  new.txt"
}

t_nothing_to_discard() {
  local out
  out=$(git discard 2>&1)
  check_equals "clean tree is a no-op" "$out" "Nothing to discard."
  check_equals "no snapshot taken" "$(snapshot_count)" "0"
}

t_source_on_dirty_tree() {
  print v2 > f
  git commit -qam two
  print uncommitted > f
  git discard --source=HEAD~1 f > /dev/null
  check_equals "reset to the named revision" "$(<f)" "a"
  git discard --undo > /dev/null
  check_equals "undo restores the uncommitted state" "$(<f)" "uncommitted"
}

t_source_on_clean_tree() {
  print v2 > f
  git commit -qam two
  local out
  out=$(git discard --source=HEAD~1 f 2>&1)
  check_equals "reset to the named revision" "$(<f)" "a"
  check_equals "no snapshot needed" "$(snapshot_count)" "0"
  check_contains "undo points back at HEAD" "$out" "Undo:      git discard -- f"
  git discard -- f > /dev/null
  check_equals "following the undo restores HEAD" "$(<f)" "v2"
}

t_source_separate_argument() {
  print v2 > f
  git commit -qam two
  git discard --source HEAD~1 f > /dev/null
  check_equals "separated form parses" "$(<f)" "a"
}

t_untracked() {
  print 'build/' > .gitignore
  git add .gitignore
  git commit -qm ignore
  mkdir build
  print x > build/out
  print u > untracked.txt
  print -- -weird > ./-weird
  git discard --untracked > /dev/null
  check_equals "untracked file removed" "$(test -e untracked.txt && print yes || print no)" "no"
  check_equals "leading-dash name removed" "$(test -e ./-weird && print yes || print no)" "no"
  check_equals "gitignored path kept" "$(<build/out)" "x"
  check_equals "tracked file kept" "$(<f)" "a"
}

t_untracked_when_clean() {
  local out
  out=$(git discard --untracked 2>&1)
  check_equals "no untracked files is a no-op" "$out" "Nothing untracked to discard."
}

t_hard() {
  print v2 > f
  git commit -qam two
  local head_before
  head_before=$(git rev-parse --short HEAD)
  print dirty > f
  local out
  out=$(git discard --hard HEAD~1 2>&1)
  check_equals "worktree follows the reset" "$(<f)" "a"
  check_equals "HEAD moved" "$(git log --oneline -1 | cut -d' ' -f2-)" "init"
  check_contains "undo names the previous head" "$out" "git reset --hard $head_before"
  git reset --hard "$head_before" -q
  git discard --undo > /dev/null
  check_equals "undo restores the uncommitted state" "$(<f)" "dirty"
}

t_list_is_newest_first() {
  print b > f
  git discard f > /dev/null
  print c > f
  git discard f > /dev/null
  local first second
  first=$(git discard --list | head -1 | cut -d' ' -f1)
  second=$(git discard --list | tail -1 | cut -d' ' -f1)
  check_equals "newest snapshot listed first" "$([[ "$first" > "$second" ]] && print yes || print no)" "yes"
}

t_list_when_empty() {
  check_equals "empty list is stated" "$(git discard --list)" "No snapshots."
}

t_prune_keeps_recent_and_minimum() {
  local old stamp i
  old=$(GIT_COMMITTER_DATE="@$(( $(date +%s) - 60 * 86400 )) +0000" \
    git commit-tree HEAD^{tree} -m "old snapshot")
  for i in $(seq -w 1 25); do
    git update-ref "refs/discard/20200101-0000$i-000-abcdef0" "$old"
  done
  print b > f
  git discard f > /dev/null
  check_equals "newest 20 kept" "$(snapshot_count)" "20"
  check_equals "the fresh snapshot survived" \
    "$(git for-each-ref --format='%(refname)' refs/discard | grep -c '^refs/discard/2020' | tr -d ' ')" "19"
}

t_prune_disabled() {
  local old i
  old=$(GIT_COMMITTER_DATE="@$(( $(date +%s) - 60 * 86400 )) +0000" \
    git commit-tree HEAD^{tree} -m "old snapshot")
  for i in $(seq -w 1 25); do
    git update-ref "refs/discard/20200101-0000$i-000-abcdef0" "$old"
  done
  print b > f
  GIT_DISCARD_KEEP_DAYS=0 git discard f > /dev/null
  check_equals "nothing pruned" "$(snapshot_count)" "26"
}

t_rejects_unborn_head() {
  cd "$tmp"
  git init -q norepo_head
  cd norepo_head
  print x > a
  git add a
  local out st
  out=$(git discard 2>&1)
  st=$?
  check_equals "exits non-zero" "$st" "1"
  check_contains "explains why" "$out" "no commits yet"
  check_equals "staged file untouched" "$(<a)" "x"
}

t_rejects_conflicted_index() {
  git switch -qc other
  print other > f
  git commit -qam other
  git switch -q -
  print main > f
  git commit -qam main
  git merge other -q > /dev/null 2>&1
  local out st
  out=$(git discard f 2>&1)
  st=$?
  check_equals "exits non-zero" "$st" "1"
  check_contains "points at the abort commands" "$out" "merge --abort"
  check_equals "conflict left in place" "$(grep -c '<<<<<<<' f)" "1"
}

t_rejects_bad_revision() {
  print b > f
  local out st
  out=$(git discard --source=nope f 2>&1)
  st=$?
  check_equals "exits non-zero" "$st" "1"
  check_contains "names the bad revision" "$out" "not a commit: nope"
  check_equals "worktree untouched" "$(<f)" "b"
}

t_rejects_unknown_option() {
  print b > f
  local out st
  out=$(git discard --bogus 2>&1)
  st=$?
  check_equals "exits non-zero" "$st" "1"
  check_contains "names the option" "$out" "unknown option: --bogus"
  check_equals "worktree untouched" "$(<f)" "b"
}

t_rejects_outside_a_repository() {
  cd "$tmp"
  local out st
  out=$(git discard 2>&1)
  st=$?
  check_equals "exits non-zero" "$st" "1"
  check_contains "explains why" "$out" "not inside a git working tree"
}


if ! zsh -n "$SRC"; then
  print -u2 "FAIL: $SRC does not parse"
  exit 1
fi

run "discards and restores"            t_discards_and_restores
run "leaves other paths alone"         t_leaves_other_paths_alone
run "undo skips paths edited since"    t_undo_skips_paths_edited_since
run "relative pathspec from subdir"    t_relative_pathspec_from_subdir
run "bare discard from subdir"         t_bare_discard_from_subdir_covers_repo
run "staged new file"                  t_staged_new_file
run "nothing to discard"               t_nothing_to_discard
run "--source on a dirty tree"         t_source_on_dirty_tree
run "--source on a clean tree"         t_source_on_clean_tree
run "--source as a separate argument"  t_source_separate_argument
run "--untracked"                      t_untracked
run "--untracked when clean"           t_untracked_when_clean
run "--hard"                           t_hard
run "--list is newest first"           t_list_is_newest_first
run "--list when empty"                t_list_when_empty
run "prune keeps recent and minimum"   t_prune_keeps_recent_and_minimum
run "prune disabled"                   t_prune_disabled
run "unborn HEAD"                      t_rejects_unborn_head
run "conflicted index"                 t_rejects_conflicted_index
run "bad revision"                     t_rejects_bad_revision
run "unknown option"                   t_rejects_unknown_option
run "outside a repository"             t_rejects_outside_a_repository

print
print "$pass passed, $fail failed"
(( fail == 0 ))
