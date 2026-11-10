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
const SUPER = 1 << 26, MOD4 = 64;
const M = {shift: 1, ctrl: 4, alt: 8, super: SUPER | MOD4, ignore: 2 | 16 | 256 | 512 | 1024 | 2048 | 4096};
const HYPER = 1 << 27, META = 1 << 28, MOD3 = 32, MOD5 = 128;
const S = {shift: 1, ctrl: 4, alt: 8, super: SUPER, ignore: 2 | 16 | 256};
const R = (b, m, act) => a.makeRule(b, m, act);
const rulesBy = {
  desktop: [R(8, '', 'prev-workspace'), R(9, '', 'next-workspace'), R(8, 'ctrl', 'toggle-overview')],
  shell: [R(8, '', 'toggle-app-grid'), R(9, 'shift', 'next-workspace')],
  overview: [R(8, '', 'toggle-app-grid')],
  'app-grid': [R(8, '', 'prev-workspace'), R(9, '', 'next-workspace')],
};
const found = (ctx, b, m) => { const f = a.findRule(rulesBy, ctx, b, m); return f ? `${f.context}:${f.index}:${f.rule.action}` : null; };
const W = {threshold: 1, minInterval: 400};
const ev = (dir, amount, kind, time) => ({dir, amount, kind, time});
// run a list of events through the accumulator; returns 'F' (fired) or '.' per event
const run = (events, cfg = W) => {
  let st = a.newWheelState(); let o = '';
  for (const e of events) { const r = a.wheelStep(st, e, cfg); st = r.state; o += r.fire ? 'F' : '.'; }
  return o;
};
const reasons = (events, cfg = W) => {
  let st = a.newWheelState(); const o = [];
  for (const e of events) { const r = a.wheelStep(st, e, cfg); st = r.state; o.push(r.reason); }
  return o.join(',');
};
const out = {
  schema: a.SCHEMA_ID, ids: a.ACTION_IDS, contexts: a.CONTEXTS,
  keys: a.CONTEXTS.map(a.rulesKey),
  boolKeys: a.BOOLEAN_KEYS, wheelKeys: a.WHEEL_KEYS, wheelDefaults: a.WHEEL_DEFAULTS,
  wheelLimits: a.WHEEL_SETTINGS.map(([k, , , lo, hi]) => [k, lo, hi]),
  norm: ['', 'Shift+ctrl', 'super+alt+ctrl+shift', 'ctrl+ctrl', ' Ctrl + Shift ', 'hyper', 'ctrl+meta', 5, null].map(x => a.normalizeModifiers(x)),
  combos: a.MODIFIER_COMBOS.length, combo0: a.MODIFIER_COMBOS[0], comboUnique: new Set(a.MODIFIER_COMBOS.map(c => c[0])).size,
  comboAllNormal: a.MODIFIER_COMBOS.every(([m]) => a.normalizeModifiers(m) === m),
  fromState: [0, 1, 4, 8, 1 << 26, 1 | 4, 1 | 2, 4 | 16, 4 | 256, 4 | 1024, MOD4, SUPER | MOD4, 4 | MOD4, 4 | SUPER, 4 | SUPER | MOD4 | 2 | 16, 1 | 2 | 8 | MOD4].map(s => a.modifiersFromState(s, M, true)),
  fromStateOther: [HYPER, META, MOD3, MOD5, 4 | HYPER, 4 | META, MOD4 | HYPER].map(s => a.modifiersFromState(s, M, true)),
  fromStateLoose: [0, 4 | HYPER, 1 | 4 | 8 | (1 << 26)].map(s => a.modifiersFromState(s, a.GTK_MASKS, false)),
  names: [2, 4, 5, 8, 9, 10, 12].map(a.buttonName),
  wheelUnbind: [[4, ''], [5, ''], [4, 'ctrl'], [5, 'super'], [4, 'bogus']].map(([b, m]) => a.unbindableReason(b, m))
    .concat([a.unbindableReason(4, '', true), a.unbindableReason(2, '', true)]),
  wheelParsed: a.parseRules([[4, 'ctrl', 'next-workspace'], [5, '', 'prev-workspace'], [4, 'hyper', 'none'], [6, '', 'none'], [7, 'alt', 'none']])
    .map(r => [r.input.kind, r.input.direction ?? '-', r.input.button, r.mods, r.action].join(',')),
  kinds: [8, 4, 5, 2].map(b => a.makeRule(b, 'ctrl', 'none').input.kind),
  wheelDir: [4, 5, 8].map(a.wheelDirection),
  wheelMatch: [a.matchRule([R(4, 'ctrl', 'none'), R(5, '', 'none')], 4, 'ctrl'), a.matchRule([R(4, 'ctrl', 'none')], 5, 'ctrl'), a.matchRule([R(4, 'ctrl', 'none')], 4, ''),
    a.matchRule([R(5, '', 'none')], 5, '')],
  wheelUses: [a.anyRuleUsesButton({desktop: [R(4, 'ctrl', 'none')]}, 4), a.anyRuleUsesButton({desktop: [R(4, 'ctrl', 'none')]}, 5)],
  wheelDup: a.findDuplicate([R(4, 'ctrl', 'none')], 4, 'Ctrl'),
  wheelFind: (() => { const f = a.findRule({desktop: [], shell: [R(5, 'ctrl', 'next-workspace')], overview: [], 'app-grid': []}, 'desktop', 5, 'ctrl'); return f ? `${f.context}:${f.index}` : null; })(),
  roundtripWheel: JSON.stringify(a.serializeRules(a.parseRules([[4, 'Ctrl', 'prev-workspace'], [5, '', 'none']]))),
  scrollIn: [['up', 0, 0], ['down', 0, 0], ['left', 0, 0], ['right', 0, 0], ['smooth', 0, -0.4], ['smooth', 0, 2.5], ['smooth', 0.2, 0.2],
    ['smooth', 3, 1], ['smooth', 0, 0], ['smooth', NaN, 1], ['bogus', 0, 1], [undefined, 0, 0]]
    .map(([d, x, y]) => { const r = a.scrollInput(d, x, y); return r ? `${r.dir}:${r.amount}:${r.kind}` : null; }),
  cfg: [a.wheelConfig(1, 400), a.wheelConfig(0, 10), a.wheelConfig(99, 99999), a.wheelConfig(NaN, 'x'), a.wheelConfig(0.5, 250)].map(c => `${c.threshold}/${c.minInterval}`),
  // one notch fires at once; the next waits for the interval (events inside it are dropped and clear the sum)
  oneNotch: run([ev('down', 1, 'discrete', 1000)]),
  burst: run([1000, 1010, 1020, 1100, 1399].map(t => ev('down', 1, 'discrete', t))),
  afterInterval: run([1000, 1400, 1500, 1800].map(t => ev('down', 1, 'discrete', t))),
  freeSpin: run(Array.from({length: 100}, (_, i) => ev('down', 1, 'discrete', 1000 + i * 8))),
  smoothSum: run([0.3, 0.3, 0.3, 0.3].map((x, i) => ev('down', x, 'smooth', 1000 + i * 16))),
  smoothBurst: run(Array.from({length: 40}, (_, i) => ev('up', 0.25, 'smooth', 1000 + i * 10))),
  slowSmooth: run([ev('down', 0.6, 'smooth', 1000), ev('down', 0.6, 'smooth', 2000)]),
  directionChange: run([ev('down', 0.6, 'smooth', 1000), ev('up', 0.6, 'smooth', 1020), ev('up', 0.6, 'smooth', 1040)]),
  highThreshold: run([1000, 1020, 1040].map(t => ev('down', 1, 'discrete', t)), {threshold: 3, minInterval: 400}),
  duplicate: run([ev('down', 1, 'discrete', 5000), ev('down', 1, 'smooth', 5000)], {threshold: 2, minInterval: 100}),
  duplicateReason: reasons([ev('down', 1, 'discrete', 5000), ev('down', 1, 'smooth', 5000)], {threshold: 2, minInterval: 100}),
  notDuplicate: run([ev('down', 1, 'discrete', 5000), ev('down', 1, 'discrete', 5000), ev('down', 1, 'smooth', 5030)], {threshold: 2, minInterval: 100}),
  reasons: reasons([ev('down', 0.4, 'smooth', 1000), ev('down', 0.7, 'smooth', 1010), ev('down', 1, 'discrete', 1100), ev('down', 1, 'discrete', 1500)]),
  clockBack: run([ev('down', 1, 'discrete', 5000), ev('down', 1, 'discrete', 100)]),
  reset: (() => { let st = a.newWheelState(); st = a.wheelStep(st, ev('down', 0.6, 'smooth', 1000), W).state; st = a.wheelReset(st);
    return [a.wheelStep(st, ev('down', 0.6, 'smooth', 1010), W).fire, st.acc].join(','); })(),
  resetKeepsLimit: (() => { let st = a.wheelStep(a.newWheelState(), ev('down', 1, 'discrete', 1000), W).state; st = a.wheelReset(st);
    return a.wheelStep(st, ev('down', 1, 'discrete', 1100), W).reason; })(),
  emulated: [[2, 2], [0, 2], [3, 2], [2, 0], [undefined, 2], [2, undefined], ['x', 2], [2, 4]].map(([f, m]) => a.isEmulatedScroll(f, m)),
  meta: [a.scrollMeta('smooth', 1, 2), a.scrollMeta('up', undefined, undefined), a.scrollMeta(undefined, 0, 0x2a)],
  metaNote: a.wheelNote({kind: 'discrete', amount: 1, meta: a.scrollMeta('down', 1, 0)}, {acc: 0}),
  wlog: [a.debugLine(true, 4, 0x4, 'ctrl', 'desktop', {context: 'desktop', index: 1, rule: R(4, 'ctrl', 'next-workspace')}, 'held', 'accumulating', a.wheelNote({kind: 'smooth', amount: 0.5}, {acc: 0.5})),
    a.debugLine(true, 5, 0, '', 'desktop', null, 'ignored', 'no-rule-uses-button'), a.inputLabel(8)],
  unbind: [[1, ''], [3, ''], [1, 'ctrl'], [3, 'shift'], [2, ''], [2, 'ctrl'], [8, ''], [9, 'alt+super'], [12, ''], [0, ''], [8, 'bogus'], [2.5, ''], ['8', '']].map(([b, m]) => a.unbindableReason(b, m)),
  parsed: a.parseRules([[8, '', 'prev-workspace'], [9, 'shift+ctrl', 'next-workspace'], [1, '', 'none'], [3, '', 'none'], [2, '', 'none'], [2, 'alt', 'none'], [8, '', 'rm-rf'], [8, 'hyper', 'none'], [8, ''], 'x', [12, 'super', 'toggle-overview']]).map(r => [r.input.button, r.mods, r.action]),
  parseJunk: [a.parseRules(null), a.parseRules('x'), a.parseRules({})].map(r => r.length),
  serialized: a.serializeRules(a.parseRules([[9, 'Shift+ctrl', 'next-workspace']])),
  roundtrip: JSON.stringify(a.serializeRules(a.parseRules([[8, '', 'prev-workspace'], [9, 'ctrl+shift', 'none']]))),
  inputKind: a.makeRule(8, '', 'none').input.kind,
  dup: [[8, '', -1], [8, '', 0], [9, '', -1], [8, 'ctrl', -1], [8, 'Ctrl', -1], [8, 'shift', -1], [10, '', -1]].map(([b, m, e]) => a.findDuplicate(rulesBy.desktop, b, m, e)),
  match: [[8, ''], [8, 'ctrl'], [9, ''], [9, 'ctrl'], [8, null], [10, ''], [8, 'ctrl+shift']].map(([b, m]) => a.matchRule(rulesBy.desktop, b, m)),
  superMatch: [[SUPER], [MOD4], [SUPER | MOD4], [SUPER | 2], [MOD4 | 16], [4 | MOD4], [4 | SUPER | MOD4], [4], [0], [SUPER | 4], [MOD4 | 1]].map(([st]) =>
    a.matchRule([R(8, 'super', 'none'), R(9, 'ctrl+super', 'none')], 8, a.modifiersFromState(st, M, true))),
  superCtrlMatch: [[4 | SUPER], [4 | MOD4], [4 | SUPER | MOD4], [SUPER], [4]].map(([st]) =>
    a.matchRule([R(8, 'super', 'none'), R(9, 'ctrl+super', 'none')], 9, a.modifiersFromState(st, M, true))),
  noSuperRule: [[0], [2], [SUPER], [MOD4], [SUPER | MOD4], [4]].map(([st]) =>
    a.matchRule([R(8, '', 'none')], 8, a.modifiersFromState(st, M, true))),
  emptyContexts: ['overview', 'app-grid', 'desktop', 'shell'].map(c => a.findRule({desktop: [], shell: [], overview: [], 'app-grid': []}, c, 8, '')),
  hex: [0x40, 1 << 26, 0, 4 | 2048, 'x', null, -1].map(a.hexState),
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
  log: [a.debugLine(false,8,0,'','desktop',null,'ran'),
    a.debugLine(true,8,0x44,'ctrl','app-grid',{context:'app-grid',index:1,rule:R(8,'ctrl','prev-workspace')},'at-end'),
    a.debugLine(true,9,0,'','shell',null,'propagated','no-matching-rule'), a.debugLine(true,9,1<<27,null,'shell',null,'ignored','other-modifier-bits'),
    a.debugLine(true,10,0x40,'super','desktop',null,'ignored','no-rule-uses-button'),
    a.debugLine(true,8,SUPER,'super','desktop',{context:'desktop',index:0,rule:R(8,'super','next-workspace')},'ran')],
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
want=$'debug-log|b|false\nrules-app-grid|a(uss)|[]\nrules-desktop|a(uss)|[(8, \x27\x27, \x27prev-workspace\x27), (9, \x27\x27, \x27next-workspace\x27)]\nrules-overview|a(uss)|[]\nrules-shell|a(uss)|[]\nwheel-min-interval|d|400\nwheel-threshold|d|1.0\nwrap-workspaces|b|false'
[ "$(cat "$tmp/defaults")" = "$want" ] && pass "schema keys and defaults: four a(uss) rule keys (desktop 8 prev, 9 next; others empty), wheel threshold 1.0 and interval 400 ms, wrap and debug off, no overview or app grid switches" || { fail "schema keys and defaults"; cat "$tmp/defaults" >&2; }
for old in desktop-back desktop-forward shell-back shell-forward; do
    grep -q "\"$old\"" "$xml" && fail "old key $old still in the schema" || pass "old key $old is gone"
done
[ "$(d '(.keys + .boolKeys + .wheelKeys)|sort|join(" ")')" = "$(cut -d'|' -f1 "$tmp/defaults" | tr '\n' ' ' | sed 's/ $//')" ] && pass "schema keys equal actions.js keys" || fail "schema keys differ from actions.js"

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
eq '.boolKeys|join(" ")' "wrap-workspaces debug-log" "only the wrap and debug switches remain"
for gone in work-in-overview work-in-app-grid CONTEXT_SWITCHES overviewAllowed this._flags; do
    grep -rq "$gone" "$ext"/*.js "$xml" && fail "$gone is still in the sources" || pass "$gone is gone"
done
eq '.emptyContexts|map(tostring)|join(" ")' "null null null null" "a context with no rules does nothing"

# modifiers
eq '.norm|map(tostring)|join("|")' "|ctrl+shift|alt+ctrl+shift+super|ctrl|ctrl+shift|null|null|null|null" "modifier strings normalize to sorted parts (unknown parts and non-strings are null)"
eq '.combos' 16 "16 modifier combinations"
eq '.comboUnique' 16 "all combinations differ"
eq '.combo0|join("/")' "/None" "None comes first"
eq '.comboAllNormal' true "every combination is a normalized string"
eq '.fromState|map(tostring)|join("|")' "|shift|ctrl|alt|super|ctrl+shift|shift|ctrl|ctrl|ctrl|super|super|ctrl+super|ctrl+super|ctrl+super|alt+shift+super" "state to modifiers: lock, num lock and button bits are ignored; Super is SUPER_MASK or MOD4_MASK or both"
eq '.superMatch|map(tostring)|join(" ")' "0 0 0 0 0 -1 -1 -1 -1 -1 -1" "a Super rule matches with SUPER_MASK only, MOD4_MASK only or both (lock bits ignored), not without or with extra modifiers"
eq '.superCtrlMatch|map(tostring)|join(" ")' "1 1 1 -1 -1" "Ctrl+Super matches with either Super bit, not Ctrl or Super alone"
eq '.noSuperRule|map(tostring)|join(" ")' "0 0 -1 -1 -1 -1" "a rule without Super does not match when Super is held (either bit); lock bits ignored"
eq '.hex|join("|")' "0x40|0x4000000|0x0|0x804|unknown|unknown|0xffffffff" "raw state as hex"
eq '.fromStateOther|map(tostring)|join("|")' "null|null|null|null|null|null|null" "Hyper, Meta and other modifier bits mean not exactly any rule"
eq '.fromStateLoose|map(tostring)|join("|")' "|ctrl|alt+ctrl+shift+super" "non-strict (preferences) reading looks at the four bits only"
eq '.names|join("|")' "Middle|Wheel up|Wheel down|Back|Forward|Button 10|Button 12" "button names"

# the mouse wheel: rules, accumulation and rate limit
eq '.wheelDefaults|"\(.threshold)/\(.minInterval)"' "1/400" "wheel defaults in actions.js: threshold 1 notch, 400 ms"
eq '.wheelKeys|join(" ")' "wheel-threshold wheel-min-interval" "wheel setting keys"
eq '.wheelLimits|map(join(":"))|join(" ")' "wheel-threshold:0.1:20 wheel-min-interval:50:3000" "wheel setting limits"
grep -q '<range min="0.1" max="20"/>' "$xml" && grep -q '<range min="50" max="3000"/>' "$xml" && pass "schema ranges equal the limits in actions.js" || fail "schema ranges differ from WHEEL_SETTINGS"
eq '.wheelUnbind|map(tostring)|join("|")' 'Wheel rules need a modifier unless "Require a modifier" is turned off.|Wheel rules need a modifier unless "Require a modifier" is turned off.|null|null|Unknown modifier.|null|The middle button needs at least one modifier.' "wheel rules need a modifier by default; a stored bare wheel rule is the explicit opt-out (middle still refused)"
eq '.wheelParsed|join(" ")' "wheel,up,4,ctrl,next-workspace wheel,down,5,,prev-workspace button,-,6,,none button,-,7,alt,none" "parseRules keeps wheel rules (also without modifier, the explicit choice) and 6 and 7 stay plain buttons"
eq '.kinds|join(" ")' "button wheel wheel button" "buttons 4 and 5 are wheel inputs, others buttons"
eq '.wheelDir|map(tostring)|join(" ")' "up down null" "wheel direction of 4, 5, others"
eq '.wheelMatch|map(tostring)|join(" ")' "0 -1 -1 0" "wheel rules match direction and exact modifiers"
eq '.wheelUses|map(tostring)|join(" ")' "true false" "anyRuleUsesButton tells wheel up from wheel down"
eq .wheelDup 0 "a second wheel rule with the same direction and modifiers is a duplicate"
eq .wheelFind "shell:0" "wheel rules use the same context fallback (desktop falls back to shell)"
eq .roundtripWheel '[[4,"ctrl","prev-workspace"],[5,"","none"]]' "wheel rules round-trip through parse and serialize (the 0.3.0 tuple shape)"
eq '.scrollIn|map(tostring)|join(" ")' "up:1:discrete down:1:discrete null null up:0.4:smooth down:2.5:smooth down:0.2:smooth null null null null null" "scroll input: up and down, horizontal and tilt ignored, smooth by delta (vertical wins ties), bad input null"
eq '.cfg|join(" ")' "1/400 0.1/50 20/3000 1/400 0.5/250" "wheelConfig clamps to the limits and falls back to defaults"
eq .oneNotch F "one notch fires at once"
eq .burst "F...." "a burst fires once; events inside the interval are dropped"
eq .afterInterval "FF.F" "a notch exactly one interval later fires again, one inside the interval does not"
eq .freeSpin "F$(printf '.%.0s' $(seq 49))F$(printf '.%.0s' $(seq 49))" "a free-spinning wheel (100 events, 8 ms apart) fires once per interval, not once per event"
eq '.smoothSum' "...F" "smooth deltas add up to the threshold"
eq '.smoothBurst|[scan("F")]|length' 1 "forty small smooth events inside one interval fire once"
eq .slowSmooth ".." "a pause longer than the idle limit starts counting again"
eq .directionChange "..F" "a change of direction starts counting again"
eq .highThreshold "..F" "a threshold of 3 notches fires on the third"
eq .duplicate ".." "a discrete and a smooth event of one notch (same time and direction) count once"
eq .duplicateReason "accumulating,duplicate" "the second event of a pair is reported as duplicate"
eq .notDuplicate ".F." "two discrete events at one time are two notches (threshold 2 fires on the second), the smooth one after it is rate limited"
eq .reasons "accumulating,fired,rate-limited,fired" "reasons: accumulating, fired, rate-limited"
eq .clockBack "FF" "an event time that went backwards is not rate limited"
eq .reset "false,0" "wheelReset clears the partial sum"
eq .resetKeepsLimit rate-limited "wheelReset keeps the rate limit"
eq '.emulated|map(tostring)|join(" ")' "true false true false false false false false" "emulated scroll events are told apart by the flag bit; a missing flag API or bad flags filter nothing"
eq '.meta|join("|")' "dir=smooth source=1 flags=0x2|dir=up source=? flags=?|dir=? source=0 flags=0x2a" "calibration fields: direction, source, flags"
eq .metaNote "scroll=discrete amount=1.00 acc=0.00 dir=down source=1 flags=0x0" "wheel debug note carries the calibration fields"
grep -q "POINTER_EMULATED" "$ext/extension.js" && grep -q "get_scroll_source" "$ext/extension.js" && pass "extension.js skips emulated scroll events and logs the scroll source" || fail "emulated filter or source logging missing"
eq '.wlog[0]' "desktop-mouse-nav: button=wheel-up state=0x4 mods=ctrl context=desktop match=yes rule=desktop[1] action=next-workspace result=held reason=accumulating scroll=smooth amount=0.50 acc=0.50" "wheel debug line"
eq '.wlog[1]' "desktop-mouse-nav: button=wheel-down state=0x0 mods=none context=desktop match=no rule=none action=none result=ignored reason=no-rule-uses-button" "wheel debug line without a rule"
eq '.wlog[2]' 8 "other inputs keep their number in the log"

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
eq '.log[1]' "desktop-mouse-nav: button=8 state=0x44 mods=ctrl context=app-grid match=yes rule=app-grid[1] action=prev-workspace result=at-end" "debug line: button, raw state in hex, modifiers, context, match, rule, action, result"
eq '.log[2]' "desktop-mouse-nav: button=9 state=0x0 mods=none context=shell match=no rule=none action=none result=propagated reason=no-matching-rule" "debug line without a rule"
eq '.log[3]' "desktop-mouse-nav: button=9 state=0x8000000 mods=other context=shell match=no rule=none action=none result=ignored reason=other-modifier-bits" "debug line with unknown modifier bits"
eq '.log[4]' "desktop-mouse-nav: button=10 state=0x40 mods=super context=desktop match=no rule=none action=none result=ignored reason=no-rule-uses-button" "debug line for a press no rule uses"
eq '.log[5]' "desktop-mouse-nav: button=8 state=0x4000000 mods=super context=desktop match=yes rule=desktop[0] action=next-workspace result=ran" "debug line for a Super press that ran"

# the only console call is console.log (console.debug is dropped by GJS by default), directly under if (this._debug)
[ "$(grep -c 'console\.' "$ext/extension.js")" = 1 ] && grep -q 'console\.log(' "$ext/extension.js" && grep -B1 'console\.log' "$ext/extension.js" | grep -q 'if (this\._debug) {' && pass "extension.js logs once with console.log, directly behind if (this._debug)" || fail "logging is not a single console.log behind the flag"
grep -rq 'console\.debug' "$ext"/*.js && fail "console.debug is dropped by GJS by default, use console.log behind the flag" || pass "no console.debug"
grep -q "get_boolean('debug-log')" "$ext/extension.js" && grep -q "get_boolean('wrap-workspaces')" "$ext/extension.js" && pass "extension.js caches debug-log and wrap-workspaces" || fail "flags not cached"
grep -q "parseRules" "$ext/extension.js" && grep -q "rulesKey" "$ext/extension.js" && pass "extension.js caches parsed rules per context" || fail "rules not cached"
grep -q "settings.get_\|_settings.get_" <(sed -n '/^    _onCapturedEvent(event)/,$p' "$ext/extension.js") && fail "a press reads GSettings" || pass "no GSettings read in the press path"
grep -qE "anywhere|desktop-back|shell-forward" "$ext/extension.js" "$ext/prefs.js" "$ext/actions.js" "$xml" && fail "old key or context names still in the sources" || pass "no old key or context names left in the sources"
grep -q "button === 1 || button === 3" "$ext/extension.js" && pass "extension.js never touches buttons 1 and 3" || fail "buttons 1 and 3 not excluded in extension.js"
grep -q "SUPER_MASK" "$ext/extension.js" && grep -q "MOD4_MASK" "$ext/extension.js" && grep -q "MOD1_MASK" "$ext/extension.js" && pass "extension.js reads Shift, Ctrl, Alt (MOD1) and Super (SUPER_MASK or MOD4_MASK) from the event state" || fail "modifier masks missing"
grep -q "Clutter.EventType.SCROLL" "$ext/extension.js" && grep -q "get_scroll_direction" "$ext/extension.js" && grep -q "wheelStep" "$ext/extension.js" && pass "extension.js handles scroll events through the accumulator" || fail "wheel handling missing in extension.js"
grep -q "get_double('wheel-threshold')" "$ext/extension.js" && grep -q "get_double('wheel-min-interval')" "$ext/extension.js" && pass "extension.js caches the wheel settings" || fail "wheel settings not cached"
grep -q "EventControllerScroll" "$ext/prefs.js" && grep -q "Require a modifier" "$ext/prefs.js" && grep -q "WHEEL_SETTINGS" "$ext/prefs.js" && pass "prefs.js detects the wheel, has the modifier switch and the wheel settings" || fail "wheel editor parts missing in prefs.js"

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
