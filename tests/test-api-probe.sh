#!/usr/bin/env bash
# scripts/api-probe.sh against a fake Shell source tree, and tests/shell-api.txt kept in step
# with the extension's code. No network (PROBE_SRC / empty GRES_DIR / stub dnf).
. "$(dirname "$0")/lib.sh"
probe=$root/scripts/api-probe.sh
tab=$'\t'
src=$tmp/src; mkdir -p "$src/js/ui"
printf 'export let modalCount = 0;\nexport let layoutManager = null;\n' > "$src/js/ui/main.js"
printf 'class Overview {\n    toggle() {}\n}\n' > "$src/js/ui/overview.js"
run() { DATA=$1 PROBE_SRC=$2 "$probe"; }

printf 'js/ui/main.js\tmodalCount\tx\njs/ui/overview.js\t^    toggle\\(\tx\n' > "$tmp/ok.txt"
expect_rc 0 "probe: all found" run "$tmp/ok.txt" "$src"
expect_out 'found=2 missing=0 unverifiable=0' "probe: counts"

printf 'js/ui/main.js\tmodalCount\tx\njs/ui/overview.js\tshowApps\tx\n' > "$tmp/miss.txt"
expect_rc 1 "probe: a missing symbol fails" run "$tmp/miss.txt" "$src"
expect_out 'MISSING +js/ui/overview.js +showApps' "probe: table names the missing symbol"
expect_out 'found=1 missing=1' "probe: missing counted"

printf 'js/ui/main.js\tmodalCount\tx\njs/ui/nothere.js\tfoo\tx\n' > "$tmp/unver.txt"
expect_rc 0 "probe: an absent file is unverifiable, not a failure" run "$tmp/unver.txt" "$src"
expect_out 'unverifiable +js/ui/nothere.js' "probe: unverifiable listed"

# no sources at all: graceful skip
mkdir -p "$tmp/emptygres" "$tmp/bin"
printf '#!/bin/sh\necho "dnf stub: no source repos" >&2\nexit 1\n' > "$tmp/bin/dnf"; chmod +x "$tmp/bin/dnf"
expect_rc 0 "probe: sources unavailable exits 0" env DATA="$tmp/ok.txt" GRES_DIR="$tmp/emptygres" PROBE_DNF="$tmp/bin/dnf" "$probe"
expect_out 'API probe skipped: Shell sources unavailable' "probe: skip message"
expect_rc 0 "probe: PROBE_SRC pointing nowhere skips" run "$tmp/ok.txt" "$tmp/does-not-exist"
expect_out 'API probe skipped' "probe: skip message for a bad PROBE_SRC"

# bad data
printf 'js/ui/main.js\tmodalCount\n' > "$tmp/b1.txt";               expect_rc 2 "probe: two fields" run "$tmp/b1.txt" "$src"
printf 'js/ui/main.js\t\tx\n' > "$tmp/b2.txt";                      expect_rc 2 "probe: empty symbol" run "$tmp/b2.txt" "$src"
printf 'ui/main.js\tmodalCount\tx\n' > "$tmp/b3.txt";               expect_rc 2 "probe: file not under js/" run "$tmp/b3.txt" "$src"
printf 'js/ui/main.js\tmodal(Count\tx\n' > "$tmp/b4.txt";            expect_rc 2 "probe: invalid regex" run "$tmp/b4.txt" "$src"
printf 'js/ui/main.js\tmodalCount\tx\textra\n' > "$tmp/b5.txt";     expect_rc 2 "probe: four fields" run "$tmp/b5.txt" "$src"
printf '# only a comment\n' > "$tmp/b6.txt";                        expect_rc 2 "probe: no data lines" run "$tmp/b6.txt" "$src"
expect_rc 2 "probe: missing data file" run "$tmp/nope.txt" "$src"

# the real data file against the real code: each way must hold
data=$root/tests/shell-api.txt
ext=$root/$uuid
grep -v '^#' "$data" | grep -c . >/dev/null && pass "data file has lines" || fail "data file has lines"
rc=0; awk -F'\t' '!/^#/ && NF && NF != 3 {print "line " NR ": " NF " fields"; bad=1} END {exit bad}' "$data" || rc=1
[ $rc -eq 0 ] && pass "data file: three fields per line" || fail "data file: three fields per line"
# 1. every 'used in' token ("<file>: <token>") occurs literally in that file
rc=0
while IFS=$'\t' read -r f s w; do
    case $f in ''|'#'*) continue ;; esac
    jsf=${w%%:*}; tok=${w#*: }
    [ -f "$ext/$jsf" ] && grep -qF -- "$tok" "$ext/$jsf" || { echo "data line for $f '$s': '$tok' not in $jsf" >&2; rc=1; }
done < "$data"
[ $rc -eq 0 ] && pass "data file: every used-in token is in the code" || fail "data file: every used-in token is in the code"
# 2. every Shell member chain the code touches has a data line
tokens=$(grep -v '^#' "$data" | awk -F'\t' 'NF==3 {sub(/^[^:]*: /, "", $3); print $3}' | sort -u)
rc=0
for jsf in extension.js prefs.js actions.js; do
    while IFS= read -r chain; do
        [ -z "$chain" ] && continue
        grep -qxF -- "$chain" <<<"$tokens" || { echo "$jsf uses $chain but tests/shell-api.txt has no line for it" >&2; rc=1; }
    done < <(grep -v '^ *//' "$ext/$jsf" | grep -oE 'Main(\.[A-Za-z_]+)+' | sort -u)
done
[ $rc -eq 0 ] && pass "code: every Main.* chain has a data line" || fail "code: every Main.* chain has a data line"
# 3. every resource:/// import of Shell code has its file in the data file
rc=0
for jsf in extension.js prefs.js actions.js; do
    while IFS= read -r p; do
        case $p in
            resource:///org/gnome/shell/*) rel=js/${p#resource:///org/gnome/shell/} ;;
            resource:///org/gnome/Shell/Extensions/js/*) rel=js/${p#resource:///org/gnome/Shell/Extensions/js/} ;;
            *) continue ;;
        esac
        awk -F'\t' -v f="$rel" '$1 == f {ok=1} END {exit !ok}' "$data" || { echo "$jsf imports $p but no data line names $rel" >&2; rc=1; }
    done < <(grep -oE "resource:///[A-Za-z0-9_./-]+\.js" "$ext/$jsf" | sort -u)
done
[ $rc -eq 0 ] && pass "code: every Shell import has a data line" || fail "code: every Shell import has a data line"
finish
