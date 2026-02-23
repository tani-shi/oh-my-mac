#!/bin/zsh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

configs=(
  "config/starship.toml:$HOME/.config/starship.toml"
  "config/sheldon/plugins.toml:$HOME/.config/sheldon/plugins.toml"
  "config/zshrc:$HOME/.zshrc"
  "config/git/ignore:$HOME/.config/git/ignore"
)

synced=()
for entry in "${configs[@]}"; do
  src="$SCRIPT_DIR/${entry%%:*}"
  dst="${entry##*:}"
  if ! diff -q "$src" "$dst" &>/dev/null; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "Synced: $dst"
    synced+=("$src")
  fi
done

if [[ ${#synced[@]} -eq 0 ]]; then
  echo "Already up to date."
  exit 0
fi

# Post-sync hooks
for src in "${synced[@]}"; do
  case "$src" in
    */sheldon/plugins.toml)
      echo "Running: sheldon lock"
      sheldon lock
      ;;
    */zshrc)
      echo "Run 'source ~/.zshrc' to apply changes."
      ;;
  esac
done
