#!/bin/zsh
set -eu

zmodload zsh/datetime

KEEP_DAYS="${GIT_DISCARD_KEEP_DAYS:-30}"
KEEP_MIN="${GIT_DISCARD_KEEP_MIN:-20}"

die() {
  print -u2 "git discard: $1"
  exit 1
}

usage() {
  print "usage: git discard [--source=<rev>] [<pathspec>...]"
  print "       git discard --untracked [<pathspec>...]"
  print "       git discard --hard [<commit>]"
  print "       git discard --list"
  print "       git discard --undo [<ref>] [-- <pathspec>...]"
}

# GIT_PREFIX is empty both at the repository top level and outside a repository,
# so it cannot stand in for this guard.
git rev-parse --is-inside-work-tree &>/dev/null || die "not inside a git working tree"

# A `!` alias runs at the repository top level and reports the caller's location
# in GIT_PREFIX. Returning to it lets git resolve pathspecs exactly as a plain
# `git restore` would, including magic forms like `:(exclude)`.
[[ -n "${GIT_PREFIX:-}" ]] && cd "$GIT_PREFIX"

SNAP_REF=""
SOURCE_REV=HEAD

require_head() {
  git rev-parse --verify -q HEAD >/dev/null \
    || die "no commits yet; nothing to restore to (use --untracked)"
}

# Recording the baseline lets --undo tell a path the discard wrote from one
# edited afterwards. The blank line keeps it out of the subject, which --list
# prints.
snapshot_message() {
  print -r -- "git discard: $1"
  print
  print -r -- "source: $2"
}

baseline_of() {
  git log -1 --format=%B "$1" | sed -n 's/^source: //p'
}

snapshot() {
  require_head
  [[ -z "$(git ls-files --unmerged)" ]] \
    || die "unresolved conflicts; run git merge --abort or git rebase --abort"
  local sha
  sha=$(git stash create "$(snapshot_message "$1" "$2")")
  [[ -n "$sha" ]] || return 0
  # Milliseconds keep the name strictly increasing, so refname order is creation
  # order; committer dates collide within a second and sort arbitrarily.
  local now=$EPOCHREALTIME
  SNAP_REF="refs/discard/$(strftime '%Y%m%d-%H%M%S' ${now%.*})-${${now#*.}:0:3}-${sha:0:7}"
  git update-ref -m "git discard: $1" "$SNAP_REF" "$sha"
  print "Snapshot:  $SNAP_REF"
}

retention_enabled() { (( KEEP_DAYS > 0 )); }

