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
