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
const M = {shift: 1, ctrl: 4, alt: 8, super: 1 << 26, ignore: 2 | 16 | 256 | 512 | 1024 | 2048 | 4096};
const HYPER = 1 << 27, META = 1 << 28, MOD3 = 32, MOD5 = 128;
const R = (b, m, act) => a.makeRule(b, m, act);
const rulesBy = {
  desktop: [R(8, '', 'prev-workspace'), R(9, '', 'next-workspace'), R(8, 'ctrl', 'toggle-overview')],
  shell: [R(8, '', 'toggle-app-grid'), R(9, 'shift', 'next-workspace')],
  overview: [R(8, '', 'toggle-app-grid')],
  'app-grid': [R(8, '', 'prev-workspace'), R(9, '', 'next-workspace')],
};
const found = (ctx, b, m) => { const f = a.findRule(rulesBy, ctx, b, m); return f ? `${f.context}:${f.index}:${f.rule.action}` : null; };
const out = {
  schema: a.SCHEMA_ID, ids: a.ACTION_IDS, contexts: a.CONTEXTS,
  keys: a.CONTEXTS.map(a.rulesKey),
  boolKeys: a.BOOLEAN_KEYS,
  norm: ['', 'Shift+ctrl', 'super+alt+ctrl+shift', 'ctrl+ctrl', ' Ctrl + Shift ', 'hyper', 'ctrl+meta', 5, null].map(x => a.normalizeModifiers(x)),
  combos: a.MODIFIER_COMBOS.length, combo0: a.MODIFIER_COMBOS[0], comboUnique: new Set(a.MODIFIER_COMBOS.map(c => c[0])).size,
  comboAllNormal: a.MODIFIER_COMBOS.every(([m]) => a.normalizeModifiers(m) === m),
  fromState: [0, 1, 4, 8, 1 << 26, 1 | 4, 1 | 2, 4 | 16, 4 | 256, 4 | 1024].map(s => a.modifiersFromState(s, M, true)),
  fromStateOther: [HYPER, META, MOD3, MOD5, 4 | HYPER, 4 | META, 4 | 64].map(s => a.modifiersFromState(s, M, true)),
  fromStateLoose: [0, 4 | HYPER, 1 | 4 | 8 | (1 << 26)].map(s => a.modifiersFromState(s, a.GTK_MASKS, false)),
  names: [2, 8, 9, 10, 12].map(a.buttonName),
  unbind: [[1, ''], [3, ''], [1, 'ctrl'], [3, 'shift'], [2, ''], [2, 'ctrl'], [8, ''], [9, 'alt+super'], [12, ''], [0, ''], [8, 'bogus'], [2.5, ''], ['8', '']].map(([b, m]) => a.unbindableReason(b, m)),
  parsed: a.parseRules([[8, '', 'prev-workspace'], [9, 'shift+ctrl', 'next-workspace'], [1, '', 'none'], [3, '', 'none'], [2, '', 'none'], [2, 'alt', 'none'], [8, '', 'rm-rf'], [8, 'hyper', 'none'], [8, ''], 'x', [12, 'super', 'toggle-overview']]).map(r => [r.input.button, r.mods, r.action]),
  parseJunk: [a.parseRules(null), a.parseRules('x'), a.parseRules({})].map(r => r.length),
  serialized: a.serializeRules(a.parseRules([[9, 'Shift+ctrl', 'next-workspace']])),
  roundtrip: JSON.stringify(a.serializeRules(a.parseRules([[8, '', 'prev-workspace'], [9, 'ctrl+shift', 'none']]))),
  inputKind: a.makeRule(8, '', 'none').input.kind,
  dup: [[8, '', -1], [8, '', 0], [9, '', -1], [8, 'ctrl', -1], [8, 'Ctrl', -1], [8, 'shift', -1], [10, '', -1]].map(([b, m, e]) => a.findDuplicate(rulesBy.desktop, b, m, e)),
  match: [[8, ''], [8, 'ctrl'], [9, ''], [9, 'ctrl'], [8, null], [10, ''], [8, 'ctrl+shift']].map(([b, m]) => a.matchRule(rulesBy.desktop, b, m)),
  firstWins: a.matchRule([R(8, '', 'none'), R(8, '', 'toggle-overview')], 8, ''),
  uses: [8, 9, 10, 2, 1].map(b => a.anyRuleUsesButton(rulesBy, b)),
  usesEmpty: a.anyRuleUsesButton({desktop: [], shell: []}, 8),
  order: ['desktop', 'shell', 'overview', 'app-grid'].map(a.contextOrder),
  find: {
    desktopBack: found('desktop', 8, ''),
    desktopCtrlBack: found('desktop', 8, 'ctrl'),
    desktopFallsBackToShell: found('desktop', 9, 'shift'),
    desktopNoMatch: found('desktop', 9, 'ctrl'),
    shellOnly: found('shell', 8, ''),
    shellNoDesktop: found('shell', 8, 'ctrl'),
    overviewOnly: found('overview', 8, ''),
    overviewNoShell: found('overview', 9, 'shift'),
    appGridOnly: found('app-grid', 9, ''),
    unknownMods: found('desktop', 8, null),
  },
  ctx: [[false,false,true],[false,false,false],[true,false,false],[true,true,false]].map(([o,g,d]) =>
    a.pointerContext({overviewVisible: o, appGridShowing: g, onEmptyDesktop: d})),
  resolve: [['prev-workspace','app-grid'],['next-workspace','app-grid'],['toggle-overview','app-grid'],
    ['prev-workspace','overview'],['next-workspace','desktop']].map(([x,c]) => a.resolveAction(x, c)),
  pages: [[0,5,-1],[0,5,1],[2,5,-1],[2,5,1],[4,5,1],[4,5,-1],[0,1,1],[0,1,-1],[0,0,1],[0,0,-1],[-1,0,1],[7,5,1],[null,5,1]]
    .map(([c,n,s]) => a.pageTarget(c, n, s)),
  ws: [[0,4,-1,0],[0,4,-1,1],[3,4,1,0],[3,4,1,1],[1,4,-1,0],[1,4,1,1],[0,1,1,1],[0,1,-1,1],[0,1,1,0],[0,0,1,1],[5,4,1,1]]
    .map(([i,n,s,w]) => a.workspaceTarget(i, n, s, !!w)),
  log: [a.debugLine(false,8,'','desktop',null,'ran'),
    a.debugLine(true,8,'ctrl','app-grid',{context:'app-grid',index:1,rule:R(8,'ctrl','prev-workspace')},'at-end'),
    a.debugLine(true,9,'','shell',null,'propagated'), a.debugLine(true,9,null,'shell',null,'propagated')],
  gate: Object.fromEntries([[1,1],[1,0],[0,1],[0,0]].flatMap(([o,g]) =>
    [[true,true],[true,false],[false,false]].map(([v,grid]) =>
      [`flags${o}${g}/visible${+v}grid${+grid}`, a.overviewAllowed({overviewVisible: v, appGridShowing: grid}, {inOverview: !!o, inAppGrid: !!g})]))),
  switchKeys: Object.keys(a.CONTEXT_SWITCHES).map(c => a.CONTEXT_SWITCHES[c][0]),
  switchContexts: Object.keys(a.CONTEXT_SWITCHES),
};
console.log(JSON.stringify(out));
JS
node "$tmp/js/dump.mjs" > "$tmp/dump.json" || { fail "node could not run actions.js"; finish; exit 1; }
d() { jq -r "$1" "$tmp/dump.json"; }
eq() { # JQ-EXPR WANT NAME
    local got; got=$(d "$1"); [ "$got" = "$2" ] && pass "$3" || { fail "$3 (got: $got)"; }
}

