#!/bin/zsh
set -eu

# Usage: ./scripts/snapshot-versions.zsh > versions.json

to_json() {
  jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

brew_list_versions() {
  brew list "$1" --versions 2>/dev/null | awk '{name=$1; $1=""; sub(/^ /, ""); print name "\t" $0}' | to_json
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

pnpm_versions() {
  local globals_txt="${1:-config/pnpm/globals.txt}"
  awk -F@ '
    NF == 0 { next }
    NF >= 2 { print $1 "\t" $2 }
  ' "$globals_txt" | to_json
}

claude_version() {
  claude --version 2>/dev/null | awk '{print $1}' || echo "unknown"
}

jq -n \
  --argjson brew "$(brew_list_versions --formula)" \
  --argjson cask "$(brew_list_versions --cask)" \
  --argjson sheldon "$(sheldon_versions)" \
  --argjson pnpm "$(pnpm_versions)" \
  --argjson uv "$(uv_versions)" \
  --arg claude "$(claude_version)" \
  '{
    _generated: now | todate,
    claude: $claude,
    brew: $brew,
    cask: $cask,
    sheldon: $sheldon,
    pnpm: $pnpm,
    uv: $uv
  }'
