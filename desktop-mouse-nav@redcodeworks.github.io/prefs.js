// SPDX-License-Identifier: GPL-2.0-or-later
//
// Preferences window: one group per context with its list of rules (button, modifiers,
// action). A plus row at the end of each list opens a dialog that detects the mouse
// button by a real click. This file runs in its own process: only Adw/Gio/Gtk/GLib.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {
    ACTIONS, ADVANCED_SWITCHES, CONTEXTS, CONTEXT_SWITCHES, GTK_MASKS, MODIFIER_COMBOS,
    WORKSPACE_SWITCHES, buttonName, findDuplicate, makeRule, modifiersFromState,
    parseRules, rulesKey, serializeRules, unbindableReason,
} from './actions.js';

const CONTEXT_TEXT = {
    desktop: {
        title: 'On the empty desktop',
        description: 'Used when the pointer is over the desktop background. If no rule here matches, the rules for the top bar and shell surfaces are tried.',
    },
    shell: {
        title: 'Top bar and shell surfaces',
        description: 'Used when the pointer is over Shell surfaces such as the top bar. GNOME never passes mouse buttons pressed over application windows to extensions, so nothing can be set for windows.',
    },
    overview: {
        title: 'Overview',
        description: 'Used while the overview is open, when enabled here.',
    },
    'app-grid': {
        title: 'App grid',
        description: 'Used while the app grid is showing, when enabled here. Previous and next workspace turn the pages of the grid instead.',
    },
};

const ACTION_IDS = ACTIONS.map(([id]) => id);
const ACTION_LABELS = ACTIONS.map(([, label]) => label);
const MODIFIER_IDS = MODIFIER_COMBOS.map(([mods]) => mods);
const MODIFIER_LABELS = MODIFIER_COMBOS.map(([, label]) => label);

function stringList(labels) {
    return Gtk.StringList.new(labels);
}

// Reads one context's rules from the settings.
function readRules(settings, context) {
    return parseRules(settings.get_value(rulesKey(context)).recursiveUnpack());
}

// Writes one context's rules; the caller holds the echo guard.
function writeRules(settings, context, rules) {
    settings.set_value(rulesKey(context), new GLib.Variant('a(uss)', serializeRules(rules)));
}