[ "$(d .schema)" = "$(jq -r '.["settings-schema"]' "$ext/metadata.json")" ] && pass "metadata settings-schema equals SCHEMA_ID" || fail "settings-schema differs from actions.js"
grep -q "<schema id=\"$(d .schema)\"" "$xml" && pass "schema XML declares that id" || fail "schema id missing in the XML"

# keys: each key, its type and its default, parsed from the XML
awk -F'"' '/<key name=/ {k=$2; t=$4} /<default>/ {gsub(/.*<default>|<\/default>.*/, ""); print k "|" t "|" $0}' "$xml" | sort > "$tmp/defaults"
want=$'debug-log|b|false\nrules-app-grid|a(uss)|[]\nrules-desktop|a(uss)|[(8, \x27\x27, \x27prev-workspace\x27), (9, \x27\x27, \x27next-workspace\x27)]\nrules-overview|a(uss)|[]\nrules-shell|a(uss)|[]\nwork-in-app-grid|b|false\nwork-in-overview|b|false\nwrap-workspaces|b|false'
[ "$(cat "$tmp/defaults")" = "$want" ] && pass "schema keys and defaults: four a(uss) rule keys (desktop 8 prev, 9 next; others empty), booleans off" || { fail "schema keys and defaults"; cat "$tmp/defaults" >&2; }
for old in desktop-back desktop-forward shell-back shell-forward; do
    grep -q "\"$old\"" "$xml" && fail "old key $old still in the schema" || pass "old key $old is gone"
