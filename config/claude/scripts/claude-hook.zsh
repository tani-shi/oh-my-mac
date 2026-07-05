#!/bin/zsh
# Unified Claude Code hook handler.
# Usage: claude-hook.zsh <stop|notification|userpromptsubmit|taskcompleted>
#
# Reads Claude Code hook JSON from stdin and orchestrates:
#   - iTerm2 tab color (green/orange/reset)
#   - macOS notification (title = current folder, body = response/message)
#   - Deduplication: suppress Notification within DEDUP_WINDOW seconds of Stop

EVENT="${1:?event required: stop|notification|userpromptsubmit|taskcompleted}"

# Skip while a claude-sentinel-wrapper is judging in this session.
# Walk to the topmost `claude` PID; the wrapper's flag is keyed on that PID,
# so both parent-direct and Agent-SDK-nested hooks find it.
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
if [[ -n "$last_claude_pid" ]]; then
  # Flag format: <parent-claude-pid>.<wrapper-pid>.flag. kill -0 detects
  # SIGKILLed wrappers whose trap didn't fire — clean up the stale flag so
  # the rest of the session isn't suppressed.
  for flag in /tmp/claude-sentinel-running.${last_claude_pid}.*.flag(N); do
    wpid=${${flag##*/claude-sentinel-running.${last_claude_pid}.}%.flag}
    if kill -0 "$wpid" 2>/dev/null; then
      exit 0
    else
      rm -f "$flag"
    fi
  done
fi

INPUT="$(cat)"
SCRIPT_DIR="${0:A:h}"
DEDUP_WINDOW=5

SESSION_ID=$(jq -r '.session_id // "default"' <<<"$INPUT" 2>/dev/null || echo default)
STATE_FILE="/tmp/claude-hook-${SESSION_ID}.state"
NOW=$(date +%s)

LAST_EVENT=""
LAST_TIME=0
if [[ -f "$STATE_FILE" ]]; then
  IFS=' ' read -r LAST_EVENT LAST_TIME < "$STATE_FILE" 2>/dev/null || true
fi
ELAPSED=$((NOW - ${LAST_TIME:-0}))

_write_state() { echo "$1 $NOW" > "$STATE_FILE" }

_notify() {
  local title="$1" body="$2" sound="$3"
  if (( ${#body} > 200 )); then
    body="${body:0:200}…"
  fi
  body="${body//$'\n'/ }"
  body="${body//$'\t'/ }"

  local focus_script="$SCRIPT_DIR/iterm2-focus-tab.applescript"
  # terminal-notifier supports -execute on click; route the click back to the
  # originating iTerm2 tab via ITERM_SESSION_ID. Fall back to osascript when
  # terminal-notifier or the iTerm2 session id is unavailable.
  if [[ -n "$ITERM_SESSION_ID" ]] \
    && command -v terminal-notifier >/dev/null 2>&1 \
    && [[ -f "$focus_script" ]]; then
    # Detach so the hook returns immediately even if terminal-notifier
    # keeps a process alive to handle the -execute click.
    (terminal-notifier \
      -title "$title" \
      -message "$body" \
      -sound "$sound" \
      -sender com.googlecode.iterm2 \
      -execute "/usr/bin/osascript '$focus_script' '$ITERM_SESSION_ID'" \
      >/dev/null 2>&1 &) >/dev/null 2>&1
  else
    body="${body//\\/\\\\}"
    body="${body//\"/\\\"}"
    title="${title//\\/\\\\}"
    title="${title//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\" sound name \"$sound\"" 2>/dev/null
  fi
}

_last_assistant_text() {
  local transcript="$1"
  [[ -f "$transcript" ]] || return
  # Bound search to the current turn (after the last user-prompt entry, where
  # .message.content is a string — tool_result entries store an array). Avoids
  # leaking the previous turn's text when the current turn hasn't flushed its
  # final text to the transcript yet.
  jq -s -r '
    . as $all |
    ([range(0; length) | select($all[.].type == "user" and ($all[.].message.content | type) == "string")] | last // -1) as $boundary |
    [$all[($boundary + 1):][] | select(.type == "assistant") | (.message.content // [])[] | select(.type == "text") | .text] | last // ""
  ' "$transcript" 2>/dev/null
}

case "$EVENT" in
  userpromptsubmit)
    "$SCRIPT_DIR/iterm2-tab-color.zsh" reset
    _write_state "$EVENT"
    ;;
  stop)
    [[ -x "$HOME/.claude/scripts/check-docs.zsh" ]] && zsh "$HOME/.claude/scripts/check-docs.zsh"
    "$SCRIPT_DIR/iterm2-tab-color.zsh" green
    transcript=$(jq -r '.transcript_path // ""' <<<"$INPUT" 2>/dev/null)
    # Wait for the final assistant text to flush to the transcript file.
    # Stop fires before the last text segment is durably written, so reading
    # immediately can return an earlier text from the same turn.
    sleep 1
    body=$(_last_assistant_text "$transcript")
    [[ -z "$body" ]] && body="Task completed"
    _notify "${PWD##*/}" "$body" "Glass"
    _write_state "$EVENT"
    ;;
  notification)
    # Both stop and taskcompleted already notified for the same moment.
    if [[ ("$LAST_EVENT" == "stop" || "$LAST_EVENT" == "taskcompleted") && $ELAPSED -lt $DEDUP_WINDOW ]]; then
      exit 0
    fi
    # Preserve tab color set by Stop (green) or wrapper (orange on ask).
    body=$(jq -r '.message // "Claude is waiting for your input"' <<<"$INPUT" 2>/dev/null)
    _notify "${PWD##*/}" "$body" "Funk"
    _write_state "$EVENT"
    ;;
  taskcompleted)
    # Agent Teams task completion. The payload schema may drift while the
    # feature is experimental; the jq fallbacks degrade to a generic body
    # instead of failing. This hook runs globally, so it stays observational:
    # exit 2 would block task completion for every project on this machine.
    teammate=$(jq -r 'first((.teammate_name, .teammate.name?) | strings | select(. != "")) // ""' <<<"$INPUT" 2>/dev/null)
    task=$(jq -r 'first((.task_subject, .task.subject?, .task.description?) | strings | select(. != "")) // ""' <<<"$INPUT" 2>/dev/null)
    body="${task:-Task completed}"
    [[ -n "$teammate" ]] && body="[$teammate] $body"
    _notify "${PWD##*/}" "$body" "Glass"
    _write_state "$EVENT"
    ;;
  *)
    echo "Unknown event: $EVENT" >&2
    exit 1
    ;;
esac

exit 0
