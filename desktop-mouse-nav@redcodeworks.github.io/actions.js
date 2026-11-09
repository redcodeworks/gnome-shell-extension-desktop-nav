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

// A rule is {input, mods, action}. Today the input is always {kind: 'button', button: N}
// (X11-style button number); other input kinds can be added later without changing the
// rest. In settings a rule is the tuple (button, modifiers, action id), type a(uss).
// `mods` is a normalized modifier string: sorted parts joined by '+', '' for none.

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
// (the Clutter values in extension.js, GTK_MASKS in prefs.js). In `strict` mode any set
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
    return {2: 'Middle', 8: 'Back', 9: 'Forward'}[button] ?? `Button ${button}`;
}

// null when (button, mods) can be bound, else a short message. The primary (1) and
// secondary (3) buttons are refused; middle (2) needs at least one modifier.
export function unbindableReason(button, mods) {
    if (!Number.isInteger(button) || button < 1)
        return 'Not a valid mouse button.';
    if (button === 1 || button === 3)
        return 'The primary and secondary buttons cannot be used.';
    const normalized = normalizeModifiers(mods);
    if (normalized === null)
        return 'Unknown modifier.';
    if (button === 2 && normalized === '')
        return 'The middle button needs at least one modifier.';
    return null;
}

export function makeRule(button, mods, action) {
    return {input: {kind: 'button', button}, mods, action};
}

// Rules from the stored tuples [button, mods, action]. Invalid ones (bad shape, buttons
// that cannot be bound, unknown modifiers or action ids) are dropped.
export function parseRules(tuples) {
    const rules = [];
    if (!Array.isArray(tuples))
        return rules;
    for (const tuple of tuples) {
        if (!Array.isArray(tuple) || tuple.length !== 3)
            continue;
        const [button, mods, action] = tuple;
        const normalized = normalizeModifiers(mods);
        if (normalized === null || unbindableReason(button, normalized) !== null ||
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
    return rules.findIndex(rule => rule.input.kind === 'button' &&
        rule.input.button === button && rule.mods === mods);
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

// Switches at the top of the Overview and App grid groups: [key, title, subtitle].
export const CONTEXT_SWITCHES = {
    overview: ['work-in-overview', 'Enable for the Overview',
        'Run the rules below while the overview is open.'],
    'app-grid': ['work-in-app-grid', 'Enable for the app grid',
        'Run the rules below while the app grid is showing. Previous and next workspace turn the pages of the grid instead.'],
};

// Boolean settings of the "Advanced" group (default false).
export const ADVANCED_SWITCHES = [
    ['debug-log', 'Log button presses',
        'For troubleshooting; off by default. Writes one line per handled mouse button press to the journal.'],
];

// Boolean setting of the "Workspaces" group (default false).
export const WORKSPACE_SWITCHES = [
    ['wrap-workspaces', 'Wrap around workspaces',
        'Back on the first workspace goes to the last one, and Forward on the last workspace goes to the first one.'],
];

export const BOOLEAN_KEYS = [...Object.values(CONTEXT_SWITCHES), ...WORKSPACE_SWITCHES, ...ADVANCED_SWITCHES].map(([key]) => key);

// Gate for the overview. `state` = {overviewVisible, appGridShowing}; `flags` =
// {inOverview, inAppGrid}. App grid showing -> only with the app grid flag; else
// overview visible -> only with the overview flag; neither showing -> always.
export function overviewAllowed(state, flags) {
    if (state.overviewVisible && state.appGridShowing)
        return !!flags.inAppGrid;
    if (state.overviewVisible)
        return !!flags.inOverview;
    return true;
}

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

// The single debug line for a press, or null when logging is off. `found` is the result
// of findRule (or null); result: 'ran', 'propagated' or 'at-end'.
export function debugLine(enabled, button, mods, context, found, result) {
    if (!enabled)
        return null;
    const rule = found ? `${found.context}[${found.index}]` : 'none';
    const action = found ? found.rule.action : 'none';
    return `desktop-mouse-nav: button=${button} mods=${mods === null ? 'other' : mods || 'none'} context=${context} rule=${rule} action=${action} result=${result}`;
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
