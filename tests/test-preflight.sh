#!/usr/bin/env bash
# scripts/ego-preflight.sh against passing and failing fixtures.
. "$(dirname "$0")/lib.sh"
command -v zip >/dev/null || { echo "zip is required for this test" >&2; exit 1; }
url=https://github.com/redcodeworks/gnome-shell-extension-desktop-nav
pf() { "$root/scripts/ego-preflight.sh" "$1" --repo-url "$url" --license-dir "$root"; }

mk() { # NAME : fresh fixture dir seeded from the real extension
    rm -rf "$tmp/f-$1"; mkdir -p "$tmp/f-$1"
    cp -r "$root/$uuid/." "$tmp/f-$1/"
    echo "$tmp/f-$1"
}
# nolog NAME : drop the extension's own gated console.log call from a fixture
nolog() { sed -i '/console\.log(this\._pressLine/d' "$tmp/f-$1/extension.js"; }
zipit() { rm -f "$tmp/$1.zip"; make_zip "$tmp/f-$1" "$tmp/$1.zip"; }
meta() { jq "$2" "$tmp/f-$1/metadata.json" > "$tmp/m" && mv "$tmp/m" "$tmp/f-$1/metadata.json"; }

mk good >/dev/null; zipit good
expect_rc 0 "the real extension passes" pf "$tmp/good.zip"
expect_out 'WARN \| code \| extension.js: one console.log behind if \(this._debug\)' "its single gated console.log is a warning"
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

mk log2 >/dev/null; nolog log2; printf "if (this._debug)\n    console.log('x');\n" >> "$tmp/f-log2/extension.js"; zipit log2
expect_rc 0 "one console.log behind if (this._debug) is only a warning" pf "$tmp/log2.zip"; expect_out 'WARN \| code.*behind if \(this._debug\)' "gated console.log warning shown"

mk log3 >/dev/null; nolog log3; printf "if (this._debug) {\n    console.log('x');\n}\nif (this._debug) {\n    console.log('y');\n}\n" >> "$tmp/f-log3/extension.js"; zipit log3
expect_rc 1 "two gated console.log calls fail" pf "$tmp/log3.zip"

mk log4 >/dev/null; nolog log4; printf "if (this._other) {\n    console.log('x');\n}\n" >> "$tmp/f-log4/extension.js"; zipit log4
expect_rc 1 "console.log behind another condition fails" pf "$tmp/log4.zip"

mk log5 >/dev/null; nolog log5; printf "if (this._debug) {\n    foo();\n    console.log('x');\n}\n" >> "$tmp/f-log5/extension.js"; zipit log5
expect_rc 1 "console.log not directly under the gate fails" pf "$tmp/log5.zip"

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

mk dev2 >/dev/null; meta dev2 '.["shell-version"] = ["51","52.beta","53.alpha"]'; zipit dev2
expect_rc 1 "two development entries fail" pf "$tmp/dev2.zip"; expect_out 'more than one development' "two dev entries message"

mk devhi >/dev/null; meta devhi '.["shell-version"] = ["51","53","52.beta"]'; zipit devhi
expect_rc 1 "stable major above the development entry fails" pf "$tmp/devhi.zip"; expect_out 'above the development' "stable above dev message"

mk devrc >/dev/null; meta devrc '.["shell-version"] = ["51","52.rc"]'; zipit devrc
expect_rc 1 "an .rc entry fails" pf "$tmp/devrc.zip"

mk don >/dev/null; meta don '. + {donations: {}}'; zipit don
expect_rc 1 "empty donations fails" pf "$tmp/don.zip"

mk vn >/dev/null; meta vn '.["version-name"] = "1.0-beta"'; zipit vn
expect_rc 1 "hyphen in version-name fails" pf "$tmp/vn.zip"

