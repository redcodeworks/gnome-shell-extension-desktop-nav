#!/usr/bin/env bash
# Settings schema and action mapping: schema defaults, keys and choices against actions.js,
# button x context -> action, and that extension.js and prefs.js use the same action ids.
. "$(dirname "$0")/lib.sh"
command -v node >/dev/null || { echo "SKIP: node missing"; exit 0; }
ext="$root/$uuid"
xml="$ext/schemas/org.gnome.shell.extensions.desktop-mouse-nav.gschema.xml"

if command -v glib-compile-schemas >/dev/null; then
    expect_rc 0 "schema compiles (strict)" glib-compile-schemas --strict --dry-run "$ext/schemas"
else
    echo "skip glib-compile-schemas (not installed)"
fi

# actions.js has no imports: run it as a .mjs copy with plain node.
mkdir "$tmp/js"; cp "$ext/actions.js" "$tmp/js/actions.mjs"
cat > "$tmp/js/dump.mjs" <<'JS'
import * as a from './actions.mjs';
const table = {
  'desktop-back': 'prev-workspace', 'desktop-forward': 'next-workspace',
  'anywhere-back': 'none', 'anywhere-forward': 'none',
};
const out = {
  schema: a.SCHEMA_ID, ids: a.ACTION_IDS,
  keys: a.CONTEXTS.flatMap(c => a.BUTTONS.map(b => a.settingsKey(c, b))),
  // button x context x (desktop set to, anywhere set to) -> picked action
  defaults: Object.fromEntries(a.BUTTONS.flatMap(b => [true, false].map(d =>
    [`${b}/${d ? 'desktop' : 'elsewhere'}`, a.pickAction(k => table[k], d, b)]))),
  anywhereOnly: a.pickAction(k => ({'desktop-back': 'none', 'anywhere-back': 'toggle-overview'})[k], true, 'back'),
  desktopWins: a.pickAction(k => ({'desktop-forward': 'next-workspace', 'anywhere-forward': 'toggle-overview'})[k], true, 'forward'),
  unknown: a.pickAction(() => 'rm-rf', true, 'back'),
};
console.log(JSON.stringify(out));
JS
node "$tmp/js/dump.mjs" > "$tmp/dump.json" || { fail "node could not run actions.js"; finish; exit 1; }
d() { jq -r "$1" "$tmp/dump.json"; }

[ "$(d .schema)" = "$(jq -r '.["settings-schema"]' "$ext/metadata.json")" ] && pass "metadata settings-schema equals SCHEMA_ID" || fail "settings-schema differs from actions.js"
grep -q "<schema id=\"$(d .schema)\"" "$xml" && pass "schema XML declares that id" || fail "schema id missing in the XML"

# keys: each key and its default, parsed from the XML
awk -F'"' '/<key name=/ {k=$2} /<default>/ {gsub(/.*<default>.|.<\/default>.*/, ""); print k, $0}' "$xml" | sort > "$tmp/defaults"
want=$'anywhere-back none\nanywhere-forward none\ndesktop-back prev-workspace\ndesktop-forward next-workspace'
[ "$(cat "$tmp/defaults")" = "$want" ] && pass "schema defaults: desktop back/forward switch workspaces, anywhere is none" || { fail "schema defaults"; cat "$tmp/defaults" >&2; }
[ "$(d '.keys|sort|join(" ")')" = "$(cut -d' ' -f1 "$tmp/defaults" | tr '\n' ' ' | sed 's/ $//')" ] && pass "schema keys equal actions.js keys" || fail "schema keys differ from actions.js"

# choices of every key equal the action ids
ids=$(d '.ids|sort|join(" ")')
bad=0
for k in $(cut -d' ' -f1 "$tmp/defaults"); do
    c=$(awk -v k="$k" '$0 ~ "<key name=\"" k "\"" {on=1} on && /<choice / {match($0, /value=.[^\x27"]*/); print substr($0, RSTART+7, RLENGTH-7)} on && /<\/key>/ {on=0}' "$xml" | sort | tr '\n' ' ' | sed 's/ $//')
    [ "$c" = "$ids" ] || { bad=1; echo "key $k choices: $c" >&2; }
done
[ "$bad" = 0 ] && pass "every key's choices equal the action ids" || fail "schema choices differ from actions.js"

# mapping
[ "$(d '.defaults["back/desktop"]')" = prev-workspace ] && [ "$(d '.defaults["forward/desktop"]')" = next-workspace ] && pass "defaults on the desktop: back=prev, forward=next" || fail "desktop defaults"
[ "$(d '.defaults["back/elsewhere"]')" = none ] && [ "$(d '.defaults["forward/elsewhere"]')" = none ] && pass "defaults elsewhere: none (buttons stay with applications)" || fail "anywhere defaults"
[ "$(d .anywhereOnly)" = toggle-overview ] && pass "desktop 'none' falls back to the anywhere action" || fail "fallback"
[ "$(d .desktopWins)" = next-workspace ] && pass "desktop action wins on the desktop" || fail "desktop precedence"
[ "$(d .unknown)" = none ] && pass "unknown ids count as none" || fail "unknown id"

# extension.js handles every action id; prefs.js takes the ids only from actions.js
for id in $(d '.ids[]|select(. != "none")'); do
    grep -q "'$id'" "$ext/extension.js" && pass "extension.js handles $id" || fail "extension.js does not handle $id"
    grep -q "$id" "$ext/prefs.js" && fail "prefs.js hard-codes $id (use actions.js)" || pass "prefs.js does not duplicate $id"
done
grep -q "from './actions.js'" "$ext/extension.js" && grep -q "from './actions.js'" "$ext/prefs.js" && pass "both import ./actions.js" || fail "missing actions.js import"
# every quoted action-like id handled in extension.js's switch must be a known id
for lit in $(grep -oE "case '[a-z-]+'" "$ext/extension.js" | cut -d"'" -f2); do
    case " $(d '.ids|join(" ")') " in *" $lit "*) ;; *) fail "extension.js handles unknown id $lit" ;; esac
done
finish
