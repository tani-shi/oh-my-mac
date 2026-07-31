#!/bin/zsh
set -eu

# Usage: ./scripts/snapshot-versions.zsh > versions.json

to_json() {
  jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

brew_managed_versions() {
  local kind="$1"
  local brewfile="${2:-Brewfile}"

  local declared
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list "$kind" --file="$brewfile" 2>/dev/null | while IFS= read -r declared; do
    brew list "$kind" "$declared" --versions 2>/dev/null | awk '{name=$1; $1=""; sub(/^ /, ""); print name "\t" $0}'
  done | to_json
}

sheldon_versions() {
  local plugins_toml="${1:-config/sheldon/plugins.toml}"
  awk '
    /^\[plugins\./ { gsub(/\[plugins\.|]/, ""); plugin=$0 }
    plugin && /^(tag|rev) = / { gsub(/"/, "", $3); print plugin "\t" $1 ":" $3; plugin="" }
  ' "$plugins_toml" | to_json
}

uv_versions() {
  local tools_txt="${1:-config/uv/tools.txt}"
  awk -F@ '
    NF == 0 { next }
    NF == 1 { print $1 "\tHEAD" }
    NF >= 2 { print $1 "\t" $2 }
  ' "$tools_txt" | to_json
}

claude_version() {
  claude --version 2>/dev/null | awk '{print $1}' || echo "unknown"
}

ntn_version() {
  command -v fnm >/dev/null 2>&1 && eval "$(fnm env)" 2>/dev/null
  ntn --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown"
}

jq -n \
  --argjson brew "$(brew_managed_versions --formula)" \
  --argjson cask "$(brew_managed_versions --cask)" \
  --argjson sheldon "$(sheldon_versions)" \
  --argjson uv "$(uv_versions)" \
  --arg claude "$(claude_version)" \
  --arg ntn "$(ntn_version)" \
  '{
    _generated: now | todate,
    claude: $claude,
    ntn: $ntn,
    brew: $brew,
    cask: $cask,
    sheldon: $sheldon,
    uv: $uv
  }'
