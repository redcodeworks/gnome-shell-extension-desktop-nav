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
  'shell-back': 'none', 'shell-forward': 'none',
};
const out = {
  schema: a.SCHEMA_ID, ids: a.ACTION_IDS,
  keys: a.CONTEXTS.flatMap(c => a.BUTTONS.map(b => a.settingsKey(c, b))),
  // button x context x (desktop set to, anywhere set to) -> picked action
  defaults: Object.fromEntries(a.BUTTONS.flatMap(b => [true, false].map(d =>
    [`${b}/${d ? 'desktop' : 'elsewhere'}`, a.pickAction(k => table[k], d, b)]))),
  anywhereOnly: a.pickAction(k => ({'desktop-back': 'none', 'shell-back': 'toggle-overview'})[k], true, 'back'),
  desktopWins: a.pickAction(k => ({'desktop-forward': 'next-workspace', 'shell-forward': 'toggle-overview'})[k], true, 'forward'),
  shellOnly: a.pickAction(k => ({'desktop-back': 'prev-workspace', 'shell-back': 'toggle-overview'})[k], false, 'back'),
  contexts: a.CONTEXTS,
  ctx: [[false,false,true],[false,false,false],[true,false,false],[true,true,false]].map(([o,g,d]) =>
    a.pointerContext({overviewVisible: o, appGridShowing: g, onEmptyDesktop: d})),
  asDesktop: ['desktop','overview','app-grid','shell'].map(c => a.treatAsDesktop(c)),
  overviewFallback: a.pickAction(k => ({'desktop-back': 'none', 'shell-back': 'next-workspace'})[k], a.treatAsDesktop('overview'), 'back'),
  resolve: [['prev-workspace','app-grid'],['next-workspace','app-grid'],['toggle-overview','app-grid'],
    ['prev-workspace','overview'],['next-workspace','desktop']].map(([x,c]) => a.resolveAction(x, c)),
  pages: [[0,5,-1],[0,5,1],[2,5,-1],[2,5,1],[4,5,1],[4,5,-1],[0,1,1],[0,1,-1],[0,0,1],[0,0,-1],[-1,0,1],[7,5,1],[null,5,1]]
    .map(([c,n,s]) => a.pageTarget(c, n, s)),
  ws: [[0,4,-1,0],[0,4,-1,1],[3,4,1,0],[3,4,1,1],[1,4,-1,0],[1,4,1,1],[0,1,1,1],[0,1,-1,1],[0,1,1,0],[0,0,1,1],[5,4,1,1]]
    .map(([i,n,s,w]) => a.workspaceTarget(i, n, s, !!w)),
  log: [a.debugLine(false,'back','desktop','none','ran'), a.debugLine(true,'back','app-grid','prev-workspace','at-end')],
  boolKeys: a.BOOLEAN_KEYS,
  unknown: a.pickAction(() => 'rm-rf', true, 'back'),
  gate: Object.fromEntries([[1,1],[1,0],[0,1],[0,0]].flatMap(([o,g]) =>
    [[true,true],[true,false],[false,false]].map(([v,grid]) =>
      [`flags${o}${g}/visible${+v}grid${+grid}`, a.overviewAllowed({overviewVisible: v, appGridShowing: grid}, {inOverview: !!o, inAppGrid: !!g})]))),
  switches: a.OVERVIEW_SWITCHES.map(r => r[0]),
};
console.log(JSON.stringify(out));
JS
node "$tmp/js/dump.mjs" > "$tmp/dump.json" || { fail "node could not run actions.js"; finish; exit 1; }
d() { jq -r "$1" "$tmp/dump.json"; }

[ "$(d .schema)" = "$(jq -r '.["settings-schema"]' "$ext/metadata.json")" ] && pass "metadata settings-schema equals SCHEMA_ID" || fail "settings-schema differs from actions.js"
grep -q "<schema id=\"$(d .schema)\"" "$xml" && pass "schema XML declares that id" || fail "schema id missing in the XML"

# keys: each key and its default, parsed from the XML
awk -F'"' '/<key name=/ {k=$2} /<default>/ {gsub(/.*<default>\x27?|\x27?<\/default>.*/, ""); print k, $0}' "$xml" | sort > "$tmp/defaults"
want=$'debug-log false\ndesktop-back prev-workspace\ndesktop-forward next-workspace\nshell-back none\nshell-forward none\nwork-in-app-grid false\nwork-in-overview false\nwrap-workspaces false'
[ "$(cat "$tmp/defaults")" = "$want" ] && pass "schema defaults: desktop back/forward switch workspaces, shell is none, debug-log and wrap-workspaces off" || { fail "schema defaults"; cat "$tmp/defaults" >&2; }
[ "$(d '(.keys + .boolKeys)|sort|join(" ")')" = "$(cut -d' ' -f1 "$tmp/defaults" | tr '\n' ' ' | sed 's/ $//')" ] && pass "schema keys equal actions.js keys" || fail "schema keys differ from actions.js"