mk vn2 >/dev/null; meta vn2 '.["version-name"] = "0.6.1.rc3"'; zipit vn2
expect_rc 0 "the dotted rc form is a valid version-name" pf "$tmp/vn2.zip"
mk vn3 >/dev/null; meta vn3 '.["version-name"] = "0.6.1-rc3"'; zipit vn3
expect_rc 1 "the old hyphen rc form is refused" pf "$tmp/vn3.zip"
mk vn4 >/dev/null; meta vn4 '.["version-name"] = "..."'; zipit vn4
expect_rc 1 "a version-name of only periods fails" pf "$tmp/vn4.zip"
mk vn5 >/dev/null; meta vn5 '.["version-name"] = "12.345.678.9012.5"'; zipit vn5
expect_rc 1 "a 17-character version-name fails" pf "$tmp/vn5.zip"

mk gsc >/dev/null; mkdir "$tmp/f-gsc/schemas"; echo x > "$tmp/f-gsc/schemas/gschemas.compiled"; zipit gsc
expect_rc 1 "gschemas.compiled in the zip fails" pf "$tmp/gsc.zip"; expect_out 'gschemas.compiled' "compiled schema named"

# forbidden imports per file
mk impg >/dev/null; sed -i "1i import Gdk from 'gi://Gdk';" "$tmp/f-impg/extension.js"; zipit impg
expect_rc 1 "extension.js importing Gdk fails" pf "$tmp/impg.zip"; expect_out 'extension.js: imports Gdk, Gtk or Adw' "Gdk message"
mk impt >/dev/null; sed -i "1i import Gtk from 'gi://Gtk?version=4.0';" "$tmp/f-impt/extension.js"; zipit impt
expect_rc 1 "extension.js importing Gtk (with a version) fails" pf "$tmp/impt.zip"
mk impa >/dev/null; sed -i "1i import Adw from 'gi://Adw';" "$tmp/f-impa/extension.js"; zipit impa
expect_rc 1 "extension.js importing Adw fails" pf "$tmp/impa.zip"
mk impc >/dev/null; sed -i "1i import Clutter from 'gi://Clutter';" "$tmp/f-impc/prefs.js"; zipit impc
expect_rc 1 "prefs.js importing Clutter fails" pf "$tmp/impc.zip"; expect_out 'prefs.js: imports Clutter, Meta, St or Shell' "Clutter message"
for lib in Meta St Shell; do
    mk "imp$lib" >/dev/null; sed -i "1i import X from 'gi://$lib';" "$tmp/f-imp$lib/prefs.js"; zipit "imp$lib"
    expect_rc 1 "prefs.js importing $lib fails" pf "$tmp/imp$lib.zip"
done
mk impr >/dev/null; sed -i "1i import * as Main from 'resource:///org/gnome/shell/ui/main.js';" "$tmp/f-impr/prefs.js"; zipit impr
expect_rc 1 "prefs.js importing a Shell resource module fails" pf "$tmp/impr.zip"; expect_out 'Shell resource module' "resource message"
mk impx >/dev/null; sed -i "1i import Gio from 'gi://Gio';" "$tmp/f-impx/actions.js"; zipit impx
expect_rc 1 "actions.js importing anything fails" pf "$tmp/impx.zip"; expect_out 'actions.js: imports something' "actions message"
mk impy >/dev/null; sed -i "1i import {x} from './other.js';" "$tmp/f-impy/actions.js"; zipit impy
expect_rc 1 "actions.js importing a module fails" pf "$tmp/impy.zip"

# the allowed imports stay allowed (the real extension passes, see above); the Extensions resource in prefs.js is fine
grep -q "resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js" "$tmp/f-good/prefs.js" && pass "prefs.js uses the allowed Extensions resource import" || fail "prefs.js import changed"

