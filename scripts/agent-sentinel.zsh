validate_agent_sentinel_codex_config() {
  local hooks_path=$1 rules_path=$2

  if ! jq -e --arg command 'agent-sentinel --host codex' '
    def has_hook($event; $matcher):
      any(.hooks[$event][]?;
        (.matcher // null) == $matcher
        and any(.hooks[]?; .type == "command" and .command == $command));
    has_hook("PreToolUse"; "*")
    and has_hook("PostToolUse"; "codex_appcreate_thread")
    and has_hook("PermissionRequest"; "codex_appsend_message_to_thread")
  ' "$hooks_path" >/dev/null; then
    print -u2 "Error: agent-sentinel did not generate its required Codex hooks"
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

generate_agent_sentinel_codex_config() {
  local hooks_path=$1 rules_path=$2 installed_config_path=$3
  local install_output line

  mkdir -p "${hooks_path:h}"
  if [[ -f "$installed_config_path" ]]; then
    cp "$installed_config_path" "${hooks_path:h}/config.toml"
  fi

  install_output=$(agent-sentinel install --target codex --path "$hooks_path")
  while IFS= read -r line; do
    [[ "$line" == Warning:* ]] && print -u2 -r -- "$line"
  done <<< "$install_output"

  validate_agent_sentinel_codex_config "$hooks_path" "$rules_path"
}

agent_sentinel_codex_hook_definition() {
  local hooks_path=$1

  if [[ ! -f "$hooks_path" ]]; then
    print -r -- '[]'
    return 0
  fi

  jq -cS --arg command 'agent-sentinel --host codex' '
    [
      ["PreToolUse", "PostToolUse", "PermissionRequest"][] as $event
      | .hooks[$event][]? as $group
      | $group.hooks[]?
      | select(.type == "command" and .command == $command)
      | {
          event: $event,
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
