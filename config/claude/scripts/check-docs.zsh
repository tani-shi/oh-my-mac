#!/bin/zsh
set -eu

# Read hook JSON from stdin (Claude Code passes session_id, transcript_path, etc.)
input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# Only run in git repositories
git rev-parse --is-inside-work-tree &>/dev/null || exit 0
repo_root=$(git rev-parse --show-toplevel)

# Get all changes (staged + unstaged), paths relative to repo root
all_changed=$( (git -C "$repo_root" diff --name-only HEAD 2>/dev/null; git -C "$repo_root" diff --name-only --cached 2>/dev/null) | sort -u )
[[ -z "$all_changed" ]] && exit 0

# Filter out doc files to get "source" changes only
source_changed=$(echo "$all_changed" | grep -vE '(^|/)README\.md$' | grep -vE '(^|/)CLAUDE\.md$' || true)
[[ -z "$source_changed" ]] && exit 0

# For each changed source file, walk up directories to find nearest doc files
stale=()
checked=()

while IFS= read -r file; do
  dir=$(dirname "$file")

  while true; do
    for doc in README.md CLAUDE.md; do
      doc_path="$doc"
      [[ "$dir" != "." ]] && doc_path="$dir/$doc"

      # Skip if already checked
      [[ " ${checked[*]:-} " == *" $doc_path "* ]] && continue
      checked+=("$doc_path")

      # Skip if doc doesn't exist
      [[ -f "$repo_root/$doc_path" ]] || continue

      # Skip if doc was already changed
      echo "$all_changed" | grep -q "^${doc_path}$" && continue

      stale+=("$doc_path")
    done

    [[ "$dir" == "." ]] && break
    dir=$(dirname "$dir")
  done
done <<< "$source_changed"

[[ ${#stale[@]} -eq 0 ]] && exit 0

# Dedup: check if we already reminded in this session
reminder_tag="[check-docs]"
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  last_rename_line=$(rg -n '"custom-title"' "$transcript_path" 2>/dev/null | tail -1 | cut -d: -f1 || true)
  if [[ -n "$last_rename_line" ]]; then
    # Only check lines after the last rename
    tail -n "+${last_rename_line}" "$transcript_path" | rg -q "$reminder_tag" 2>/dev/null && exit 0
  else
    # No rename events: check entire transcript
    rg -q "$reminder_tag" "$transcript_path" 2>/dev/null && exit 0
  fi
fi

# Report with unique tag for transcript-based dedup
echo "$reminder_tag Files were changed but documentation was not updated." >&2
echo "Please verify these files are current:" >&2
printf '  - %s\n' "${stale[@]}" | sort -u >&2
exit 2
