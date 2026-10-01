#!/bin/zsh
# Claude Code status line: model · context usage · directory (branch) · session ID prefix.
# Session JSON arrives on stdin: https://code.claude.com/docs/en/statusline

input="$(cat)"
IFS=$'\t' read -r model pct dir sid < <(jq -r '[
  .model.display_name // "?",
  (.context_window.used_percentage // 0 | floor),
  .workspace.current_dir // .cwd // "",
  .session_id // ""
] | @tsv' <<<"$input")

dir="${dir:-$PWD}"
# --no-optional-locks keeps this read-only probe from contending with concurrent git commands.
branch=$(git --no-optional-locks -C "$dir" branch --show-current 2>/dev/null)
[[ -z "$branch" ]] && branch=$(git --no-optional-locks -C "$dir" rev-parse --short HEAD 2>/dev/null)

location="${dir:t}"
[[ -n "$branch" ]] && location+=" ($branch)"

print -r -- "$model · ctx ${pct}% · $location · ${sid:0:8}"