done
[ "$(d '(.keys + .boolKeys)|sort|join(" ")')" = "$(cut -d'|' -f1 "$tmp/defaults" | tr '\n' ' ' | sed 's/ $//')" ] && pass "schema keys equal actions.js keys" || fail "schema keys differ from actions.js"

# the compiled defaults read back through gsettings against a temp schema dir
if command -v glib-compile-schemas >/dev/null && command -v gsettings >/dev/null; then
    mkdir "$tmp/schemadir"; cp "$xml" "$tmp/schemadir/"; glib-compile-schemas --strict "$tmp/schemadir"
    gs() { GSETTINGS_BACKEND=memory gsettings --schemadir "$tmp/schemadir" "$@"; }
    sid=$(d .schema)
    [ "$(gs get "$sid" rules-desktop | sed 's/uint32 //')" = "[(8, '', 'prev-workspace'), (9, '', 'next-workspace')]" ] && pass "gsettings reads the desktop defaults back" || fail "gsettings desktop default: $(gs get "$sid" rules-desktop)"
    for k in rules-shell rules-overview rules-app-grid; do
        [ "$(gs get "$sid" $k)" = "@a(uss) []" ] && pass "gsettings reads $k as empty" || fail "gsettings $k: $(gs get "$sid" $k)"
    done
else
    echo "skip gsettings read-back (glib-compile-schemas or gsettings not installed)"
fi

# choices of the action ids (the rule keys are arrays, so ids are checked in parseRules)
eq '.ids|length > 5' true "action ids exist"
eq '.contexts|join(" ")' "desktop shell overview app-grid" "contexts are desktop, shell, overview, app-grid"
eq '.keys|join(" ")' "rules-desktop rules-shell rules-overview rules-app-grid" "one rules key per context"
eq '.switchKeys|join(" ")' "work-in-overview work-in-app-grid" "overview and app grid keep their switches"
eq '.switchContexts|join(" ")' "overview app-grid" "switches belong to the overview and app grid contexts"

# modifiers
eq '.norm|map(tostring)|join("|")' "|ctrl+shift|alt+ctrl+shift+super|ctrl|ctrl+shift|null|null|null|null" "modifier strings normalize to sorted parts (unknown parts and non-strings are null)"
eq '.combos' 16 "16 modifier combinations"
eq '.comboUnique' 16 "all combinations differ"
eq '.combo0|join("/")' "/None" "None comes first"
eq '.comboAllNormal' true "every combination is a normalized string"
eq '.fromState|map(tostring)|join("|")' "|shift|ctrl|alt|super|ctrl+shift|shift|ctrl|ctrl|ctrl" "state to modifiers: lock, num lock and button bits are ignored"
eq '.fromStateOther|map(tostring)|join("|")' "null|null|null|null|null|null|null" "Hyper, Meta and other modifier bits mean not exactly any rule"
eq '.fromStateLoose|map(tostring)|join("|")' "|ctrl|alt+ctrl+shift+super" "non-strict (preferences) reading looks at the four bits only"
eq '.names|join("|")' "Middle|Back|Forward|Button 10|Button 12" "button names"

# buttons
eq '.unbind|map(tostring)|join("|")' "The primary and secondary buttons cannot be used.|The primary and secondary buttons cannot be used.|The primary and secondary buttons cannot be used.|The primary and secondary buttons cannot be used.|The middle button needs at least one modifier.|null|null|null|null|Not a valid mouse button.|Unknown modifier.|Not a valid mouse button.|Not a valid mouse button." "buttons 1 and 3 are refused, middle needs a modifier, others are fine"

