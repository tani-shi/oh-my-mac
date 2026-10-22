#!/bin/zsh
# Temporary mitigation for the eMudhra intermediate CA key compromise until Apple
# ships a fixed /etc/ssl/cert.pem. https://emudhra.we-have-a-problem.com/
set -u

TEST_URL="https://dv-g3b-emudhra.we-have-a-problem.com/"
CERT_FILE="/etc/ssl/cert.pem"
DISTRUSTED_ROOTS='^=== .*/CN=(AAA Certificate Services|emSign ECC Root CA - G3)$'

report() {
  printf "  %-22s %s\n" "$1" "$2"
}

check_curl() {
  local exit_code=0
  "$1" -s -o /dev/null --max-time 15 "$TEST_URL" || exit_code=$?
  case $exit_code in
    0) echo EXPOSED ;;
    60) echo SAFE ;;
    *) echo "UNKNOWN (curl exit $exit_code)" ;;
  esac
}

check_git() {
  local output
  output=$(GIT_TERMINAL_PROMPT=0 "$1" ls-remote "$TEST_URL" 2>&1)
  case $output in
    *"SSL certificate problem"*|*"server certificate verification failed"*) echo SAFE ;;
    *"not valid: is this a git repository"*|*"not found"*) echo EXPOSED ;;
    *) echo "UNKNOWN (${output%%$'\n'*})" ;;
  esac
}

check_node() {
  node -e '
    fetch(process.argv[1], { signal: AbortSignal.timeout(15000) })
      .then(() => console.log("EXPOSED"))
      .catch((error) => {
        const code = error.cause?.code ?? error.name;
        console.log(/CERT|UNABLE_TO|SELF_SIGNED/.test(code) ? "SAFE" : `UNKNOWN (${code})`);
      });
  ' "$TEST_URL"
}

check_python() {
  "$@" -c '
import ssl, sys, urllib.error, urllib.request
try:
    urllib.request.urlopen(sys.argv[1], timeout=15)
    print("EXPOSED")
except urllib.error.HTTPError:
    print("EXPOSED")
except urllib.error.URLError as error:
    print("SAFE" if isinstance(error.reason, ssl.SSLCertVerificationError) else f"UNKNOWN ({error.reason})")
' "$TEST_URL"
}

check() {
  local result exposed=0
  print "Connecting to $TEST_URL (SAFE = connection refused):"
  for name in /usr/bin/curl /usr/bin/git node /usr/bin/python3 "uv python"; do
    case $name in
      /usr/bin/curl) result=$(check_curl /usr/bin/curl) ;;
      /usr/bin/git) result=$(check_git /usr/bin/git) ;;
      node) command -v node &>/dev/null && result=$(check_node) || result=SKIP ;;
      /usr/bin/python3) result=$(check_python /usr/bin/python3) ;;
      "uv python") command -v uv &>/dev/null && result=$(check_python uv run --no-project python) || result=SKIP ;;
    esac
    report "$name" "$result"
    [[ $result == EXPOSED ]] && exposed=1
  done
  if (( exposed )); then
    print -u2 "Some tools still trust the compromised CA. Run 'make fix-cert-pem' and update the tools above."
    return 1
  fi
}

fix() {
  if ! grep -Eq "$DISTRUSTED_ROOTS" "$CERT_FILE"; then
    print "$CERT_FILE already excludes the distrusted roots"
    return 0
  fi
  print "Removing distrusted roots from $CERT_FILE (backup: $CERT_FILE.bak)"
  sudo cp -p "$CERT_FILE" "$CERT_FILE.bak" || return 1
  awk -v pattern="$DISTRUSTED_ROOTS" '
    /^(###|===) / { skip = 0 }
    $0 ~ pattern { skip = 1 }
    !skip
  ' "$CERT_FILE.bak" | sudo tee "$CERT_FILE" >/dev/null || return 1
  print "Done. Restore with: sudo cp -p $CERT_FILE.bak $CERT_FILE"
}

case "${1:-}" in
  check) check ;;
  fix) fix ;;
  *) print -u2 "Usage: $0 check|fix"; exit 2 ;;
esac
