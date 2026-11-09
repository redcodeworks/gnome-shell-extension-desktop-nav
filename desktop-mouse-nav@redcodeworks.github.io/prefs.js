// SPDX-License-Identifier: GPL-2.0-or-later
//
// Preferences window: one group per context, one combo row per mouse button.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {ACTIONS, ADVANCED_SWITCHES, BUTTONS, CONTEXTS, OVERVIEW_SWITCHES, WORKSPACE_SWITCHES, settingsKey} from './actions.js';

const CONTEXT_TEXT = {
    desktop: {
        title: 'On the empty desktop',
        description: 'Used when the pointer is over the desktop background, and in the overview and the app grid (when enabled below). "Do nothing" here falls back to the Shell setting.',
    },
    shell: {
        title: 'Top bar and shell surfaces',
        description: 'Used when the pointer is over Shell surfaces such as the top bar. GNOME never passes mouse buttons pressed over application windows to extensions, so nothing can be set for windows.',
    },
};

const BUTTON_TITLE = {back: 'Back button', forward: 'Forward button'};

export default class DesktopMouseNavPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const ids = ACTIONS.map(([id]) => id);
        const labels = Gtk.StringList.new(ACTIONS.map(([, label]) => label));

        const page = new Adw.PreferencesPage({
            title: 'Mouse buttons',
            icon_name: 'input-mouse-symbolic',
        });

        for (const context of CONTEXTS) {
            const group = new Adw.PreferencesGroup(CONTEXT_TEXT[context]);
            for (const button of BUTTONS) {
                const key = settingsKey(context, button);
                const row = new Adw.ComboRow({title: BUTTON_TITLE[button], model: labels});
                const fromSettings = () => Math.max(0, ids.indexOf(settings.get_string(key)));
                row.selected = fromSettings();
                // No binding mapping function: its GJS callback conventions crashed the prefs
                // process. Plain signals instead, guarded against echo loops.
                let updating = false;
                row.connect('notify::selected', () => {
                    if (updating)
                        return;
                    updating = true;
                    settings.set_string(key, ids[row.selected] ?? 'none');
                    updating = false;
                });
                settings.connect(`changed::${key}`, () => {
                    if (updating)
                        return;
                    updating = true;
                    row.selected = fromSettings();
                    updating = false;
                });
                group.add(row);
            }
            page.add(group);
        }

        const addSwitches = (title, description, switches) => {
            const group = new Adw.PreferencesGroup({title, description});
            for (const [key, rowTitle, subtitle] of switches) {
                const row = new Adw.SwitchRow({title: rowTitle, subtitle});
                settings.bind(key, row, 'active', Gio.SettingsBindFlags.DEFAULT);
                group.add(row);
            }
            page.add(group);
        };
        addSwitches('Overview',
            'By default the buttons do nothing while the overview or the app grid is open. There the desktop setting applies; in the app grid previous and next workspace turn the pages.',
            OVERVIEW_SWITCHES);
        addSwitches('Workspaces', null, WORKSPACE_SWITCHES);
        addSwitches('Advanced', null, ADVANCED_SWITCHES);

        // Keep the settings object alive as long as the window (gjs.guide pattern).
        window._settings = settings;
        window.add(page);
    }
}
