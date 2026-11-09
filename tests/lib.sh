# Shared helpers for tests/test-*.sh (sourced). Never touches the real home or the network.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
uuid=desktop-mouse-nav@redcodeworks.github.io
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=0 passes=0
pass() { passes=$((passes+1)); echo "ok   $*"; }
fail() { fails=$((fails+1)); echo "FAIL $*" >&2; }
# expect_rc EXPECTED NAME CMD...  (output kept in $tmp/last.out)
expect_rc() {
    local want=$1 name=$2; shift 2
    "$@" > "$tmp/last.out" 2>&1; local rc=$?
    if [ "$rc" -eq "$want" ]; then pass "$name"; else fail "$name (exit $rc, wanted $want)"; sed 's/^/     | /' "$tmp/last.out" >&2; fi
}
expect_out() { # PATTERN NAME : last output must match
    if grep -qE -- "$1" "$tmp/last.out"; then pass "$2"; else fail "$2 (no match for: $1)"; sed 's/^/     | /' "$tmp/last.out" >&2; fi
}
finish() { echo "$passes passed, $fails failed"; [ "$fails" -eq 0 ]; }
# make_zip DIR ZIP : zip the CONTENTS of DIR
make_zip() { ( cd "$1" && zip -q -r -X "$2" . ); }
