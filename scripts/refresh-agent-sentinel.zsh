#!/bin/zsh
set -eu

REPO="${0:A:h}/.."
CLAUDE_SETTINGS="$REPO/config/claude/settings.json"
source "$REPO/scripts/agent-sentinel.zsh"

for command_name in agent-sentinel codex jq; do
  if ! command -v "$command_name" &>/dev/null; then
    print -u2 "Error: $command_name is required to refresh agent-sentinel config"
    exit 1
  fi
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

generated_claude="$tmpdir/claude/settings.json"
generated_codex="$tmpdir/codex/hooks.json"
generated_rules="$tmpdir/codex/rules/agent-sentinel.rules"
mkdir -p "${generated_claude:h}" "${generated_codex:h}"
cp "$CLAUDE_SETTINGS" "$generated_claude"

agent-sentinel install --target claude --path "$generated_claude" >/dev/null
agent-sentinel install --target codex --path "$generated_codex" >/dev/null

jq -e --arg command 'zsh ~/.claude/scripts/agent-sentinel-wrapper.zsh' \
  '[.hooks.PreToolUse[].hooks[].command] | index($command) != null' \
  "$generated_claude" >/dev/null
validate_agent_sentinel_codex_config "$generated_codex" "$generated_rules"

policy=$(codex execpolicy check --pretty --rules "$generated_rules" -- ssh host)
if ! print -r -- "$policy" | jq -e '.decision == "prompt"' >/dev/null; then
  print -u2 "Error: agent-sentinel rules do not prompt for ssh host"
  exit 1
fi

if diff -q "$CLAUDE_SETTINGS" "$generated_claude" &>/dev/null; then
  echo "Claude Code settings are already up to date."
else
  git diff --no-index "$CLAUDE_SETTINGS" "$generated_claude" || true
  cp "$generated_claude" "$CLAUDE_SETTINGS"
  echo "Updated: $CLAUDE_SETTINGS"
fi

echo "Validated generated Codex hooks and execution rules."
