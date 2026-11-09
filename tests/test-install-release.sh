#!/usr/bin/env bash
# scripts/install-release.sh with a stub gh and a temp extensions directory.
. "$(dirname "$0")/lib.sh"
command -v zip >/dev/null || { echo "zip is required for this test" >&2; exit 1; }
export STUB_LOG=$tmp/log STUB_RELEASES=$tmp/releases GH=$root/tests/stubs/gh-release UUID=$uuid RETRY_WAIT=0
export GNOME_EXTENSIONS_DIR=$tmp/ext
mkrel() { # DIR VERSION
    local src=$tmp/src-$2; mkdir -p "$src" "$1"
    printf '{"uuid":"%s","version-name":"%s","name":"x","description":"x","shell-version":["51"]}\n' "$uuid" "$2" > "$src/metadata.json"
    echo "// $2" > "$src/extension.js"
    make_zip "$src" "$1/$uuid.shell-extension.zip"
    ( cd "$1" && sha256sum "$uuid.shell-extension.zip" > "$uuid.shell-extension.zip.sha256" )
}
mkrel "$STUB_RELEASES/latest" 0.2.0; mkrel "$STUB_RELEASES/v0.1.0" 0.1.0
inst() { "$root/scripts/install-release.sh" "$@"; }
ver() { jq -r '.["version-name"]' "$tmp/ext/$uuid/metadata.json"; }

expect_rc 0 "help" inst help; expect_out 'Usage: just install-release' "help text"
expect_rc 1 "unknown option fails" inst --nope

expect_rc 0 "dry run" inst --dry-run; expect_out 'nothing installed' "dry run says so"
[ ! -e "$tmp/ext/$uuid" ] && pass "dry run installs nothing" || fail "dry run installed"

expect_rc 0 "install latest" inst; [ "$(ver)" = 0.2.0 ] && pass "latest installed" || fail "latest version"
[ -f "$tmp/ext/$uuid/extension.js" ] && pass "files unpacked" || fail "files"
expect_rc 0 "second run is idempotent" inst; expect_out 'already installed' "already installed message"
expect_rc 0 "named version" inst 0.1.0; [ "$(ver)" = 0.1.0 ] && pass "named version installed" || fail "named version"
expect_rc 0 "v-prefixed version" inst v0.1.0; expect_out 'already installed' "v prefix accepted"
expect_rc 1 "missing release fails" inst 9.9.9

# tampered zip: checksum must stop the install
rm -rf "$tmp/ext"; mkrel "$STUB_RELEASES/v0.3.0" 0.3.0; echo tamper >> "$STUB_RELEASES/v0.3.0/$uuid.shell-extension.zip"
expect_rc 1 "checksum mismatch fails" inst 0.3.0; expect_out 'checksum' "checksum message"
[ ! -e "$tmp/ext/$uuid" ] && pass "nothing installed after a mismatch" || fail "installed despite mismatch"

STUB_FAIL_DOWNLOADS=1 expect_rc 1 "download failure retried then reported" inst; expect_out 'attempt 3 of 3' "three attempts"
finish
