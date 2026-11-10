#!/usr/bin/env bash
# scripts/install-remote.sh (behind `just install`) with a stub gh and a temp extensions directory.
. "$(dirname "$0")/lib.sh"
command -v zip >/dev/null || { echo "zip is required for this test" >&2; exit 1; }
export STUB_LOG=$tmp/log STUB_RELEASES=$tmp/releases GH=$root/tests/stubs/gh-remote UUID=$uuid RETRY_WAIT=0
export GNOME_EXTENSIONS_DIR=$tmp/ext
mkrel() { # TAG VERSION [MARK] : release dir with zip + sha256 (+ manifest.json, which must be ignored)
    local d=$STUB_RELEASES/$1 src=$tmp/src-$1-${3:-}; mkdir -p "$src" "$d"
    printf '{"uuid":"%s","version-name":"%s","name":"x","description":"x","shell-version":["51"]}\n' "$uuid" "$2" > "$src/metadata.json"
    echo "// $1 $2 ${3:-}" > "$src/extension.js"
    make_zip "$src" "$d/$uuid.shell-extension.zip"
    ( cd "$d" && sha256sum "$uuid.shell-extension.zip" > "$uuid.shell-extension.zip.sha256" )
    echo '{}' > "$d/manifest.json"
}
inst() { "$root/scripts/install-remote.sh" "$@"; }
ver() { jq -r '.["version-name"]' "$tmp/ext/$uuid/metadata.json"; }
body() { cat "$tmp/ext/$uuid/extension.js"; }
reset() { rm -rf "$tmp/ext" "$STUB_RELEASES"; mkdir -p "$STUB_RELEASES"; }

reset
expect_rc 0 "help" inst help; expect_out 'Usage: just install ' "help text"
expect_rc 1 "unknown option fails" inst --nope; expect_out 'unknown option' "unknown option message"
expect_rc 1 "--testing with a version is a usage error" inst --testing 0.1.0; expect_out 'cannot be combined' "combination message"
expect_rc 1 "two versions are a usage error" inst 0.1.0 0.1.1

# no release at all
expect_rc 1 "no release at all fails" inst
expect_out 'no release' "says there is no release"; expect_out 'just install --testing' "points to --testing"; expect_out 'just install-local' "points to install-local"
expect_rc 1 "no testing build fails" inst --testing; expect_out 'no testing build' "says there is no testing build"

# latest release only
mkrel v0.1.1 0.1.1; echo v0.1.1 > "$STUB_RELEASES/_latest"
expect_rc 1 "--testing without a testing build fails" inst --testing
expect_rc 0 "dry run" inst --dry-run; expect_out 'nothing installed' "dry run says so"
[ ! -e "$tmp/ext/$uuid" ] && pass "dry run installs nothing" || fail "dry run installed"
expect_rc 0 "install latest release" inst; [ "$(ver)" = 0.1.1 ] && pass "release installed" || fail "release version"
[ -f "$tmp/ext/$uuid/extension.js" ] && pass "files unpacked" || fail "files"
[ ! -e "$tmp/ext/$uuid/manifest.json" ] && pass "manifest not downloaded" || fail "manifest installed"
expect_rc 0 "second run is idempotent" inst; expect_out 'already installed' "already installed message"
expect_rc 0 "named version" inst 0.1.1; expect_out 'already installed' "named version, same zip"
expect_rc 0 "v-prefixed version" inst v0.1.1; expect_out 'already installed' "v prefix accepted"
expect_rc 1 "missing release fails" inst 9.9.9

# testing prerelease only (same version-name, different zip)
reset; mkrel testing 0.2.0 a
expect_rc 1 "testing only: default has no release" inst; expect_out 'no release' "default ignores the prerelease"
expect_rc 0 "testing only: --testing installs" inst --testing; [ "$(ver)" = 0.2.0 ] && pass "testing installed" || fail "testing version"
expect_rc 0 "testing second run is idempotent" inst --testing; expect_out 'already installed' "testing already installed"

# a stamped rc testing build installs like any other (version-name is free text to the installer)
reset; mkrel testing 0.6.0-rc3 a
expect_rc 0 "rc-stamped testing zip installs" inst --testing; [ "$(ver)" = 0.6.0-rc3 ] && pass "rc version-name installed" || fail "rc version $(ver)"
expect_rc 0 "rc-stamped testing zip is idempotent" inst --testing; expect_out 'already installed' "rc zip already installed"
expect_rc 1 "rc testing build is not the default release" inst; expect_out 'no release' "default ignores the rc prerelease"

# both present: default picks the release, --testing the prerelease
reset; mkrel v0.1.1 0.1.1; echo v0.1.1 > "$STUB_RELEASES/_latest"; mkrel testing 0.2.0 b
expect_rc 0 "both: default" inst; [ "$(ver)" = 0.1.1 ] && pass "default picked the release" || fail "default picked $(ver)"
expect_rc 0 "both: --testing" inst --testing; [ "$(ver)" = 0.2.0 ] && pass "--testing picked the prerelease" || fail "testing picked $(ver)"
mkrel testing 0.2.0 c
expect_rc 0 "same version-name, new testing zip is reinstalled" inst --testing
expect_out 'Installed testing' "different zip of the same version installs"; grep -q 'testing 0.2.0 c' "$tmp/ext/$uuid/extension.js" && pass "new testing zip unpacked" || fail "stale testing zip"

# tampered zip: checksum must stop the install and keep the old copy
mkrel v0.3.0 0.3.0; echo v0.3.0 > "$STUB_RELEASES/_latest"; echo tamper >> "$STUB_RELEASES/v0.3.0/$uuid.shell-extension.zip"
expect_rc 1 "checksum mismatch fails" inst; expect_out 'checksum' "checksum message"
[ "$(ver)" = 0.2.0 ] && pass "old copy kept after a mismatch" || fail "old copy lost"

STUB_FAIL_DOWNLOADS=1 expect_rc 1 "download failure retried then reported" inst 0.1.1; expect_out 'attempt 3 of 3' "three attempts"
finish