# rules: parse, serialize, duplicates, matching
eq '.parsed|map(join(","))|join(" ")' "8,,prev-workspace 9,ctrl+shift,next-workspace 2,alt,none 12,super,toggle-overview" "parseRules drops invalid tuples (buttons 1 and 3, bare middle, unknown id, bad modifier, bad shape)"
eq '.parseJunk|join(" ")' "0 0 0" "parseRules survives non-arrays"
eq '.serialized|tostring' '[[9,"ctrl+shift","next-workspace"]]' "serializeRules writes (button, normalized modifiers, action)"
eq .roundtrip '[[8,"","prev-workspace"],[9,"ctrl+shift","none"]]' "parse and serialize round-trip"
eq .inputKind button "a rule's input is a typed button input (open for other kinds)"
eq '.dup|map(tostring)|join(" ")' "0 -1 1 2 2 -1 -1" "duplicates: same button and modifiers (normalized), the edited rule itself is skipped"
eq '.match|map(tostring)|join(" ")' "0 2 1 -1 -1 -1 -1" "exact (button, modifiers) match; extra modifiers or unknown bits do not match"
eq .firstWins 0 "the first matching rule wins when duplicates exist"
eq '.uses|map(tostring)|join(" ")' "true true false false false" "anyRuleUsesButton"
eq .usesEmpty false "no rules, no button used"

# context resolution and fallback order
eq '.order|map(join(">"))|join(" ")' "desktop>shell shell overview app-grid" "resolution order: desktop then shell; the others only themselves"
eq '.find.desktopBack' "desktop:0:prev-workspace" "desktop: first rule wins"
eq '.find.desktopCtrlBack' "desktop:2:toggle-overview" "desktop: exact modifiers pick the ctrl rule"
eq '.find.desktopFallsBackToShell' "shell:1:next-workspace" "desktop: no desktop rule, the shell rule runs"
eq '.find.desktopNoMatch' null "desktop: nothing matches, the press propagates"
eq '.find.shellOnly' "shell:0:toggle-app-grid" "shell surfaces: only the shell rules"
eq '.find.shellNoDesktop' null "shell surfaces never use desktop rules"
eq '.find.overviewOnly' "overview:0:toggle-app-grid" "overview: its own rules, not the desktop or shell ones"
eq '.find.overviewNoShell' null "overview does not fall back to shell rules"
eq '.find.appGridOnly' "app-grid:1:next-workspace" "app grid: its own rules"
eq '.find.unknownMods' null "unknown modifier bits never match"
eq '.ctx|join(" ")' "desktop shell overview app-grid" "pointer context: desktop, shell, overview, app-grid"
eq '.resolve|map(if .type == "page" then "page\(.step)" else .id end)|join(" ")' "page-1 page1 toggle-overview prev-workspace next-workspace" "app grid: prev/next workspace page the grid, others as bound"
eq '.pages|map(tostring)|join(" ")' "null 1 1 3 null 3 null null null null null null null" "page target: start, middle, end, one page, zero pages, bad input, no wrap"
eq '.ws|map(tostring)|join(" ")' "null 3 null 0 0 2 null null null null null" "workspace target: first, middle, last, one workspace, wrap on and off"
eq '.log[0]' null "debug line is null when off"
eq '.log[1]' "desktop-mouse-nav: button=8 mods=ctrl context=app-grid rule=app-grid[1] action=prev-workspace result=at-end" "debug line: button, modifiers, context, rule, action, result"
eq '.log[2]' "desktop-mouse-nav: button=9 mods=none context=shell rule=none action=none result=propagated" "debug line without a rule"
eq '.log[3]' "desktop-mouse-nav: button=9 mods=other context=shell rule=none action=none result=propagated" "debug line with unknown modifier bits"

# the only console.debug is behind the flag
[ "$(grep -c 'console\.' "$ext/extension.js")" = 1 ] && grep -B3 'console\.debug' "$ext/extension.js" | grep -q 'if (line)' && grep -B6 'console\.debug' "$ext/extension.js" | grep -q 'if (this._debug)' && pass "extension.js logs once, behind this._debug and debugLine" || fail "logging is not gated by the flag"
grep -q "get_boolean('debug-log')" "$ext/extension.js" && grep -q "get_boolean('wrap-workspaces')" "$ext/extension.js" && pass "extension.js caches debug-log and wrap-workspaces" || fail "flags not cached"
grep -q "parseRules" "$ext/extension.js" && grep -q "rulesKey" "$ext/extension.js" && pass "extension.js caches parsed rules per context" || fail "rules not cached"
grep -q "settings.get_\|_settings.get_" <(sed -n '/^    _onCapturedEvent(event)/,$p' "$ext/extension.js") && fail "a press reads GSettings" || pass "no GSettings read in the press path"
grep -qE "anywhere|desktop-back|shell-forward" "$ext/extension.js" "$ext/prefs.js" "$ext/actions.js" "$xml" && fail "old key or context names still in the sources" || pass "no old key or context names left in the sources"
grep -q "button === 1 || button === 3" "$ext/extension.js" && pass "extension.js never touches buttons 1 and 3" || fail "buttons 1 and 3 not excluded in extension.js"
grep -q "SUPER_MASK" "$ext/extension.js" && grep -q "MOD1_MASK" "$ext/extension.js" && pass "extension.js reads Shift, Ctrl, Alt (MOD1) and Super from the event state" || fail "modifier masks missing"
grep -qiE "wheel|scroll" "$ext/extension.js" "$ext/prefs.js" "$ext/actions.js" && fail "wheel code present (a later brief)" || pass "no wheel code"

