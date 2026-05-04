#!/bin/zsh
# Unified Claude Code hook handler.
# Usage: claude-hook.zsh <stop|notification|userpromptsubmit>
#
# Reads Claude Code hook JSON from stdin and orchestrates:
#   - iTerm2 tab color (green/orange/reset)
#   - macOS notification (title = current folder, body = response/message)
#   - Deduplication: suppress Notification within DEDUP_WINDOW seconds of Stop

EVENT="${1:?event required: stop|notification|userpromptsubmit}"
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
  body="${body//\\/\\\\}"
  body="${body//\"/\\\"}"
  title="${title//\\/\\\\}"
  title="${title//\"/\\\"}"
  osascript -e "display notification \"$body\" with title \"$title\" sound name \"$sound\"" 2>/dev/null
}

_last_assistant_text() {
  local transcript="$1"
  [[ -f "$transcript" ]] || return
  tail -100 "$transcript" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | (.message.content // []) | .[]? | select(.type == "text") | .text' 2>/dev/null \
    | tail -n 1
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
    body=$(_last_assistant_text "$transcript")
    [[ -z "$body" ]] && body="Task completed"
    _notify "${PWD##*/}" "$body" "Glass"
    _write_state "$EVENT"
    ;;
  notification)
    if [[ "$LAST_EVENT" == "stop" && $ELAPSED -lt $DEDUP_WINDOW ]]; then
      exit 0
    fi
    "$SCRIPT_DIR/iterm2-tab-color.zsh" orange
    body=$(jq -r '.message // "Claude is waiting for your input"' <<<"$INPUT" 2>/dev/null)
    _notify "${PWD##*/}" "$body" "Funk"
    _write_state "$EVENT"
    ;;
  *)
    echo "Unknown event: $EVENT" >&2
    exit 1
    ;;
esac

exit 0
