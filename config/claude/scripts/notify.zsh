#!/bin/zsh
# Claude Code hook: emit an OSC 9 desktop notification through Claude Code.
# Usage: notify.zsh <stop|notification>  (hook JSON on stdin)
#
# Hooks have no controlling terminal, so the sequence is returned in
# terminalSequence for Claude Code to write. iTerm2 posts it and reveals the
# emitting tab on click; its "Suppress Alerts in Active Session" profile
# setting drops it while that tab is in front. preferredNotifChannel is
# notifications_disabled, so these are the only notifications.

event="${1:?event required: stop|notification}"
input="$(cat)"

case "$event" in
  stop)
    body=$(jq -r '.last_assistant_message // ""' <<<"$input" 2>/dev/null)
    [[ -n "$body" ]] || body="Task completed"
    ;;
  notification)
    # idle_prompt only repeats a Stop notification about 60 seconds later.
    case "$(jq -r '.notification_type // ""' <<<"$input" 2>/dev/null)" in
      permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input) ;;
      *) exit 0 ;;
    esac
    body=$(jq -r '.message // ""' <<<"$input" 2>/dev/null)
    [[ -n "$body" ]] || body="Claude is waiting for your input"
    ;;
  *)
    print -u2 "Unknown event: $event"
    exit 1
    ;;
esac

cwd=$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null)
body="${${cwd:-$PWD}:t}: ${(j: :)${=body}}"
# Control characters would end or corrupt the OSC sequence.
body="${body//[[:cntrl:]]/}"
(( ${#body} > 160 )) && body="${body:0:160}…"

jq -nc --arg seq $'\e]9;'"$body"$'\a' '{terminalSequence: $seq}'
