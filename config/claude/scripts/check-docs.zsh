#!/bin/zsh
set -eu

[[ "${SKIP_CHECK_DOCS:-0}" == "1" ]] && exit 0

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)
permission_mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null || true)

[[ "$permission_mode" != "acceptEdits" ]] && exit 0

[[ -z "$session_id" ]] && exit 0

# stop_hook_active means we are already inside a prior block's continuation; re-blocking would loop
stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[[ "$stop_hook_active" == "true" ]] && exit 0

git rev-parse --is-inside-work-tree &>/dev/null || exit 0
repo_root=$(git rev-parse --show-toplevel)

all_changed=$( (git -C "$repo_root" diff --name-only HEAD 2>/dev/null; git -C "$repo_root" diff --name-only --cached 2>/dev/null) | sort -u )
[[ -z "$all_changed" ]] && exit 0

source_changed=$(echo "$all_changed" | grep -vE '(^|/)README\.md$' || true)
[[ -z "$source_changed" ]] && exit 0

stale=()
checked=()

while IFS= read -r file; do
  dir=$(dirname "$file")

  while true; do
    for doc in README.md; do
      doc_path="$doc"
      [[ "$dir" != "." ]] && doc_path="$dir/$doc"

      [[ " ${checked[*]:-} " == *" $doc_path "* ]] && continue
      checked+=("$doc_path")

      [[ -f "$repo_root/$doc_path" ]] || continue

      # untracked docs are newly created, not stale — nothing to update
      git -C "$repo_root" ls-files --error-unmatch "$doc_path" &>/dev/null || continue

      echo "$all_changed" | grep -q "^${doc_path}$" && continue

      stale+=("$doc_path")
    done

    [[ "$dir" == "." ]] && break
    dir=$(dirname "$dir")
  done
done <<< "$source_changed"

[[ ${#stale[@]} -eq 0 ]] && exit 0

reminder_tag="[check-docs]"
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  rg -qF "$reminder_tag" "$transcript_path" 2>/dev/null && exit 0
fi

stale_list=$(printf '  - %s\n' "${stale[@]}" | sort -u)
reason="$reminder_tag Files were changed but documentation was not updated.
Please verify these files are current:
${stale_list}"

jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