# choices of every key equal the action ids
ids=$(d '.ids|sort|join(" ")')
bad=0
for k in $(d '.keys[]'); do
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

# every string default is a valid index into the action list (prefs.js maps it to a row)
for k in $(d '.keys[]'); do
    v=$(grep "^$k " "$tmp/defaults" | cut -d' ' -f2)
    [ "$(jq -r --arg v "$v" '.ids|index($v)' "$tmp/dump.json")" != null ] && pass "default of $k ($v) is in the action list" || fail "default of $k ($v) not in the action list"
done

[ "$(d '.contexts|join(" ")')" = "desktop shell" ] && pass "contexts are desktop and shell" || fail "contexts"
[ "$(d .shellOnly)" = toggle-overview ] && pass "shell surface: only the shell action" || fail "shell-only"
[ "$(d '.ctx|join(" ")')" = "desktop shell overview app-grid" ] && pass "pointer context: desktop, shell, overview, app-grid" || fail "pointer context"
[ "$(d '.asDesktop|map(tostring)|join(" ")')" = "true true true false" ] && pass "overview and app grid count as the desktop" || fail "treatAsDesktop"
[ "$(d .overviewFallback)" = next-workspace ] && pass "overview: desktop none falls back to the shell action" || fail "overview fallback"
[ "$(d '.resolve|map(if .type == "page" then "page\(.step)" else .id end)|join(" ")')" = "page-1 page1 toggle-overview prev-workspace next-workspace" ] && pass "app grid: prev/next workspace page the grid, others as bound" || fail "resolveAction"
[ "$(d '.pages|map(tostring)|join(" ")')" = "null 1 1 3 null 3 null null null null null null null" ] && pass "page target: start, middle, end, one page, zero pages, bad input, no wrap" || { fail "pageTarget"; d '.pages|tostring' >&2; }
[ "$(d '.ws|map(tostring)|join(" ")')" = "null 3 null 0 0 2 null null null null null" ] && pass "workspace target: first, middle, last, one workspace, wrap on and off" || { fail "workspaceTarget"; d '.ws|tostring' >&2; }
[ "$(d '.log[0]')" = null ] && [ "$(d '.log[1]')" = "desktop-mouse-nav: button=back context=app-grid action=prev-workspace result=at-end" ] && pass "debug line is null when off, one line when on" || fail "debugLine"
# the only console.debug is behind the flag
[ "$(grep -c 'console\.' "$ext/extension.js")" = 1 ] && grep -B3 'console\.debug' "$ext/extension.js" | grep -q 'if (line)' && grep -B6 'console\.debug' "$ext/extension.js" | grep -q 'if (this._debug)' && pass "extension.js logs once, behind this._debug and debugLine" || fail "logging is not gated by the flag"
grep -q "get_boolean('debug-log')" "$ext/extension.js" && grep -q "get_boolean('wrap-workspaces')" "$ext/extension.js" && pass "extension.js caches debug-log and wrap-workspaces" || fail "flags not cached"
grep -q "settings.get_\|_settings.get_" <(sed -n '/^    _onCapturedEvent(event)/,$p' "$ext/extension.js") && fail "a press reads GSettings" || pass "no GSettings read in the press path"
grep -qE "anywhere" "$ext/extension.js" "$ext/prefs.js" "$ext/actions.js" "$xml" && fail "anywhere still in the sources" || pass "no 'anywhere' left in the sources"

# overview gate
g() { d ".gate[\"$1\"]"; }
[ "$(g flags00/visible1grid1)" = false ] && [ "$(g flags10/visible1grid1)" = false ] && [ "$(g flags01/visible1grid1)" = true ] && pass "app grid showing: only with work-in-app-grid" || fail "gate: app grid"
[ "$(g flags00/visible1grid0)" = false ] && [ "$(g flags01/visible1grid0)" = false ] && [ "$(g flags10/visible1grid0)" = true ] && pass "overview showing: only with work-in-overview" || fail "gate: overview"
[ "$(g flags00/visible0grid0)" = true ] && [ "$(g flags11/visible0grid0)" = true ] && pass "neither showing: always allowed" || fail "gate: neither"
grep -q "overviewAllowed" "$ext/extension.js" && pass "extension.js gates on overviewAllowed" || fail "extension.js does not gate"

# prefs.js must not use binding mappings (their GJS callbacks crashed the prefs process)
grep -nE "bind_with_mapping|\.bind\([^)]*,[^)]*,[^)]*,[^)]*," "$ext/prefs.js" >/dev/null && fail "prefs.js uses a binding mapping" || pass "prefs.js uses no binding mapping"
grep -qE "^import .* from 'gi://(Clutter|Meta|St|Shell)'" "$ext/prefs.js" && fail "prefs.js imports a Shell-only library" || pass "prefs.js imports only Adw/Gio/Gtk"

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