// The "Press a mouse button" dialog. `onAdd(button, mods, action)` is called on Add.
// Adw.Dialog (libadwaita 1.5) presented from the window; a modal Adw.Window as fallback.
function showRuleDialog(window, existingRules, onAdd) {
    const box = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, spacing: 12,
        margin_top: 24, margin_bottom: 24, margin_start: 24, margin_end: 24,
    });
    const prompt = new Gtk.Label({
        label: 'Click a mouse button here.',
        css_classes: ['title-3'], wrap: true, justify: Gtk.Justification.CENTER,
    });
    const hint = new Gtk.Label({
        label: 'Hold modifier keys while you click to pre-fill the modifier.',
        css_classes: ['dim-label'], wrap: true, justify: Gtk.Justification.CENTER,
    });
    const status = new Gtk.Label({label: '', wrap: true, css_classes: ['error'], visible: false});
    box.append(prompt);
    box.append(hint);
    box.append(status);

    const group = new Adw.PreferencesGroup({visible: false});
    const buttonRow = new Adw.ActionRow({title: 'Button'});
    const modifierRow = new Adw.ComboRow({title: 'Modifier', model: stringList(MODIFIER_LABELS)});
    const actionRow = new Adw.ComboRow({title: 'Action', model: stringList(ACTION_LABELS)});
    group.add(buttonRow);
    group.add(modifierRow);
    group.add(actionRow);
    box.append(group);

    const buttons = new Gtk.Box({orientation: Gtk.Orientation.HORIZONTAL, spacing: 12, halign: Gtk.Align.END});
    const cancel = new Gtk.Button({label: 'Cancel'});
    const add = new Gtk.Button({label: 'Add', css_classes: ['suggested-action'], sensitive: false});
    buttons.append(cancel);
    buttons.append(add);
    box.append(buttons);

    let detected = null;
    const showStatus = text => {
        status.label = text ?? '';
        status.visible = !!text;
    };
    // Add is enabled only for a bindable, not yet bound (button, modifier).
    const validate = () => {
        if (detected === null)
            return;
        const mods = MODIFIER_IDS[modifierRow.selected] ?? '';
        let problem = unbindableReason(detected, mods);
        if (!problem && findDuplicate(existingRules, detected, mods) >= 0)
            problem = 'Already bound in this list.';
        showStatus(problem);
        add.sensitive = !problem;
    };

    const gesture = new Gtk.GestureClick({button: 0});
    gesture.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
    gesture.connect('pressed', () => {
        if (detected !== null)
            return;
        const button = gesture.get_current_button();
        const state = gesture.get_current_event_state() & Gtk.accelerator_get_default_mod_mask();
        if (button === 1 || button === 3) {
            // Primary and secondary are refused; this click may be on Cancel, so it is not claimed.
            showStatus(unbindableReason(button, ''));
            return;
        }
        detected = button;
        buttonRow.subtitle = buttonName(button) + (button > 9 || button === 2 ? '' : ` (button ${button})`);
        modifierRow.selected = Math.max(0, MODIFIER_IDS.indexOf(modifiersFromState(state, GTK_MASKS, false)));
        prompt.label = 'Choose the modifier and the action.';
        hint.visible = false;
        group.visible = true;
        validate();
    });
    box.add_controller(gesture);
    modifierRow.connect('notify::selected', validate);

    let dialog = null;
    try {
        dialog = new Adw.Dialog({title: 'Press a mouse button', child: box, content_width: 420});
        dialog.present(window);
    } catch (e) {
        // Fallback: a modal window on top of the preferences window.
        dialog = new Adw.Window({
            title: 'Press a mouse button', modal: true, transient_for: window,
            default_width: 420, content: box,
        });
        dialog.present();
    }

    cancel.connect('clicked', () => dialog.close());
    add.connect('clicked', () => {
        if (detected === null)
            return;
        const mods = MODIFIER_IDS[modifierRow.selected] ?? '';
        if (unbindableReason(detected, mods) || findDuplicate(existingRules, detected, mods) >= 0)
            return;
        onAdd(detected, mods, ACTION_IDS[actionRow.selected] ?? 'none');
        dialog.close();
    });
}

