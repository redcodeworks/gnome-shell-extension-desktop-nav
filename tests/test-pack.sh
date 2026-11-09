#!/usr/bin/env bash
# `just pack` output: the zip holds LICENSE, actions.js, extension.js, metadata.json, prefs.js and the schema XML (nothing else, no gschemas.compiled),
# the manifest script accepts it, and the EGO pre-flight sees the license in the zip.
. "$(dirname "$0")/lib.sh"
command -v gnome-extensions >/dev/null && command -v just >/dev/null || { echo "SKIP: gnome-extensions or just missing"; exit 0; }
cd "$root" || exit 1
expect_rc 0 "just pack" just pack
zip=dist/$uuid.shell-extension.zip
list=$(unzip -Z1 "$zip" | LC_ALL=C sort | tr '\n' ' ')
[ "$list" = "LICENSE actions.js extension.js metadata.json prefs.js schemas/ schemas/org.gnome.shell.extensions.desktop-mouse-nav.gschema.xml " ] && pass "zip holds exactly the expected files (schema XML, no compiled schema)" || fail "zip contents: $list"
[ "$(unzip -p "$zip" LICENSE | sha256sum)" = "$(sha256sum < LICENSE)" ] && pass "LICENSE in the zip equals the repository file" || fail "LICENSE differs"
expect_rc 0 "manifest from the packed zip" scripts/make-manifest.sh "$uuid" "$zip" "$tmp/manifest.json"
[ "$(jq -r .zip "$tmp/manifest.json")" = "$uuid.shell-extension.zip" ] && pass "manifest names the zip" || fail "manifest zip name"
expect_rc 0 "pre-flight on the packed zip" scripts/ego-preflight.sh "$zip" --repo-url https://github.com/redcodeworks/gnome-shell-extension-desktop-nav --license-dir "$root"
expect_out 'PASS \| files \| license file in the zip' "pre-flight sees the license"
finish
