#!/bin/zsh
set -eu

# Snapshot installed versions of all managed packages as JSON.
# Usage: ./scripts/snapshot-versions.zsh > versions.json

brew_versions() {
  brew list --formula --versions | awk '{name=$1; $1=""; sub(/^ /, ""); print name "\t" $0}' | \
    jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

cask_versions() {
  brew list --cask --versions 2>/dev/null | awk '{name=$1; $1=""; sub(/^ /, ""); print name "\t" $0}' | \
    jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

sheldon_versions() {
  local plugins_toml="${1:-config/sheldon/plugins.toml}"
  awk '
    /^\[plugins\./ { gsub(/\[plugins\.|]/, ""); plugin=$0 }
    plugin && /^(tag|rev) = / { gsub(/"/, "", $3); print plugin "\t" $1 ":" $3; plugin="" }
  ' "$plugins_toml" | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

uv_versions() {
  local tools_txt="${1:-config/uv/tools.txt}"
  awk -F@ '
    NF == 0 { next }
    NF == 1 { print $1 "\tHEAD" }
    NF >= 2 { print $1 "\t" $2 }
  ' "$tools_txt" | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

claude_version() {
  claude --version 2>/dev/null | awk '{print $1}' || echo "unknown"
}

jq -n \
  --argjson brew "$(brew_versions)" \
  --argjson cask "$(cask_versions)" \
  --argjson sheldon "$(sheldon_versions)" \
  --argjson uv "$(uv_versions)" \
  --arg claude "$(claude_version)" \
  '{
    _generated: now | todate,
    claude: $claude,
    brew: $brew,
    cask: $cask,
    sheldon: $sheldon,
    uv: $uv
  }'
