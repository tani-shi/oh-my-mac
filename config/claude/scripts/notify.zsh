#!/bin/zsh
# Claude Code hook: post a macOS notification describing the event.
# Usage: notify.zsh <stop|notification>  (hook JSON on stdin)
#
# osascript exits right after posting. terminal-notifier stays resident per
# notification and exhausted launchservicesd's client queues (see c7859c4).

event="${1:?event required: stop|notification}"
input="$(cat)"

case "$event" in
  stop)
    # The launching terminal is already in front, so the reply is visible.
    front=$(lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null)
    front="${${front#*=\"}%\"}"
    [[ -n "$__CFBundleIdentifier" && "$front" == "$__CFBundleIdentifier" ]] && exit 0
    body=$(jq -r '.last_assistant_message // ""' <<<"$input" 2>/dev/null)
    [[ -n "$body" ]] || body="Task completed"
    sound="Glass"
    ;;
  notification)
    body=$(jq -r '.message // ""' <<<"$input" 2>/dev/null)
    [[ -n "$body" ]] || body="Claude is waiting for your input"
    sound="Funk"
    ;;
  *)
    print -u2 "Unknown event: $event"
    exit 1
    ;;
esac

cwd=$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null)
title="${${cwd:-$PWD}:t}"
body="${(j: :)${=body}}"
(( ${#body} > 160 )) && body="${body:0:160}…"

osascript \
  -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title (item 2 of argv) sound name (item 3 of argv)' \
  -e 'end run' \
  "$body" "$title" "$sound" 2>/dev/null
exit 0
