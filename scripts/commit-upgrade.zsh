#!/bin/zsh
set -eu

# Auto-commit after `make upgrade` if there are changes.
# Extracts upgraded package names from versions.json diff for the commit message.

cd "$(git rev-parse --show-toplevel)"

# Check if there are any changes to commit
if git diff --quiet && git diff --cached --quiet; then
  echo "No changes to commit."
  exit 0
fi

# Extract upgraded package names from versions.json diff.
# Looks for lines like:  -    "fzf": "0.70.0",  /  +    "fzf": "0.71.0",
# and collects the package names that changed.
changed_packages=()
if ! git diff --quiet -- versions.json; then
  # Get removed lines (old versions) with package names
  local -A old_versions
  while IFS= read -r line; do
    if [[ "$line" =~ '^\-[[:space:]]+"([^"]+)":[[:space:]]+"([^"]+)"' ]]; then
      old_versions[${match[1]}]=${match[2]}
    fi
  done < <(git diff -- versions.json)

  # Get added lines (new versions) and match against old
  while IFS= read -r line; do
    if [[ "$line" =~ '^\+[[:space:]]+"([^"]+)":[[:space:]]+"([^"]+)"' ]]; then
      local pkg=${match[1]}
      [[ "$pkg" == "_generated" ]] && continue
      if (( ${+old_versions[$pkg]} )); then
        changed_packages+=("$pkg")
      fi
    fi
  done < <(git diff -- versions.json)
fi

# Also check config file changes for packages not reflected in versions.json
for f in config/claude/version config/sheldon/plugins.toml config/uv/tools.txt config/pnpm/globals.txt; do
  if ! git diff --quiet -- "$f" 2>/dev/null; then
    case "$f" in
      config/claude/version) changed_packages+=("claude") ;;
    esac
  fi
done

# Deduplicate
changed_packages=(${(u)changed_packages})

# Build commit message
if (( ${#changed_packages} == 0 )); then
  msg="chore: upgrade dependencies"
else
  pkg_list="${(j:, :)changed_packages}"
  msg="chore: upgrade $pkg_list"
fi

git add -A
git commit -m "$msg"
echo "Committed: $msg"
