#!/usr/bin/env bash
# scripts/install-zip.sh in a temp extensions directory: schema compile on unpack, no schema, missing compiler.
. "$(dirname "$0")/lib.sh"
command -v zip >/dev/null || { echo "zip is required for this test" >&2; exit 1; }
ext=$tmp/ext; target=$ext/$uuid
mk() { # DIR [withschema]
    mkdir -p "$1"
    printf '{"uuid":"%s","version-name":"1","name":"x","description":"x","shell-version":["51"]}\n' "$uuid" > "$1/metadata.json"
    echo "// new" > "$1/extension.js"
    [ -z "${2:-}" ] || { mkdir -p "$1/schemas"; cp "$root/$uuid"/schemas/*.gschema.xml "$1/schemas/"; }
}
mk "$tmp/s" schema; make_zip "$tmp/s" "$tmp/schema.zip"
mk "$tmp/n"; make_zip "$tmp/n" "$tmp/noschema.zip"
if unzip -Z1 "$tmp/schema.zip" | grep -q gschemas.compiled; then fail "test zip has a compiled schema"; fi

expect_rc 0 "install with schema" "$root/scripts/install-zip.sh" "$tmp/schema.zip" "$ext" "$uuid"
[ -s "$target/schemas/gschemas.compiled" ] && pass "gschemas.compiled created" || fail "gschemas.compiled missing"
expect_rc 0 "reinstall is idempotent" "$root/scripts/install-zip.sh" "$tmp/schema.zip" "$ext" "$uuid"
[ -s "$target/schemas/gschemas.compiled" ] && pass "still compiled after reinstall" || fail "compiled lost"

rm -rf "$ext"
expect_rc 0 "zip without a schema installs" "$root/scripts/install-zip.sh" "$tmp/noschema.zip" "$ext" "$uuid"
[ -f "$target/extension.js" ] && [ ! -e "$target/schemas" ] && pass "no schema, nothing compiled" || fail "no-schema layout"

# PATH without glib-compile-schemas: fails, old copy kept, no staging leftovers
bin=$tmp/bin; mkdir -p "$bin"
for t in bash unzip jq grep mktemp rm mv mkdir dirname; do ln -s "$(command -v $t)" "$bin/$t"; done
echo old > "$target/marker"
PATH=$bin expect_rc 1 "missing glib-compile-schemas fails" "$bin/bash" "$root/scripts/install-zip.sh" "$tmp/schema.zip" "$ext" "$uuid"
expect_out 'glib2-devel' "message names the package"
[ "$(cat "$target/marker" 2>/dev/null)" = old ] && pass "existing copy kept" || fail "existing copy replaced"
[ -z "$(ls -A "$ext" | grep -v "^$uuid\$")" ] && pass "no staging directory left" || fail "staging leftovers"
finish
