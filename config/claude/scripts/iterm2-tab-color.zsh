#!/bin/zsh
# Set iTerm2 tab color via OSC 6, written directly to the controlling TTY
# so it reaches iTerm2 regardless of the caller's stdout capture.
# Usage: iterm2-tab-color.zsh <green|orange|purple|reset>
#
# Claude Code spawns hook subprocesses without a controlling terminal, so
# /dev/tty fails to open ("device not configured"). When that happens, walk
# up to the parent `claude` process and write to its tty device instead.

case "${1:-reset}" in
  green)
    esc=$'\e]6;1;bg;red;brightness;0\a\e]6;1;bg;green;brightness;180\a\e]6;1;bg;blue;brightness;100\a'
    ;;
  orange)
    esc=$'\e]6;1;bg;red;brightness;230\a\e]6;1;bg;green;brightness;130\a\e]6;1;bg;blue;brightness;0\a'
    ;;
  purple)
    esc=$'\e]6;1;bg;red;brightness;160\a\e]6;1;bg;green;brightness;90\a\e]6;1;bg;blue;brightness;200\a'
    ;;
  reset)
    esc=$'\e]6;1;bg;*;default\a'
    ;;
  *)
    echo "Usage: $0 <green|orange|purple|reset>" >&2
    exit 1
    ;;
esac

_target_tty() {
  if { : > /dev/tty } 2>/dev/null; then
    print -- /dev/tty
    return
  fi
  local pid=$$ cmd t
  while [[ "$pid" -gt 1 ]]; do
    IFS=' ' read -r cmd t <<<"$(ps -o comm=,tty= -p "$pid" 2>/dev/null)"
    if [[ "$cmd" == "claude" || "$cmd" == */claude ]] && [[ -n "$t" && "$t" != "??" ]]; then
      print -- "/dev/$t"
      return
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
}

dev=$(_target_tty)
[[ -n "$dev" ]] && { print -n -- "$esc" > "$dev" } 2>/dev/null
exit 0
