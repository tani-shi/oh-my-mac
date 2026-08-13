#!/bin/zsh
set -eu

cd "$(git rev-parse --show-toplevel)"

if git diff --quiet && git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

changed_packages=()
for pin in \
  "claude:config/claude/version" \
  "ntn:config/ntn/version" \
  "codex:config/codex/version" \
  "sheldon:config/sheldon/plugins.toml" \
  "uv:config/uv/tools.txt"; do
  if ! git diff --quiet -- "${pin#*:}" || ! git diff --cached --quiet -- "${pin#*:}"; then
    changed_packages+=("${pin%%:*}")
  fi
done

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
