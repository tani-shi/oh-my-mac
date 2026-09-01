#!/bin/zsh
set -eu

REPO="${0:A:h}/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

export HOME="$tmp/home"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export UV_CACHE_DIR="$tmp/uv-cache"
export UV_NO_PROGRESS=1
export OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT="$tmp/config-tools-root"

mkdir -p "$HOME" "$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT"
: > "$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT/.oh-my-mac-config-tools-test-root"

"$REPO/scripts/install-config-tools.zsh"
export OH_MY_MAC_TEST_CONFIG_PYTHON="$OH_MY_MAC_CONFIG_TOOLS_TEST_ROOT/config-tools/bin/python"

make -C "$REPO" test