export default class DesktopMouseNavPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage({
            title: 'Mouse buttons',
            icon_name: 'input-mouse-symbolic',
        });

        const toast = text => {
            if (typeof window.add_toast === 'function')
                window.add_toast(new Adw.Toast({title: text}));
        };

        for (const context of CONTEXTS)
            page.add(this._buildContextGroup(window, settings, context, toast));

        const addSwitches = (title, switches) => {
            const group = new Adw.PreferencesGroup({title});
            for (const [key, rowTitle, subtitle] of switches) {
                const row = new Adw.SwitchRow({title: rowTitle, subtitle});
                settings.bind(key, row, 'active', Gio.SettingsBindFlags.DEFAULT);
                group.add(row);
            }
            page.add(group);
        };
        addSwitches('Workspaces', WORKSPACE_SWITCHES);
        addSwitches('Advanced', ADVANCED_SWITCHES);

        // Keep the settings object alive as long as the window (gjs.guide pattern).
        window._settings = settings;
        window.add(page);
    }

    _buildContextGroup(window, settings, context, toast) {
        const group = new Adw.PreferencesGroup(CONTEXT_TEXT[context]);
        const key = rulesKey(context);

        const switchSpec = CONTEXT_SWITCHES[context];
        if (switchSpec) {
            const [switchKey, title, subtitle] = switchSpec;
            const row = new Adw.SwitchRow({title, subtitle});
            settings.bind(switchKey, row, 'active', Gio.SettingsBindFlags.DEFAULT);
            group.add(row);
        }

        const addRow = new Adw.ButtonRow({title: 'Add rule', start_icon_name: 'list-add-symbolic'});
        let rows = [];
        // No binding mapping function (its GJS callback conventions crashed the prefs
        // process); plain signals, guarded against echo loops.
        let updating = false;

        const save = rules => {
            updating = true;
            try {
                writeRules(settings, context, rules);
            } finally {
                updating = false;
            }
        };

        const rebuild = () => {
            for (const row of rows)
                group.remove(row);
            group.remove(addRow);
            rows = [];
            const rules = readRules(settings, context);
            if (rules.length === 0) {
                const empty = new Adw.ActionRow({
                    title: 'No rules yet',
                    subtitle: 'Use "Add rule" to bind a mouse button.',
                    sensitive: false,
                });
                rows.push(empty);
                group.add(empty);
            }
            rules.forEach((rule, index) => {
                const row = this._buildRuleRow(rule, {
                    change: (field, value) => {
                        const current = readRules(settings, context);
                        if (!current[index])
                            return false;
                        const next = {...current[index], [field]: value};
                        if (field === 'mods') {
                            const problem = unbindableReason(next.input.button, next.mods);
                            if (problem) {
                                toast(problem);
                                return false;
                            }
                            if (findDuplicate(current, next.input.button, next.mods, index) >= 0) {
                                toast('Already bound in this list.');
                                return false;
                            }
                        }
                        current[index] = next;
                        save(current);
                        return true;
                    },
                    remove: () => {
                        const current = readRules(settings, context);
                        current.splice(index, 1);
                        save(current);
                        rebuild();
                    },
                });
                rows.push(row);
                group.add(row);
            });
            group.add(addRow);
        };

        addRow.connect('activated', () => {
            showRuleDialog(window, readRules(settings, context), (button, mods, action) => {
                const current = readRules(settings, context);
                current.push(makeRule(button, mods, action));
                save(current);
                rebuild();
            });
        });

        settings.connect(`changed::${key}`, () => {
            if (updating)
                return;
            rebuild();
        });
        rebuild();
        return group;
    }

    // One rule: button name as the title; modifier and action dropdowns and a delete
    // button as suffixes. `edit.change(field, value)` returns false to refuse the change.
    _buildRuleRow(rule, edit) {
        const row = new Adw.ActionRow({title: buttonName(rule.input.button)});
        let mods = rule.mods;

        const modifierDrop = new Gtk.DropDown({
            model: stringList(MODIFIER_LABELS), valign: Gtk.Align.CENTER,
            selected: Math.max(0, MODIFIER_IDS.indexOf(mods)),
        });
        const actionDrop = new Gtk.DropDown({
            model: stringList(ACTION_LABELS), valign: Gtk.Align.CENTER,
            selected: Math.max(0, ACTION_IDS.indexOf(rule.action)),
        });
        let reverting = false;
        modifierDrop.connect('notify::selected', () => {
            if (reverting)
                return;
            const wanted = MODIFIER_IDS[modifierDrop.selected] ?? '';
            if (edit.change('mods', wanted)) {
                mods = wanted;
            } else {
                reverting = true;
                modifierDrop.selected = Math.max(0, MODIFIER_IDS.indexOf(mods));
                reverting = false;
            }
        });
        actionDrop.connect('notify::selected', () => {
            if (reverting)
                return;
            edit.change('action', ACTION_IDS[actionDrop.selected] ?? 'none');
        });

        const remove = new Gtk.Button({
            icon_name: 'user-trash-symbolic', valign: Gtk.Align.CENTER,
            css_classes: ['flat'], tooltip_text: 'Delete this rule',
        });
        remove.connect('clicked', () => edit.remove());

        row.add_suffix(modifierDrop);
        row.add_suffix(actionDrop);
        row.add_suffix(remove);
        return row;
    }
}
