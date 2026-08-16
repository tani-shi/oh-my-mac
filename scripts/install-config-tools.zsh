#!/bin/zsh
set -eu

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/config-tools.zsh"
REQUIREMENTS="$SCRIPT_DIR/../config/uv/config-tools.txt"
EXPECTED_TOMLKIT_VERSION=$(sed -n 's/^tomlkit==//p' "$REQUIREMENTS")

if [[ -n "${OH_MY_MAC_CONFIG_TOOLS_DIR:-}" ]]; then
  print -u2 "Error: OH_MY_MAC_CONFIG_TOOLS_DIR is not supported"
  exit 1
fi
if [[ -z "$EXPECTED_TOMLKIT_VERSION" ]]; then
  print -u2 "Error: tomlkit pin missing from $REQUIREMENTS"
  exit 1
fi
if [[ -n "$CONFIG_TOOLS_TEST_ROOT" ]]; then
  test_root="${CONFIG_TOOLS_TEST_ROOT:A}"
  temporary_root=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || print /tmp)
  temporary_root="${temporary_root:A}"
  if [[ "$CONFIG_TOOLS_TEST_ROOT" != /* \
    || ! -d "$CONFIG_TOOLS_TEST_ROOT" \
    || ! -f "$CONFIG_TOOLS_TEST_ROOT/.oh-my-mac-config-tools-test-root" \
    || "$test_root" != "$temporary_root"/* ]]; then
    print -u2 "Error: unsafe config tools test root: $CONFIG_TOOLS_TEST_ROOT"
    exit 1
  fi
  CONFIG_TOOLS_DIR="$test_root/config-tools"
  CONFIG_TOOLS_PYTHON="$CONFIG_TOOLS_DIR/bin/python"
elif [[ "$CONFIG_TOOLS_DIR" != "$HOME/.local/share/oh-my-mac/config-tools" ]]; then
  print -u2 "Error: unsafe config tools directory: $CONFIG_TOOLS_DIR"
  exit 1
fi

config_python_is_ready() {
  local python=$1 current
  [[ -x "$python" ]] || return 1
  current=$(PYTHONDONTWRITEBYTECODE=1 "$python" -c \
    'import sys, tomlkit; sys.version_info >= (3, 11) or sys.exit(1); print(tomlkit.__version__)' \
    2>/dev/null) || return 1
  [[ "$current" == "$EXPECTED_TOMLKIT_VERSION" ]]
}

if config_python_is_ready "$CONFIG_TOOLS_PYTHON"; then
  echo "Config tools already installed"
  exit 0
fi
if ! command -v uv &>/dev/null; then
  print -u2 "Error: uv not found"
  exit 1
fi

parent="${CONFIG_TOOLS_DIR:h}"
mkdir -p "$parent"
parent="${parent:A}"
if [[ -z "$CONFIG_TOOLS_TEST_ROOT" && "$parent" != "${HOME:A}"/* ]]; then
  print -u2 "Error: unsafe config tools parent: $parent"
  exit 1
fi
CONFIG_TOOLS_DIR="$parent/config-tools"
CONFIG_TOOLS_PYTHON="$CONFIG_TOOLS_DIR/bin/python"
staging=$(mktemp -d "$parent/.config-tools.XXXXXX")
trap 'rm -rf "$staging"' EXIT INT TERM

echo "Installing config tools..."
uv venv --python '>=3.11' "$staging"
uv pip install --python "$staging/bin/python" --requirements "$REQUIREMENTS"
if ! config_python_is_ready "$staging/bin/python"; then
  print -u2 "Error: installed config tools failed validation"
  exit 1
fi

rm -rf "$CONFIG_TOOLS_DIR"
mv "$staging" "$CONFIG_TOOLS_DIR"
trap - EXIT INT TERM
