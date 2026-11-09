#!/usr/bin/env bash
# scripts/ego-preflight.sh against passing and failing fixtures.
. "$(dirname "$0")/lib.sh"
command -v zip >/dev/null || { echo "zip is required for this test" >&2; exit 1; }
url=https://github.com/redcodeworks/gnome-shell-extension-desktop-nav
pf() { "$root/scripts/ego-preflight.sh" "$1" --repo-url "$url" --license-dir "$root"; }

mk() { # NAME : fresh fixture dir seeded from the real extension
    rm -rf "$tmp/f-$1"; mkdir -p "$tmp/f-$1"
    cp "$root/$uuid/extension.js" "$root/$uuid/metadata.json" "$tmp/f-$1/"
    echo "$tmp/f-$1"
}
zipit() { rm -f "$tmp/$1.zip"; make_zip "$tmp/f-$1" "$tmp/$1.zip"; }
meta() { jq "$2" "$tmp/f-$1/metadata.json" > "$tmp/m" && mv "$tmp/m" "$tmp/f-$1/metadata.json"; }

mk good >/dev/null; zipit good
expect_rc 0 "the real extension passes" pf "$tmp/good.zip"
expect_out 'Result: \*\*PASS' "pass report"

# fixtures that must FAIL
mk ver >/dev/null; meta ver '. + {version: 3}'; zipit ver
expect_rc 1 "version field fails" pf "$tmp/ver.zip"; expect_out 'version. field' "version field message"

mk extra >/dev/null; echo '#!/bin/sh' > "$tmp/f-extra/build.sh"; zipit extra
expect_rc 1 "build script in the zip fails" pf "$tmp/extra.zip"; expect_out 'build.sh' "extra file named"

mk po >/dev/null; echo x > "$tmp/f-po/de.po"; zipit po
expect_rc 1 ".po file fails" pf "$tmp/po.zip"

mk media >/dev/null; printf '\x89PNG' > "$tmp/f-media/icon.png"; zipit media
expect_rc 1 "media file fails" pf "$tmp/media.zip"

mk mini >/dev/null; { cat "$tmp/f-mini/extension.js"; printf 'const a = %s;\n' "$(printf '1,%.0s' $(seq 1 200))1"; } > "$tmp/m.js"; mv "$tmp/m.js" "$tmp/f-mini/extension.js"; zipit mini
expect_rc 1 "minified line fails" pf "$tmp/mini.zip"; expect_out 'over 300' "minified message"

mk disc >/dev/null; sed -i '/global.stage.disconnect/d' "$tmp/f-disc/extension.js"; zipit disc
expect_rc 1 "missed disconnect fails" pf "$tmp/disc.zip"; expect_out 'disconnect everything' "disconnect message"

mk lang >/dev/null; printf "import * as Lang from 'resource:///org/gnome/gjs/modules/lang.js';\n" >> "$tmp/f-lang/extension.js"; zipit lang
expect_rc 1 "deprecated module fails" pf "$tmp/lang.zip"

mk log >/dev/null; printf "console.log('x');\n" >> "$tmp/f-log/extension.js"; zipit log
expect_rc 1 "console.log fails" pf "$tmp/log.zip"

mk sub >/dev/null; printf "const p = Gio.Subprocess.new(['ls'], 0);\n" >> "$tmp/f-sub/extension.js"; zipit sub
expect_rc 1 "Gio.Subprocess fails" pf "$tmp/sub.zip"

mk modl >/dev/null; printf "const label = new St.Label({text: 'x'});\n" >> "$tmp/f-modl/extension.js"; zipit modl
expect_rc 1 "object created at module load fails" pf "$tmp/modl.zip"; expect_out 'module load' "module load message"

mk ctor >/dev/null
sed -i 's/^export default class DesktopMouseNav extends Extension {/&\n    constructor(metadata) {\n        super(metadata);\n        this._id = global.stage.connect("captured-event", () => {});\n    }/' "$tmp/f-ctor/extension.js"; zipit ctor
expect_rc 1 "connection in the constructor fails" pf "$tmp/ctor.zip"; expect_out 'constructor' "constructor message"

mk url >/dev/null; meta url '.url = "https://example.invalid/x"'; zipit url
expect_rc 1 "url differing from the repository fails" pf "$tmp/url.zip"

mk sv >/dev/null; meta sv '.["shell-version"] = ["51.1"]'; zipit sv
expect_rc 1 "non-major shell-version fails" pf "$tmp/sv.zip"

mk gn >/dev/null; meta gn '.uuid = "x@extensions.gnome.org"'; zipit gn
expect_rc 1 "gnome.org uuid fails" pf "$tmp/gn.zip"

mk bu >/dev/null; meta bu '.uuid = "no-at-sign"'; zipit bu
expect_rc 1 "invalid uuid fails" pf "$tmp/bu.zip"

mk sm >/dev/null; meta sm '. + {"session-modes": ["user"]}'; zipit sm
expect_rc 1 "unused session-modes fails" pf "$tmp/sm.zip"

mk don >/dev/null; meta don '. + {donations: {}}'; zipit don
expect_rc 1 "empty donations fails" pf "$tmp/don.zip"

mk vn >/dev/null; meta vn '.["version-name"] = "1.0-beta"'; zipit vn
expect_rc 1 "hyphen in version-name fails" pf "$tmp/vn.zip"

# warnings only (still exit 0)
mk dbg >/dev/null; zipit dbg
expect_rc 0 "console.debug is only a warning" pf "$tmp/dbg.zip"; expect_out 'WARN \| code' "debug warning shown"

expect_rc 1 "license missing fails" "$root/scripts/ego-preflight.sh" "$tmp/good.zip" --repo-url "$url" --license-dir "$tmp"
finish