prune() {
  retention_enabled || return 0
  local -a newest_first
  newest_first=(${(f)"$(git for-each-ref --sort=-refname \
    --format='%(refname) %(committerdate:unix)' refs/discard)"})
  local -a beyond_keep_min=("${(@)newest_first[KEEP_MIN+1,-1]}")
  local cutoff=$(( EPOCHSECONDS - KEEP_DAYS * 86400 )) entry n=0
  for entry in "${beyond_keep_min[@]}"; do
    (( ${entry##* } < cutoff )) || continue
    git update-ref -d "${entry%% *}"
    n=$(( n + 1 ))
  done
  if (( n > 0 )); then
    print "Pruned:    $n snapshot(s) older than ${KEEP_DAYS}d"
  fi
}

resolve_ref() {
  local r="$1"
  if [[ -z "$r" ]]; then
    r=$(git for-each-ref --sort=-refname --count=1 --format='%(refname)' refs/discard)
    [[ -n "$r" ]] || die "no snapshots"
  elif git rev-parse --verify -q "refs/discard/$r^{commit}" >/dev/null; then
    r="refs/discard/$r"
  fi
  git rev-parse --verify -q "$r^{commit}" >/dev/null || die "unknown snapshot: $1"
  print "$r"
}

discard_tree() {
  require_head
  local rev="$SOURCE_REV"
  local src
  src=$(git rev-parse --verify -q "$rev^{commit}") || die "not a commit: $rev"

  local -a paths
  paths=("${@:-:/}")
  local n
  n=$(git diff --name-only "$src" -- "${paths[@]}" | wc -l | tr -d ' ')
  if [[ "$n" == "0" ]]; then
    print "Nothing to discard."
    return 0
  fi
  snapshot "${(j: :)paths}${${rev:#HEAD}:+ (source: $rev)}" "$src"
  git restore --source="$src" --staged --worktree -- "${paths[@]}"
  print "Discarded: $n file(s)"
  if [[ -n "$SNAP_REF" ]]; then
    print "Undo:      git discard --undo $SNAP_REF"
  else
    # A clean tree needs no snapshot: everything overwritten is still in HEAD.
    print "Undo:      git discard -- ${(j: :)${(q-)paths[@]}}"
  fi
  prune
}

discard_untracked() {
  local -a paths files
  paths=("${@:-:/}")
  files=(${(0)"$(git ls-files -z --others --exclude-standard --directory -- "${paths[@]}")"})
  if (( ${#files} == 0 )); then
    print "Nothing untracked to discard."
    return 0
  fi
  # trash(1) takes no `--` terminator, so `./` keeps a leading-dash filename out
  # of its option parsing.
  trash "${files[@]/#/./}"
  print "Trashed:   ${#files} path(s)"
  print "Undo:      restore from Finder Trash (Put Back)"
}

discard_hard() {
  local target="${1:-HEAD}"
  [[ "$target" != -* ]] || die "invalid commit: $target"
  git rev-parse --verify -q "$target^{commit}" >/dev/null || die "not a commit: $target"
  local head
  head=$(git rev-parse --short HEAD)
  snapshot "--hard $target" "$(git rev-parse HEAD)"
  if [[ -z "$SNAP_REF" && "$(git rev-parse "$target^{commit}")" == "$(git rev-parse HEAD)" ]]; then
    print "Nothing to discard."
    return 0
  fi
  git reset --hard "$target" >/dev/null
  local now
  now=$(git rev-parse --short HEAD)
  print "Reset:     $now (was $head)"
  if [[ "$now" == "$head" ]]; then
    print "Undo:      git discard --undo $SNAP_REF"
  elif [[ -n "$SNAP_REF" ]]; then
    print "Undo:      git reset --hard $head && git discard --undo $SNAP_REF"
  else
    print "Undo:      git reset --hard $head"
  fi
  prune
}

undo() {
  local ref=""
  if [[ -n "${1:-}" && "$1" != "--" ]]; then
    ref="$1"
    shift
  fi
  [[ "${1:-}" != "--" ]] || shift
  ref=$(resolve_ref "$ref")

  local -a paths skipped
  if (( $# > 0 )); then
    paths=("$@")
  else
    local src
    src=$(baseline_of "$ref")
    src=$(git rev-parse --verify -q "${src:-HEAD}^{commit}") || die "unknown baseline in $ref"
    local -A dirty
    local p
    for p in ${(0)"$(git diff --name-only -z "$src")"}; do
      dirty[$p]=1
    done
    # A snapshot covers the whole tree while a discard may have been scoped, so
    # a path the tree has moved on from since is left alone rather than
    # overwritten with the snapshot's version.
    for p in ${(0)"$(git diff --name-only -z "$src" "$ref")"}; do
      if [[ -n "${dirty[$p]:-}" ]]; then
        skipped+=("$p")
      else
        paths+=("$p")
      fi
    done
    if (( ${#paths} == 0 )); then
      print "Nothing to restore from $ref."
      (( ${#skipped} == 0 )) || print "Skipped:   ${#skipped} path(s) modified since the snapshot"
      return 0
    fi
  fi

  snapshot "--undo $ref" "$(git rev-parse HEAD)"
  git restore --source="$ref" --staged --worktree -- "${paths[@]}"
  print "Restored:  ${#paths} file(s) from $ref"
  (( ${#skipped} == 0 )) || print "Skipped:   ${#skipped} path(s) modified since the snapshot"
  if [[ -n "$SNAP_REF" ]]; then
    print "Undo:      git discard --undo $SNAP_REF"
  fi
}

list() {
  local out
  out=$(git for-each-ref --sort=-refname \
    --format='%(refname)  %(committerdate:format:%Y-%m-%d %H:%M)  %(contents:subject)' refs/discard)
  print "${out:-No snapshots.}"
}

case "${1:-}" in
  --untracked) shift; discard_untracked "$@" ;;
  --hard)      shift; discard_hard "$@" ;;
  --list)      list ;;
  --undo)      shift; undo "$@" ;;
  -h)          usage ;;
  --source=*)  SOURCE_REV="${1#--source=}"; shift; discard_tree "$@" ;;
  --source)    shift; SOURCE_REV="${1:-}"; shift || true; discard_tree "$@" ;;
  --)          shift; discard_tree "$@" ;;
  -*)          die "unknown option: $1" ;;
  *)           discard_tree "$@" ;;
esac
