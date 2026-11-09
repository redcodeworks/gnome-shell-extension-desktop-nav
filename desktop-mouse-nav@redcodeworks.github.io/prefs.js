// SPDX-License-Identifier: GPL-2.0-or-later
//
// Preferences window: one group per context, one combo row per mouse button.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {ACTIONS, BUTTONS, CONTEXTS, settingsKey} from './actions.js';

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
                const row = new Adw.ComboRow({title: BUTTON_TITLE[button], model: labels});
                settings.bind_with_mapping(
                    settingsKey(context, button), row, 'selected', Gio.SettingsBindFlags.DEFAULT,
                    (value) => Math.max(0, ids.indexOf(value)),
                    (index) => ids[index] ?? 'none');
                group.add(row);
            }
            page.add(group);
        }

        window.add(page);
    }
}
