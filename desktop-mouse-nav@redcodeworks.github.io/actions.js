// SPDX-License-Identifier: GPL-2.0-or-later
//
// One source of truth shared by extension.js and prefs.js: the schema id, the
// settings keys and the action ids (the schema's choices must match; tests check it).
// No imports on purpose, so the tests can run this file with plain node.

export const SCHEMA_ID = 'org.gnome.shell.extensions.desktop-mouse-nav';

// Mouse buttons, named as in the settings keys.
export const BUTTONS = ['back', 'forward'];

// Settings contexts: the empty desktop (and, while it is open, the overview and the
// app grid), and the other Shell surfaces such as the top bar. GNOME never passes
// button presses over application windows to extensions, so there is no context for them.
export const CONTEXTS = ['desktop', 'shell'];

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

export function settingsKey(context, button) {
    return `${context}-${button}`;
}

// The action a press runs. `read(key)` returns the stored action id. On the empty
// desktop the desktop action wins unless it is 'none'; then the shell action
// applies. Unknown ids count as 'none'.
export function pickAction(read, onDesktop, button) {
    let id = 'none';
    if (onDesktop)
        id = read(settingsKey('desktop', button));
    if (!ACTION_IDS.includes(id) || id === 'none')
        id = read(settingsKey('shell', button));
    return ACTION_IDS.includes(id) ? id : 'none';
}

// Boolean settings: [key, title, subtitle] for the "Overview" group (both default false).
export const OVERVIEW_SWITCHES = [
    ['work-in-overview', 'Enable for the Overview',
        'Run the Back and Forward actions while the overview is open.'],
    ['work-in-app-grid', 'Enable for the app grid',
        'Run the Back and Forward actions while the app grid is showing. Previous and next workspace turn the pages of the grid instead.'],
];

// Boolean settings of the "Advanced" group (default false).
export const ADVANCED_SWITCHES = [
    ['debug-log', 'Log button presses',
        'For troubleshooting; off by default. Writes one line per Back or Forward press to the journal.'],
];

// Boolean setting of the "Workspaces" group (default false).
export const WORKSPACE_SWITCHES = [
    ['wrap-workspaces', 'Wrap around workspaces',
        'Back on the first workspace goes to the last one, and Forward on the last workspace goes to the first one.'],
];

export const BOOLEAN_KEYS = [...OVERVIEW_SWITCHES, ...WORKSPACE_SWITCHES, ...ADVANCED_SWITCHES].map(([key]) => key);

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

// The overview and the app grid count as the empty desktop: the desktop action runs,
// and the shell action is the fallback when the desktop action is 'none'.
export function treatAsDesktop(context) {
    return context === 'desktop' || context === 'overview' || context === 'app-grid';
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

// The single debug line for a press, or null when logging is off.
// result: 'ran', 'propagated' or 'at-end'.
export function debugLine(enabled, button, context, action, result) {
    if (!enabled)
        return null;
    return `desktop-mouse-nav: button=${button} context=${context} action=${action} result=${result}`;
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
