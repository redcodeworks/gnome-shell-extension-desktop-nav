// SPDX-License-Identifier: GPL-2.0-or-later
//
// One source of truth shared by extension.js and prefs.js: the schema id, the
// settings keys, the rule model and the action ids (the schema's choices must match; tests check it).
// No imports on purpose, so the tests can run this file with plain node.

export const SCHEMA_ID = 'org.gnome.shell.extensions.desktop-mouse-nav';

// Contexts, each with its own rule list (settings key `rules-<context>`):
// 'desktop' (empty desktop), 'shell' (top bar and other Shell surfaces), 'overview'
// and 'app-grid'. GNOME never passes button presses over application windows to
// extensions, so there is no context for them.
export const CONTEXTS = ['desktop', 'shell', 'overview', 'app-grid'];

export function rulesKey(context) {
    return `rules-${context}`;
}

// [id, label shown in the preferences window]
export const ACTIONS = [
    ['none', 'Do nothing'],
    ['prev-workspace', 'Previous workspace'],
    ['next-workspace', 'Next workspace'],
    ['toggle-overview', 'Toggle the overview'],
    ['toggle-app-grid', 'Toggle the app grid'],
    ['move-window-prev-workspace', 'Move the focused window to the previous workspace'],
    ['move-window-next-workspace', 'Move the focused window to the next workspace'],
];

export const ACTION_IDS = ACTIONS.map(([id]) => id);

// A rule is {input, mods, action}. The input is {kind: 'button', button: N} (X11-style
// button number) or, for the mouse wheel, {kind: 'wheel', direction, button: N} with the
// X11 scroll numbers 4 (up) and 5 (down). Real mouse buttons never use 4 to 7 (mutter
// numbers extra buttons from 8; UNVERIFIED, from memory), so the stored tuple needs no new
// field and settings written by 0.3.0 stay valid. In settings a rule is the tuple
// (button, modifiers, action id), type a(uss). `mods` is a normalized modifier string:
// sorted parts joined by '+', '' for none.
export const WHEEL_UP = 4;
export const WHEEL_DOWN = 5;

export function isWheelButton(button) {
    return button === WHEEL_UP || button === WHEEL_DOWN;
}

// 'up' or 'down' for the wheel numbers, else null.
export function wheelDirection(button) {
    return button === WHEEL_UP ? 'up' : button === WHEEL_DOWN ? 'down' : null;
}

export const MODIFIER_PARTS = ['alt', 'ctrl', 'shift', 'super'];

function modifierPartLabel(part) {
    return {alt: 'Alt', ctrl: 'Ctrl', shift: 'Shift', super: 'Super'}[part];
}

// Normalize a modifier string ('Shift+ctrl' -> 'ctrl+shift'); null when a part is unknown.
export function normalizeModifiers(text) {
    if (typeof text !== 'string')
        return null;
    const parts = new Set();
    for (const raw of text.split('+')) {
        const part = raw.trim().toLowerCase();
        if (part === '')
            continue;
        if (!MODIFIER_PARTS.includes(part))
            return null;
        parts.add(part);
    }
    return MODIFIER_PARTS.filter(part => parts.has(part)).join('+');
}

// All 16 combinations, 'none' first, then fewer modifiers before more:
// [modifier string, label].
export const MODIFIER_COMBOS = Array.from({length: 16}, (_, bits) => {
    const parts = MODIFIER_PARTS.filter((_part, i) => bits & (1 << i));
    return {bits, count: parts.length, mods: parts.join('+'),
        label: parts.length ? parts.map(modifierPartLabel).join('+') : 'None'};
}).sort((x, y) => x.count - y.count || x.bits - y.bits).map(c => [c.mods, c.label]);

export function modifierLabel(mods) {
    const normalized = normalizeModifiers(mods);
    if (normalized === null)
        return String(mods);
    return normalized === '' ? 'None' : normalized.split('+').map(modifierPartLabel).join('+');
}

// Modifier bits of a GDK/GTK event state in the preferences process (no Gdk import
// there; these are the GDK 4 ModifierType values: SHIFT 1, CONTROL 4, ALT 8, SUPER 1<<26).
export const GTK_MASKS = {shift: 1, ctrl: 4, alt: 8, super: 1 << 26, ignore: 0};