# warnings
mk clip >/dev/null; echo "const c = St.Clipboard.get_default();" >> "$tmp/f-clip/extension.js"; zipit clip
expect_rc 0 "St.Clipboard is only a warning" pf "$tmp/clip.zip"; expect_out 'WARN \| code \| extension.js: St.Clipboard' "clipboard warning"
mk lc >/dev/null; echo "const [ok, data] = file.load_contents(null);" >> "$tmp/f-lc/extension.js"; zipit lc
expect_rc 0 "load_contents is only a warning" pf "$tmp/lc.zip"; expect_out 'load_contents/file_get_contents' "load_contents warning"
mk fgc >/dev/null; echo "const x = GLib.file_get_contents('/etc/hostname');" >> "$tmp/f-fgc/extension.js"; zipit fgc
expect_rc 0 "file_get_contents is only a warning" pf "$tmp/fgc.zip"; expect_out 'load_contents/file_get_contents' "file_get_contents warning"
mk l200 >/dev/null; printf '// %s\n' "$(printf 'x%.0s' $(seq 1 210))" >> "$tmp/f-l200/extension.js"; zipit l200
expect_rc 0 "a line over 200 characters is only a warning" pf "$tmp/l200.zip"; expect_out 'WARN \| code \| extension.js: 1 line\(s\) over 200' "long line warning"
expect_rc 0 "the real extension has no line over 200 characters" pf "$tmp/good.zip"; grep -q 'over 200' "$tmp/last.out" && fail "a line over 200 characters is in the real extension" || pass "no over-200 warning for the real extension"

# schema id and path
mk sid >/dev/null; sed -i 's/id="org.gnome.shell.extensions.desktop-mouse-nav"/id="org.example.nav"/' "$tmp/f-sid"/schemas/*.gschema.xml; zipit sid
expect_rc 1 "a schema id outside org.gnome.shell.extensions fails" pf "$tmp/sid.zip"; expect_out "schema id 'org.example.nav'" "schema id message"
mk spa >/dev/null; sed -i 's#path="/org/gnome/shell/extensions/desktop-mouse-nav/"#path="/org/example/nav/"#' "$tmp/f-spa"/schemas/*.gschema.xml; zipit spa
expect_rc 1 "a schema path outside /org/gnome/shell/extensions fails" pf "$tmp/spa.zip"; expect_out "schema path '/org/example/nav/'" "schema path message"
mk snp >/dev/null; sed -i 's# path="/org/gnome/shell/extensions/desktop-mouse-nav/"##' "$tmp/f-snp"/schemas/*.gschema.xml; zipit snp
expect_rc 0 "a schema without a path attribute passes" pf "$tmp/snp.zip"

# warnings only (still exit 0)
mk sm >/dev/null; meta sm '. + {"session-modes": ["user"]}'; zipit sm
expect_rc 0 "redundant session-modes is only a warning" pf "$tmp/sm.zip"; expect_out 'WARN \| metadata \| session-modes' "session-modes warning"

mk dev1 >/dev/null; meta dev1 '.["shell-version"] = ["50","51","52.beta"]'; zipit dev1
expect_rc 0 "one development entry passes" pf "$tmp/dev1.zip"

mk lic >/dev/null; cp "$root/LICENSE" "$tmp/f-lic/LICENSE"; zipit lic
expect_rc 0 "LICENSE in the zip passes" pf "$tmp/lic.zip"; expect_out 'PASS \| files \| license file in the zip' "license in zip noted"
expect_rc 0 "no LICENSE in the zip is only a warning" pf "$tmp/good.zip"; expect_out 'no LICENSE file in the zip: not stated in the guidelines \(unverified\)' "missing license warning"

mk dbg >/dev/null; echo "console.debug('x');" >> "$tmp/f-dbg/extension.js"; zipit dbg
expect_rc 0 "console.debug is only a warning" pf "$tmp/dbg.zip"; expect_out 'WARN \| code' "debug warning shown"

expect_rc 1 "license missing fails" "$root/scripts/ego-preflight.sh" "$tmp/good.zip" --repo-url "$url" --license-dir "$tmp"
finish
