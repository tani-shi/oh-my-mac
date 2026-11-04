#!/bin/zsh
set -eu

# Compares app bundles with the latest casks because Homebrew's install record
# stays at the original version after an app updates itself.

autoload -Uz is-at-least

BREWFILE="${0:A:h}/../config/homebrew/Brewfile.install-only"

casks=(${(f)"$(brew bundle list --file="$BREWFILE" --cask)"})
pending=()
brew info --cask --json=v2 "${casks[@]}" |
  jq -r '.casks[] | [.token, (.version | split(",")[0]), (.artifacts[] | select(.app) | .app[0])] | @tsv' |
  while IFS=$'\t' read -r token latest app; do
    plist="/Applications/$app/Contents/Info.plist"
    [[ -f "$plist" ]] || continue
    installed=$(plutil -extract CFBundleShortVersionString raw "$plist")
    is-at-least "$latest" "$installed" || pending+=("$token $installed -> $latest")
  done

if (( ${#pending} )); then
  print "GUI apps with updates to apply (restart the app or use its update control):"
  print -l -- "  "${^pending}
else
  print "GUI apps are up to date"
fi
