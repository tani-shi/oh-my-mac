#!/bin/zsh
set -eu

# Read hook JSON from stdin (Claude Code passes session_id, transcript_path, etc.)
input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# Guard: exit early if expected fields are missing (stdin not received or malformed)
[[ -z "$session_id" ]] && exit 0

# Guard: skip if Claude is already continuing from a previous stop hook (prevents infinite loop)
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[[ "$stop_hook_active" == "true" ]] && exit 0

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

      # Skip if doc doesn't exist on disk
      [[ -f "$repo_root/$doc_path" ]] || continue

      # Skip if doc is not tracked by git (newly created files don't need "updating")
      git -C "$repo_root" ls-files --error-unmatch "$doc_path" &>/dev/null || continue

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
  rg -qF "$reminder_tag" "$transcript_path" 2>/dev/null && exit 0
fi

# Report: output JSON decision to block stop and provide reason
stale_list=$(printf '  - %s\n' "${stale[@]}" | sort -u)
reason="$reminder_tag Files were changed but documentation was not updated.
Please verify these files are current:
${stale_list}"

jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
