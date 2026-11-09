#!/usr/bin/env bash
# scripts/gnome-version-watch.sh with stub dnf and gh.
. "$(dirname "$0")/lib.sh"
export STUB_LOG=$tmp/log STUB_DNF_DIR=$tmp/dnf RELEASED_VER=45 REPO=o/r
export DNF=$root/tests/stubs/dnf GH=$root/tests/stubs/gh-issues
export STUB_BODY=$tmp/body STUB_TITLE=$tmp/title STUB_LABEL_CREATED=$tmp/labelmade
meta=$tmp/metadata.json; echo '{"shell-version":["51"]}' > "$meta"; export METADATA=$meta
pkg() { echo "gnome-shell|0|$1|$2|x86_64|$3"; } # VERSION RELEASE REPOID
reset() { rm -rf "$STUB_DNF_DIR" "$STUB_BODY" "$STUB_TITLE" "$STUB_LABEL_CREATED"; mkdir -p "$STUB_DNF_DIR"; : > "$STUB_LOG"
    unset STUB_LABEL_ISSUES STUB_TITLE_ISSUES STUB_LABELS; }
run() { "$root/scripts/gnome-version-watch.sh"; }

reset; pkg 51.1 1.fc45 updates > "$STUB_DNF_DIR/45"; pkg 51.1 1.fc46 rawhide > "$STUB_DNF_DIR/rawhide"
expect_rc 0 "51.1 against [51]: nothing to do" run; expect_out 'nothing to do' "listed major message"
[ ! -f "$STUB_TITLE" ] && pass "no issue for a listed major" || fail "issue created for a listed major"
expect_out 'no branched/beta release yet' "no beta yet is logged"
expect_out 'channel rawhide' "rawhide named as the source"

reset; pkg 52.alpha 1.fc46 rawhide > "$STUB_DNF_DIR/rawhide"
expect_rc 0 "52.alpha not listed: issue" run
[ "$(cat "$STUB_TITLE" 2>/dev/null)" = "Support GNOME Shell 52" ] && pass "issue title" || fail "issue title"
grep -q 'gnome-shell-0:52.alpha-1.fc46.x86_64' "$STUB_BODY" && pass "body has the NEVR" || fail "body NEVR"
grep -q 'rawhide' "$STUB_BODY" && pass "body has the repository" || fail "body repository"
grep -q 'devkit --wayland' "$STUB_BODY" && pass "body has the nested session checklist" || fail "checklist"
[ -f "$STUB_LABEL_CREATED" ] && pass "missing label is created" || fail "label creation"

reset; pkg 52~beta 1.fc46 rawhide > "$STUB_DNF_DIR/rawhide"
expect_rc 0 "52~beta (rpm tilde) counts as 52" run; [ "$(cat "$STUB_TITLE")" = "Support GNOME Shell 52" ] && pass "tilde major" || fail "tilde major"

reset; pkg 52.beta 1.fc46 updates-testing > "$STUB_DNF_DIR/46"; pkg 53.alpha 1.fc47 rawhide > "$STUB_DNF_DIR/rawhide"
expect_rc 0 "branched release exists: it wins over rawhide" run
expect_out 'channel branched' "branched named as the source"
[ "$(cat "$STUB_TITLE")" = "Support GNOME Shell 52" ] && pass "branched major used" || fail "branched major"

reset; pkg 9.1 1 rawhide > "$STUB_DNF_DIR/rawhide"; echo '{"shell-version":["10"]}' > "$meta"
expect_rc 0 "numeric comparison (9 < 10)" run; [ ! -f "$STUB_TITLE" ] && pass "9 vs 10 compared numerically" || fail "string comparison"
echo '{"shell-version":["51"]}' > "$meta"

reset
expect_rc 3 "nothing found anywhere: exit 3" run; [ ! -f "$STUB_TITLE" ] && pass "no issue when nothing found" || fail "issue on nothing"

reset; pkg '$(touch pwned)' 1 rawhide > "$STUB_DNF_DIR/rawhide"; cd "$tmp"
expect_rc 3 "hostile version string is rejected" run; [ ! -e "$tmp/pwned" ] && pass "version string never evaluated" || fail "version string was evaluated"

reset; pkg 52.alpha 1.fc46 rawhide > "$STUB_DNF_DIR/rawhide"; echo '[{"number":7,"title":"Support GNOME Shell 52"}]' > "$tmp/open.json"; export STUB_LABEL_ISSUES=$tmp/open.json
expect_rc 0 "open gnome-version issue: dedupe" run; expect_out 'issue exists' "dedupe message"; [ ! -f "$STUB_TITLE" ] && pass "no second issue (label)" || fail "duplicate issue"

reset; pkg 52.alpha 1.fc46 rawhide > "$STUB_DNF_DIR/rawhide"; echo '[{"number":8,"title":"Support GNOME Shell 52"}]' > "$tmp/open2.json"; export STUB_TITLE_ISSUES=$tmp/open2.json
expect_rc 0 "open issue with the same title: dedupe" run; [ ! -f "$STUB_TITLE" ] && pass "no second issue (title)" || fail "duplicate issue (title)"

reset; pkg 52.alpha 1.fc46 rawhide > "$STUB_DNF_DIR/rawhide"
DRY_RUN=1 expect_rc 0 "dry run" run; [ ! -f "$STUB_TITLE" ] && pass "dry run creates nothing" || fail "dry run created"
finish