// Modifier string from a numeric event state. `masks` = {shift, ctrl, alt, super, ignore}
// (the Clutter values in extension.js, GTK_MASKS in prefs.js). Each entry may be several
// bits OR-ed together: any of them counts. extension.js passes SUPER_MASK | MOD4_MASK as
// `super`, because Super may arrive as either bit (UNVERIFIED which one Shell 51 uses). In `strict` mode any set
// bit that is neither one of the four modifiers nor in `ignore` (Hyper, Meta, other
// modifier bits) makes the result null: such a press is not exactly any rule.
export function modifiersFromState(state, masks, strict) {
    if (!Number.isInteger(state))
        return null;
    const known = masks.shift | masks.ctrl | masks.alt | masks.super;
    if (strict && (state & ~(known | masks.ignore)) !== 0)
        return null;
    const parts = [];
    if (state & masks.alt)
        parts.push('alt');
    if (state & masks.ctrl)
        parts.push('ctrl');
    if (state & masks.shift)
        parts.push('shift');
    if (state & masks.super)
        parts.push('super');
    return parts.join('+');
}

export function buttonName(button) {
    return {2: 'Middle', 4: 'Wheel up', 5: 'Wheel down', 8: 'Back', 9: 'Forward'}[button] ??
        `Button ${button}`;
}

// null when (button, mods) can be bound, else a short message. The primary (1) and
// secondary (3) buttons are refused; middle (2) needs at least one modifier; so does the
// wheel (4, 5) unless `allowBareWheel` (a rule the user explicitly set to need none).
export function unbindableReason(button, mods, allowBareWheel = false) {
    if (!Number.isInteger(button) || button < 1)
        return 'Not a valid mouse button.';
    if (button === 1 || button === 3)
        return 'The primary and secondary buttons cannot be used.';
    const normalized = normalizeModifiers(mods);
    if (normalized === null)
        return 'Unknown modifier.';
    if (button === 2 && normalized === '')
        return 'The middle button needs at least one modifier.';
    if (isWheelButton(button) && normalized === '' && !allowBareWheel)
        return 'Wheel rules need a modifier unless "Require a modifier" is turned off.';
    return null;
}

export function makeRule(button, mods, action) {
    const direction = wheelDirection(button);
    return {
        input: direction ? {kind: 'wheel', direction, button} : {kind: 'button', button},
        mods, action,
    };
}

// Rules from the stored tuples [button, mods, action]. Invalid ones (bad shape, buttons
// that cannot be bound, unknown modifiers or action ids) are dropped. A stored wheel rule
// without a modifier is kept: it is the user's explicit choice.
export function parseRules(tuples) {
    const rules = [];
    if (!Array.isArray(tuples))
        return rules;
    for (const tuple of tuples) {
        if (!Array.isArray(tuple) || tuple.length !== 3)
            continue;
        const [button, mods, action] = tuple;
        const normalized = normalizeModifiers(mods);
        if (normalized === null || unbindableReason(button, normalized, true) !== null ||
            !ACTION_IDS.includes(action))
            continue;
        rules.push(makeRule(button, normalized, action));
    }
    return rules;
}

// The tuples to store: [[button, mods, action], ...] for GLib.Variant('a(uss)', ...).
export function serializeRules(rules) {
    return rules.map(rule => [rule.input.button, rule.mods, rule.action]);
}

// Index of the first rule on the same input (button, mods), skipping `except`; -1 when none.
export function findDuplicate(rules, button, mods, except = -1) {
    const normalized = normalizeModifiers(mods);
    return rules.findIndex((rule, i) => i !== except && rule.input.button === button &&
        rule.mods === normalized);
}

// Index of the first rule matching the pressed button and the exact modifiers; -1 when
// none (or mods is null: an unknown modifier bit was held).
export function matchRule(rules, button, mods) {
    if (mods === null)
        return -1;
    return rules.findIndex(rule => rule.input.button === button && rule.mods === mods);
}

// True when any rule in any context uses this button (cheap exit for other buttons).
export function anyRuleUsesButton(rulesByContext, button) {
    return Object.values(rulesByContext).some(rules => rules.some(rule => rule.input.button === button));
}

// Contexts whose rules are tried for a pointer context, in order: on the empty desktop
// the desktop rules then the shell rules; everywhere else only that context's own.
export function contextOrder(context) {
    return context === 'desktop' ? ['desktop', 'shell'] : [context];
}

