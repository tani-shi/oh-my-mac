#!/bin/zsh
set -u

REPO="${0:A:h}/.."
[[ -f "$REPO/README.md" ]] || { print -u2 "missing $REPO/README.md"; exit 1 }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0 fail=0 current=""

check_files_equal() {
  if cmp -s "$2" "$3"; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    print -u2 "FAIL $current: $1"
    diff -u "$3" "$2" >&2
  fi
}

check_lacks() {
  if [[ "$2" != *"$3"* ]]; then
    pass=$(( pass + 1 ))
  else
    fail=$(( fail + 1 ))
    print -u2 "FAIL $current: $1"
    print -u2 "  expected to lack: $3"
  fi
}

run() {
  current="$1"
  "$2"
}

t_homebrew_packages_match_brewfile() {
  awk '
    /^(brew|cask) "/ {
      package = $0
      sub(/^[^"]*"/, "", package)
      sub(/".*$/, "", package)
      sub(/^.*\//, "", package)
      print package
    }
  ' "$REPO/Brewfile" | LC_ALL=C sort -u > "$tmp/brewfile-packages"

  awk '
    /^### Homebrew Packages / { in_packages = 1; next }
    /^### / && in_packages { exit }
    in_packages && /^\| [^|]+ \| [^|]+ \|$/ {
      packages = $0
      sub(/^\| [^|]+ \| /, "", packages)
      sub(/ \|$/, "", packages)
      if (packages == "Packages" || packages == "---") next
      count = split(packages, package, /, /)
      for (i = 1; i <= count; i++) print package[i]
    }
  ' "$REPO/README.md" | LC_ALL=C sort -u > "$tmp/readme-packages"

  check_files_equal "README lists every Brewfile package" \
    "$tmp/readme-packages" "$tmp/brewfile-packages"
}

t_public_make_targets_match_readme() {
  make -s -C "$REPO" help | \
    sed -E $'s/\033\\[[0-9;]*m//g' | \
    awk '/^  [a-zA-Z][a-zA-Z_-]*[[:space:]]/ { print $1 }' | \
    LC_ALL=C sort -u > "$tmp/help-targets"

  awk -F'|' '
    /^## Usage$/ { in_usage = 1; next }
    /^## / && in_usage { exit }
    in_usage && /^\| `make/ {
      command = $2
      while (match(command, /`make( [a-zA-Z][a-zA-Z_-]*)?`/)) {
        target = substr(command, RSTART + 1, RLENGTH - 2)
        sub(/^make ?/, "", target)
        if (target != "") print target
        command = substr(command, RSTART + RLENGTH)
      }
    }
  ' "$REPO/README.md" | LC_ALL=C sort -u > "$tmp/readme-targets"

  check_files_equal "README documents every public make target" \
    "$tmp/readme-targets" "$tmp/help-targets"

  local help_output
  help_output="$(<"$tmp/help-targets")"
  check_lacks "make help hides the internal converge target" "$help_output" "converge"
  check_lacks "make help has no agent-hosted upgrade entrypoint" "$help_output" "upgrade"
}

run "Homebrew package documentation" t_homebrew_packages_match_brewfile
run "public make target documentation" t_public_make_targets_match_readme

print
print "$pass passed, $fail failed"
(( fail == 0 ))
