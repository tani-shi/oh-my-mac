#!/bin/zsh
set -eu

cd "$(git rev-parse --show-toplevel)"

if git diff --quiet && git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

changed_packages=()
if ! git diff --quiet -- versions.json; then
  versions_diff=$(git diff -- versions.json)

  local -A old_versions
  while IFS= read -r line; do
    if [[ "$line" =~ '^\-[[:space:]]+"([^"]+)":[[:space:]]+"([^"]+)"' ]]; then
      old_versions[${match[1]}]=${match[2]}
    fi
  done <<< "$versions_diff"

  while IFS= read -r line; do
    if [[ "$line" =~ '^\+[[:space:]]+"([^"]+)":[[:space:]]+"([^"]+)"' ]]; then
      local pkg=${match[1]}
      [[ "$pkg" == "_generated" ]] && continue
      if (( ${+old_versions[$pkg]} )); then
        changed_packages+=("$pkg")
      fi
    fi
  done <<< "$versions_diff"
fi

if ! git diff --quiet -- config/claude/version 2>/dev/null; then
  changed_packages+=("claude")
fi

changed_packages=(${(u)changed_packages})

if (( ${#changed_packages} == 0 )); then
  msg="chore: upgrade dependencies"
else
  pkg_list="${(j:, :)changed_packages}"
  msg="chore: upgrade $pkg_list"
fi

git add -A
git commit -m "$msg"
echo "Committed: $msg"
