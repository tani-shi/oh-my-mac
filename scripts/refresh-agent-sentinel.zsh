#!/bin/zsh
set -eu

REPO="${0:A:h}/.."
CLAUDE_SETTINGS="$REPO/config/claude/settings.json"
UV_TOOLS="$REPO/config/uv/tools.txt"
CODEX_CONFIG="$HOME/.codex/config.toml"
CODEX_HOOKS="$HOME/.codex/hooks.json"
AGENT_SENTINEL_REPOSITORY="https://github.com/tani-shi/agent-sentinel.git"
source "$REPO/scripts/agent-sentinel.zsh"

for command_name in agent-sentinel codex git jq uv; do
  if ! command -v "$command_name" &>/dev/null; then
    print -u2 "Error: $command_name is required to refresh agent-sentinel config"
    exit 1
  fi
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

current_requirement=$(grep -E '^agent-sentinel\[claude\] @ git\+https://github\.com/tani-shi/agent-sentinel\.git@[0-9a-f]{40}$' "$UV_TOOLS") || {
  print -u2 "Error: agent-sentinel must have one full commit pin in $UV_TOOLS"
  exit 1
}
if [[ $(grep -Ec '^agent-sentinel(\[[^]]+\])? @ git\+https://github\.com/tani-shi/agent-sentinel\.git' "$UV_TOOLS") -ne 1 ]]; then
  print -u2 "Error: agent-sentinel must have one full commit pin in $UV_TOOLS"
  exit 1
fi

remote_commit=$(git ls-remote "$AGENT_SENTINEL_REPOSITORY" HEAD | awk '$2 == "HEAD" { print $1 }') || {
  print -u2 "Error: failed to resolve agent-sentinel HEAD"
  exit 1
}
if [[ ! "$remote_commit" =~ '^[0-9a-f]{40}$' ]]; then
  print -u2 "Error: agent-sentinel HEAD did not resolve to a full commit SHA"
  exit 1
fi

verification_repository="$tmpdir/agent-sentinel.git"
git init --quiet "$verification_repository"
if ! git -C "$verification_repository" fetch --quiet --depth=1 "$AGENT_SENTINEL_REPOSITORY" HEAD; then
  print -u2 "Error: failed to fetch agent-sentinel commit $remote_commit"
  exit 1
fi
fetched_commit=$(git -C "$verification_repository" rev-parse 'FETCH_HEAD^{commit}') || {
  print -u2 "Error: fetched agent-sentinel revision is not a commit"
  exit 1
}
if [[ "$fetched_commit" != "$remote_commit" ]]; then
  print -u2 "Error: fetched agent-sentinel commit $fetched_commit does not match resolved HEAD $remote_commit"
  exit 1
fi
echo "Verified agent-sentinel commit: $remote_commit"

candidate_requirement="${current_requirement%.git@*}.git@$remote_commit"
candidate_tools="$tmpdir/tools.txt"
if ! awk -v current="$current_requirement" -v candidate="$candidate_requirement" '
  $0 == current { print candidate; replaced++; next }
  { print }
  END { if (replaced != 1) exit 1 }
' "$UV_TOOLS" > "$candidate_tools"; then
  print -u2 "Error: failed to prepare the agent-sentinel pin update"
  exit 1
fi

if [[ "$candidate_requirement" != "$current_requirement" ]]; then
  echo "Installing verified agent-sentinel commit: $remote_commit"
  uv tool install --upgrade "$candidate_requirement"
  command -v agent-sentinel >/dev/null 2>&1 || {
    print -u2 "Error: agent-sentinel executable not found after install"
    exit 1
  }
  agent-sentinel --help >/dev/null 2>&1 || {
    print -u2 "Error: agent-sentinel executable check failed"
    exit 1
  }
else
  echo "agent-sentinel is already pinned to $remote_commit."
fi

generated_claude="$tmpdir/claude/settings.json"
generated_codex="$tmpdir/codex/hooks.json"
generated_rules="$tmpdir/codex/rules/agent-sentinel.rules"
mkdir -p "${generated_claude:h}" "${generated_codex:h}"
cp "$CLAUDE_SETTINGS" "$generated_claude"

agent-sentinel install --target claude --path "$generated_claude" >/dev/null
generate_agent_sentinel_codex_config "$generated_codex" "$generated_rules" "$CODEX_CONFIG"

jq -e --arg command 'zsh ~/.claude/scripts/agent-sentinel-wrapper.zsh' \
  '[.hooks.PreToolUse[].hooks[].command] | index($command) != null' \
  "$generated_claude" >/dev/null
codex_hook_changed=0
if agent_sentinel_codex_hook_changed "$CODEX_HOOKS" "$generated_codex"; then
  codex_hook_changed=1
fi

policy=$(codex execpolicy check --pretty --rules "$generated_rules" -- ssh host)
if ! print -r -- "$policy" | jq -e '.decision == "prompt"' >/dev/null; then
  print -u2 "Error: agent-sentinel rules do not prompt for ssh host"
  exit 1
fi

if diff -q "$UV_TOOLS" "$candidate_tools" &>/dev/null; then
  echo "The agent-sentinel pin is already up to date."
else
  git diff --no-index "$UV_TOOLS" "$candidate_tools" || true
  cp "$candidate_tools" "$UV_TOOLS"
  echo "Updated: $UV_TOOLS"
fi

if diff -q "$CLAUDE_SETTINGS" "$generated_claude" &>/dev/null; then
  echo "Claude Code settings are already up to date."
else
  git diff --no-index "$CLAUDE_SETTINGS" "$generated_claude" || true
  cp "$generated_claude" "$CLAUDE_SETTINGS"
  echo "Updated: $CLAUDE_SETTINGS"
fi

echo "Validated generated Codex hooks and execution rules."
if [[ $codex_hook_changed -eq 1 ]]; then
  print_codex_hook_trust_instructions pending
fi
