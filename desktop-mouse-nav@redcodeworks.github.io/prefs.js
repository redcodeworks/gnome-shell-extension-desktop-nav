// SPDX-License-Identifier: GPL-2.0-or-later
//
// Preferences window: one group per context, one combo row per mouse button.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {ACTIONS, BUTTONS, CONTEXTS, OVERVIEW_SWITCHES, settingsKey} from './actions.js';

const CONTEXT_TEXT = {
    desktop: {
        title: 'On the empty desktop',
        description: 'Used when the pointer is over the desktop background. "Do nothing" here falls back to the anywhere setting.',
    },
    anywhere: {
        title: 'Anywhere else',
        description: 'Used over windows, panels and the overview. Leave on "Do nothing" to keep the buttons for applications.',
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

        const overview = new Adw.PreferencesGroup({
            title: 'Overview',
            description: 'By default the buttons do nothing while the overview or the app grid is open.',
        });
        for (const [key, title, subtitle] of OVERVIEW_SWITCHES) {
            const row = new Adw.SwitchRow({title, subtitle});
            settings.bind(key, row, 'active', Gio.SettingsBindFlags.DEFAULT);
            overview.add(row);
        }
        page.add(overview);

        // Keep the settings object alive as long as the window (gjs.guide pattern).
        window._settings = settings;
        window.add(page);
    }
}