# overview gate
g() { d ".gate[\"$1\"]"; }
[ "$(g flags00/visible1grid1)" = false ] && [ "$(g flags10/visible1grid1)" = false ] && [ "$(g flags01/visible1grid1)" = true ] && pass "app grid showing: only with work-in-app-grid" || fail "gate: app grid"
[ "$(g flags00/visible1grid0)" = false ] && [ "$(g flags01/visible1grid0)" = false ] && [ "$(g flags10/visible1grid0)" = true ] && pass "overview showing: only with work-in-overview" || fail "gate: overview"
[ "$(g flags00/visible0grid0)" = true ] && [ "$(g flags11/visible0grid0)" = true ] && pass "neither showing: always allowed" || fail "gate: neither"
grep -q "overviewAllowed" "$ext/extension.js" && pass "extension.js gates on overviewAllowed" || fail "extension.js does not gate"

# prefs.js must not use binding mappings (their GJS callbacks crashed the prefs process)
grep -nE "bind_with_mapping|\.bind\([^)]*,[^)]*,[^)]*,[^)]*," "$ext/prefs.js" >/dev/null && fail "prefs.js uses a binding mapping" || pass "prefs.js uses no binding mapping"
# prefs.js runs in its own process: only Adw, Gio, Gtk and GLib from gi://, never Shell libraries
bad=$(grep -oE "from 'gi://[A-Za-z]+'" "$ext/prefs.js" | grep -vE "gi://(Adw|Gio|Gtk|GLib|GObject)'" || true)
[ -z "$bad" ] && pass "prefs.js imports only Adw/Gio/Gtk/GLib/GObject from gi://" || fail "prefs.js imports $bad"
grep -qE "gi://(Clutter|Meta|St|Shell)|resource:///org/gnome/shell/" "$ext/prefs.js" && fail "prefs.js imports a Shell-only module" || pass "prefs.js imports no Shell module"
grep -q "recursiveUnpack" "$ext/prefs.js" && grep -q "set_value" "$ext/prefs.js" && grep -q "'a(uss)'" "$ext/prefs.js" && pass "prefs.js reads with recursiveUnpack and writes set_value with a(uss)" || fail "prefs.js does not read/write a(uss) as designed"
grep -q "get_current_button" "$ext/prefs.js" && grep -q "get_current_event_state" "$ext/prefs.js" && grep -q "PropagationPhase.CAPTURE" "$ext/prefs.js" && pass "prefs.js detects the button in a capture-phase click gesture" || fail "detection gesture missing"
grep -q "Adw.ButtonRow" "$ext/prefs.js" && grep -q "list-add-symbolic" "$ext/prefs.js" && grep -q "user-trash-symbolic" "$ext/prefs.js" && pass "prefs.js has the add row and the delete button" || fail "add row or delete button missing"

# extension.js handles every action id; prefs.js takes the ids only from actions.js
for id in $(d '.ids[]|select(. != "none")'); do
    grep -q "'$id'" "$ext/extension.js" && pass "extension.js handles $id" || fail "extension.js does not handle $id"
    grep -q "'$id'" "$ext/prefs.js" && fail "prefs.js hard-codes $id (use actions.js)" || pass "prefs.js does not duplicate $id"
done
grep -q "from './actions.js'" "$ext/extension.js" && grep -q "from './actions.js'" "$ext/prefs.js" && pass "both import ./actions.js" || fail "missing actions.js import"
# every quoted action-like id handled in extension.js's switch must be a known id
for lit in $(grep -oE "case '[a-z-]+'" "$ext/extension.js" | cut -d"'" -f2); do
    case " $(d '.ids|join(" ")') " in *" $lit "*) ;; *) fail "extension.js handles unknown id $lit" ;; esac
done
finish
