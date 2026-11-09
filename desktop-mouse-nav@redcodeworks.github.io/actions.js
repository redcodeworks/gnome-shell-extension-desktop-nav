// SPDX-License-Identifier: GPL-2.0-or-later
//
// One source of truth shared by extension.js and prefs.js: the schema id, the
// settings keys and the action ids (the schema's choices must match; tests check it).
// No imports on purpose, so the tests can run this file with plain node.

export const SCHEMA_ID = 'org.gnome.shell.extensions.desktop-mouse-nav';

// Mouse buttons, named as in the settings keys.
export const BUTTONS = ['back', 'forward'];

// Where the pointer is: on the empty desktop, or anywhere else.
export const CONTEXTS = ['desktop', 'anywhere'];

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
// desktop the desktop action wins unless it is 'none'; then the anywhere action
// applies. Unknown ids count as 'none'.
export function pickAction(read, onDesktop, button) {
    let id = 'none';
    if (onDesktop)
        id = read(settingsKey('desktop', button));
    if (!ACTION_IDS.includes(id) || id === 'none')
        id = read(settingsKey('anywhere', button));
    return ACTION_IDS.includes(id) ? id : 'none';
}

// Boolean settings: [key, title, subtitle] for the "Overview" group (both default false).
export const OVERVIEW_SWITCHES = [
    ['work-in-overview', 'Work in the Overview',
        'Back and Forward also run while the overview is open.'],
    ['work-in-app-grid', 'Work in the app grid',
        'Back and Forward also run while the app grid is showing.'],
];

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