// First matching rule for a press: {context, index, rule} (context = the list it was
// found in) or null.
export function findRule(rulesByContext, pointer, button, mods) {
    for (const context of contextOrder(pointer)) {
        const rules = rulesByContext[context] ?? [];
        const index = matchRule(rules, button, mods);
        if (index >= 0)
            return {context, index, rule: rules[index]};
    }
    return null;
}

// Boolean settings of the "Advanced" group (default false).
export const ADVANCED_SWITCHES = [
    ['debug-log', 'Log button presses',
        'For troubleshooting; off by default. Writes one line per mouse button press that reaches the extension (including ignored ones, with the reason) to the journal.'],
];

// Boolean setting of the "Workspaces" group (default false).
export const WORKSPACE_SWITCHES = [
    ['wrap-workspaces', 'Wrap around workspaces',
        'Back on the first workspace goes to the last one, and Forward on the last workspace goes to the first one.'],
];

// Number settings of the "Mouse wheel" group (type d): [key, title, subtitle, min, max,
// step, digits]. Defaults are in the schema (tests keep both in step with WHEEL_DEFAULTS).
export const WHEEL_DEFAULTS = {threshold: 1, minInterval: 400};
// A wheel burst that pauses longer than this starts counting from zero again.
export const WHEEL_IDLE_MS = 600;
export const WHEEL_SETTINGS = [
    ['wheel-threshold', 'Scroll needed per action',
        'How much scrolling one action needs, in wheel notches (1 = one click). Raise it to make a high-resolution or free-spin wheel less sensitive.',
        0.1, 20, 0.1, 1],
    ['wheel-min-interval', 'Pause between actions (ms)',
        'After an action, wheel events are ignored for this long, so one burst of scrolling does not switch several workspaces.',
        50, 3000, 50, 0],
];
export const WHEEL_KEYS = WHEEL_SETTINGS.map(([key]) => key);

// The numbers from settings, forced into their limits (bad values fall back to defaults).
export function wheelConfig(threshold, minInterval) {
    const clamp = (value, min, max, fallback) =>
        Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;
    return {
        threshold: clamp(threshold, 0.1, 20, WHEEL_DEFAULTS.threshold),
        minInterval: clamp(minInterval, 50, 3000, WHEEL_DEFAULTS.minInterval),
    };
}

// A scroll event reduced to {dir: 'up'|'down', amount, kind: 'discrete'|'smooth'}, or null
// when it is not a vertical scroll (horizontal, tilt wheel, empty smooth delta).
// `direction` is 'up', 'down', 'left', 'right' or 'smooth' (the Clutter.ScrollDirection
// names); `dx`, `dy` are the smooth deltas (positive dy = down, UNVERIFIED sign).
export function scrollInput(direction, dx, dy) {
    if (direction === 'up' || direction === 'down')
        return {dir: direction, amount: 1, kind: 'discrete'};
    if (direction !== 'smooth' || !Number.isFinite(dx) || !Number.isFinite(dy))
        return null;
    if (dy === 0 || Math.abs(dx) > Math.abs(dy))
        return null;
    return {dir: dy < 0 ? 'up' : 'down', amount: Math.abs(dy), kind: 'smooth'};
}

export function newWheelState() {
    return {acc: 0, dir: null, last: null, lastFire: null, prev: null};
}

// Forget the partial accumulation (end of a smooth-scroll gesture, settings reload);
// the rate limit and the duplicate check stay.
export function wheelReset(state) {
    return {...state, acc: 0, dir: null, last: null};
}

// Accumulation and rate limit, pure. `input` = scrollInput result plus `time` (ms),
// `config` = wheelConfig result. Returns {state, fire, reason} with reason 'fired',
// 'accumulating', 'rate-limited' or 'duplicate'; the caller keeps the returned state.
// - Events of one notch can arrive both as a discrete and as a smooth event with the
//   same direction and time: the second one is dropped ('duplicate').
// - Within `minInterval` ms after an action every event is dropped and the sum is
//   cleared, so one burst (or a free-spinning wheel) gives one action per interval.
// - Otherwise amounts of one direction add up (a change of direction or a pause of
//   WHEEL_IDLE_MS starts again); reaching `threshold` fires and clears the sum.
export function wheelStep(state, input, config) {
    const {dir, amount, kind, time} = input;
    const seen = {time, dir, kind};
    if (state.prev && state.prev.time === time && state.prev.dir === dir &&
        state.prev.kind !== kind)
        return {state, fire: false, reason: 'duplicate'};
    let next = {...state, prev: seen};
    if (next.lastFire !== null && time >= next.lastFire && time - next.lastFire < config.minInterval)
        return {state: {...next, acc: 0, dir: null, last: null}, fire: false, reason: 'rate-limited'};
    if (next.dir !== dir || next.last === null || time - next.last > WHEEL_IDLE_MS || time < next.last)
        next = {...next, acc: 0, dir};
    const acc = next.acc + amount;
    if (acc >= config.threshold)
        return {state: {...next, acc: 0, last: time, lastFire: time}, fire: true, reason: 'fired'};
    return {state: {...next, acc, last: time}, fire: false, reason: 'accumulating'};
}

