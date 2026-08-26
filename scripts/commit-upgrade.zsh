#!/bin/zsh
set -eu

cd "$(git rev-parse --show-toplevel)"

pins=(
  "claude:config/claude/version" \
  "ntn:config/ntn/version" \
  "sheldon:config/sheldon/plugins.toml" \
  "uv:config/uv/tools.txt"
)
allowed_paths=()
for pin in "${pins[@]}"; do
  allowed_paths+=("${pin#*:}")
done
prepared_state_file="$(git rev-parse --git-path commit-upgrade.prepared)"

cached_fingerprint() {
  git diff --cached --binary -- "${allowed_paths[@]}" | git hash-object --stdin
}

is_allowed_path() {
  local candidate=$1 allowed
  for allowed in "${allowed_paths[@]}"; do
    [[ "$candidate" == "$allowed" ]] && return 0
  done
  return 1
}

typeset -A outside_paths

record_outside_paths() {
  local path
  while IFS= read -r -d '' path; do
    if ! is_allowed_path "$path"; then
      outside_paths[$path]=1
    fi
  done
}

find_outside_paths() {
  outside_paths=()
  record_outside_paths < <(git diff --name-only -z)
  record_outside_paths < <(git diff --cached --name-only -z)
  record_outside_paths < <(git ls-files --others --exclude-standard -z)
}

reject_outside_paths() {
  find_outside_paths
  (( ${#outside_paths} == 0 )) && return 0

  print -u2 "Upgrade commit refused: changes outside the approved files:"
  local path
  for path in ${(ok)outside_paths}; do
    print -u2 -r -- "  $path"
  done
  return 1
}

prepare_commit() {
  rm -f "$prepared_state_file"
  reject_outside_paths
  if ! git diff --cached --quiet; then
    print -u2 "Upgrade commit refused: staged changes already exist."
    return 1
  fi

  git add -- "${allowed_paths[@]}"
  if git diff --cached --quiet; then
    echo "No changes to commit."
    return 0
  fi

  cached_fingerprint > "$prepared_state_file"
  git diff --cached -- "${allowed_paths[@]}"
  echo "Prepared upgrade changes. Review the cached diff before committing."
}

commit_prepared() {
  reject_outside_paths
  if ! git diff --quiet; then
    print -u2 "Upgrade commit refused: approved files changed after preparation."
    return 1
  fi
  if git diff --cached --quiet; then
    rm -f "$prepared_state_file"
    echo "No changes to commit."
    return 0
  fi
  if [[ ! -f "$prepared_state_file" ]]; then
    print -u2 "Upgrade commit refused: run prepare before committing."
    return 1
  fi
  if [[ "$(cached_fingerprint)" != "$(<"$prepared_state_file")" ]]; then
    print -u2 "Upgrade commit refused: staged changes changed after preparation."
    return 1
  fi

  changed_packages=()
  local pin
  for pin in "${pins[@]}"; do
    if ! git diff --cached --quiet -- "${pin#*:}"; then
      changed_packages+=("${pin%%:*}")
    fi
  done

  changed_packages=(${(u)changed_packages})
  pkg_list="${(j:, :)changed_packages}"
  msg="chore: upgrade $pkg_list"

  git commit -m "$msg"
  rm -f "$prepared_state_file"
  echo "Committed: $msg"
}

abort_prepared() {
  if [[ ! -f "$prepared_state_file" ]]; then
    echo "No prepared upgrade changes to abort."
    return 0
  fi

  git restore --staged -- "${allowed_paths[@]}"
  rm -f "$prepared_state_file"
  echo "Aborted the upgrade commit. Working tree changes were preserved."
}

if (( $# != 1 )) || [[ "$1" != "prepare" && "$1" != "commit" && "$1" != "abort" ]]; then
  print -u2 "Usage: $0 prepare|commit|abort"
  exit 1
fi

case "$1" in
  prepare) prepare_commit ;;
  commit) commit_prepared ;;
  abort) abort_prepared ;;
esac
