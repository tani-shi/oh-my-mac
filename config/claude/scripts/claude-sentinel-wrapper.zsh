#!/bin/zsh
# Wrap claude-sentinel: paint the iTerm2 tab purple during long LLM-backed
# judgments, orange on ask, reset on allow/deny, and notify after 5s.

SCRIPT_DIR="${0:A:h}"
THRESHOLD_SEC=0.3
SLOW_NOTIFY_SEC=5
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
  remaining=$(awk -v a="$SLOW_NOTIFY_SEC" -v b="$THRESHOLD_SEC" 'BEGIN { print a - b }')
  sleep "$remaining"
  osascript -e 'display notification "Sentinel is still judging…" with title "claude-sentinel"' 2>/dev/null
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

# ask (exit 0, empty) → orange directly (skip reset to avoid flicker).
# Empty output with non-zero exit is an error, not ask.
if [[ "$exit_code" -eq 0 && -z "$output" ]]; then
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
