#!/bin/zsh
# Set iTerm2 tab color via OSC 6, written directly to the controlling TTY
# so it reaches iTerm2 regardless of the caller's stdout capture.
# Usage: iterm2-tab-color.zsh <green|orange|purple|reset>

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

{ print -n -- "$esc" > /dev/tty } 2>/dev/null
exit 0
