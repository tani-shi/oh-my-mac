#!/bin/zsh
SCRIPT_DIR="${0:A:h}"
THRESHOLD_SEC=0.3
FIRED_FLAG="/tmp/claude-sentinel-fired.$$.flag"
rm -f "$FIRED_FLAG"

# Walk ancestors to the topmost `claude` PID. Both parent-direct hooks and
# Agent-SDK-nested hooks share this ancestor, so flagging by it covers both.
# Claude Code does not propagate env to hook subprocesses, so a file flag is
# the only reliable signal.
last_claude_pid=""
pid=$$
while [[ "$pid" -gt 1 ]]; do
  cmd=$(ps -o comm= -p "$pid" 2>/dev/null | xargs)
  if [[ "$cmd" == "claude" || "$cmd" == */claude ]]; then
    last_claude_pid=$pid
  fi
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ -z "$pid" ]] && break
done
RUNNING_FLAG="/tmp/claude-sentinel-running.${last_claude_pid:-$$}.$$.flag"
: > "$RUNNING_FLAG"
trap 'rm -f "$RUNNING_FLAG"' EXIT INT TERM

(
  sleep "$THRESHOLD_SEC"
  : > "$FIRED_FLAG"
  "$SCRIPT_DIR/iterm2-tab-color.zsh" purple
) &
timer_pid=$!

output=$(claude-sentinel)
exit_code=$?

kill "$timer_pid" 2>/dev/null
wait "$timer_pid" 2>/dev/null

fired=0
if [[ -f "$FIRED_FLAG" ]]; then
  fired=1
  rm -f "$FIRED_FLAG"
fi

# claude-sentinel reports its verdict as a permissionDecision under PreToolUse.
# ask → orange directly (skip reset to avoid flicker); any other verdict clears
# the purple judging color.
decision=""
if [[ -n "$output" ]] && command -v jq >/dev/null 2>&1; then
  decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
fi

if [[ "$decision" == "ask" ]]; then
  "$SCRIPT_DIR/iterm2-tab-color.zsh" orange
elif (( fired )); then
  "$SCRIPT_DIR/iterm2-tab-color.zsh" reset
fi

if [[ -n "$output" ]]; then
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$output" | jq -c '. + {statusMessage: "claude-sentinel: judging…"}' 2>/dev/null \
      || printf '%s\n' "$output"
  else
    printf '%s\n' "$output"
  fi
fi

exit "$exit_code"