export const BOOLEAN_KEYS = [...WORKSPACE_SWITCHES, ...ADVANCED_SWITCHES].map(([key]) => key);

// Where the pointer is, for a press the extension sees: 'app-grid' and 'overview'
// while the overview is open, else 'desktop' (empty desktop) or 'shell' (another
// Shell surface, such as the top bar).
export function pointerContext({overviewVisible, appGridShowing, onEmptyDesktop}) {
    if (overviewVisible)
        return appGridShowing ? 'app-grid' : 'overview';
    return onEmptyDesktop ? 'desktop' : 'shell';
}

// What an action does in a context: while the app grid shows, previous/next workspace
// page the grid (step -1/+1); everything else runs as bound.
export function resolveAction(action, context) {
    if (context === 'app-grid') {
        if (action === 'prev-workspace')
            return {type: 'page', step: -1};
        if (action === 'next-workspace')
            return {type: 'page', step: 1};
    }
    return {type: 'action', id: action};
}

// Target page for a paging step, or null (no wrapping): no pages, a single page, a
// bad current page or the first/last page already reached.
export function pageTarget(current, nPages, step) {
    if (!Number.isInteger(current) || !Number.isInteger(nPages) || nPages < 2)
        return null;
    if (current < 0 || current >= nPages)
        return null;
    const target = current + step;
    return target < 0 || target >= nPages ? null : target;
}

// Raw event state as hex for the debug line ('0x40'), 'unknown' when not an integer.
export function hexState(state) {
    return Number.isInteger(state) ? `0x${(state >>> 0).toString(16)}` : 'unknown';
}

// 'wheel-up'/'wheel-down' for the wheel numbers, else the button number.
export function inputLabel(button) {
    const direction = wheelDirection(button);
    return direction ? `wheel-${direction}` : String(button);
}

// Extra debug fields of a wheel event: `scroll=smooth amount=0.50 acc=0.50`.
export function wheelNote(input, state) {
    return `scroll=${input.kind} amount=${input.amount.toFixed(2)} acc=${state.acc.toFixed(2)}`;
}

// The single debug line for a handled press, or null when logging is off. `state` = raw
// event modifier state, `mods` the normalized string (null = unknown bits held), `found`
// the result of findRule (or null), result 'ran', 'propagated', 'at-end' or 'ignored',
// `reason` a short note for presses that did not run (or null), `extra` more fields (wheel).
// result may also be 'held' (a wheel event swallowed without an action).
export function debugLine(enabled, button, state, mods, context, found, result, reason = null, extra = null) {
    if (!enabled)
        return null;
    const rule = found ? `${found.context}[${found.index}]` : 'none';
    const action = found ? found.rule.action : 'none';
    const note = (reason ? ` reason=${reason}` : '') + (extra ? ` ${extra}` : '');
    return `desktop-mouse-nav: button=${inputLabel(button)} state=${hexState(state)} mods=${mods === null ? 'other' : mods || 'none'} context=${context} match=${found ? 'yes' : 'no'} rule=${rule} action=${action} result=${result}${note}`;
}

// Target workspace index for a step (-1/+1) from the active one, or null (do nothing,
// let the press propagate): fewer than two workspaces, a bad index, the ends with wrap
// off, or a target equal to the active workspace. Also used to move a window.
export function workspaceTarget(active, count, step, wrap) {
    if (!Number.isInteger(active) || !Number.isInteger(count) || count < 2)
        return null;
    if (active < 0 || active >= count)
        return null;
    let index = active + step;
    if (wrap)
        index = (index % count + count) % count;
    else if (index < 0 || index >= count)
        return null;
    return index === active ? null : index;
}
