validate_agent_sentinel_codex_config() {
  local hooks_path=$1 rules_path=$2

  if ! jq -e --arg command 'agent-sentinel --host codex' '
    [.hooks.PreToolUse[]? | .hooks[]? | select(.type == "command") | .command]
    | index($command) != null
  ' "$hooks_path" >/dev/null; then
    print -u2 "Error: agent-sentinel did not generate its Codex PreToolUse hook"
    return 1
  fi

  if [[ ! -s "$rules_path" ]]; then
    print -u2 "Error: agent-sentinel did not generate Codex execution rules"
    return 1
  fi

  if ! awk '
    /^[[:space:]]*prefix_rule[[:space:]]*\(/ { rules++ }
    /^[[:space:]]*decision[[:space:]]*=/ {
      decisions++
      if ($0 !~ /^[[:space:]]*decision[[:space:]]*=[[:space:]]*"(prompt|forbidden)"[[:space:]]*,?[[:space:]]*(#.*)?$/) {
        unsafe++
      }
    }
    END {
      exit rules == 0 || decisions != rules || unsafe != 0
    }
  ' "$rules_path"; then
    print -u2 "Error: every agent-sentinel Codex rule must explicitly use prompt or forbidden"
    return 1
  fi
}

agent_sentinel_codex_hook_definition() {
  local hooks_path=$1

  if [[ ! -f "$hooks_path" ]]; then
    print -r -- '[]'
    return 0
  fi

  jq -cS --arg command 'agent-sentinel --host codex' '
    [
      .hooks.PreToolUse[]? as $group
      | $group.hooks[]?
      | select(.type == "command" and .command == $command)
      | {
          event: "PreToolUse",
          matcher: ($group.matcher // null),
          hook: .
        }
    ]
  ' "$hooks_path"
}

agent_sentinel_codex_hook_changed() {
  local current_hooks=$1 generated_hooks=$2
  local current_definition generated_definition

  current_definition=$(agent_sentinel_codex_hook_definition "$current_hooks")
  generated_definition=$(agent_sentinel_codex_hook_definition "$generated_hooks")
  [[ "$current_definition" != "$generated_definition" ]]
}

print_codex_hook_trust_instructions() {
  local state=$1

  if [[ "$state" == "pending" ]]; then
    echo "The generated Codex hook definition changed."
    echo "Run 'make sync-config', then review and trust the agent-sentinel hook:"
  else
    echo "Codex hook trust is required. Review and trust the agent-sentinel hook:"
  fi
  echo "  GUI: Open Settings > Hooks."
  echo "  CLI: Run /hooks."
}
