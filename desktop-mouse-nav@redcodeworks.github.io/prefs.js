// SPDX-License-Identifier: GPL-2.0-or-later
//
// Preferences window: one group per context with its list of rules (button, modifiers,
// action). A plus row at the end of each list opens a dialog that detects the mouse
// button by a real click, or the wheel by scrolling. This file runs in its own process: only Adw/Gio/Gtk/GLib.

import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {
    ADVANCED_SWITCHES, CONTEXTS, GTK_MASKS, MODIFIER_COMBOS, WHEEL_DOWN, WHEEL_LEFT, WHEEL_RIGHT,
    WHEEL_SETTINGS, WHEEL_UP, WORKSPACE_SWITCHES, actionAvailability, actionsForContext, buttonName, findDuplicate, isWheelButton,
    makeRule, modifiersFromState, parseRules, rulesKey, serializeRules, unbindableReason,
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
        description: 'Used while the overview is open. With no rules here, nothing happens in the overview.',
    },
    'app-grid': {
        title: 'App grid',
        description: 'Used while the app grid is showing. With no rules here, nothing happens in the app grid. Use the app grid page actions to turn its pages.',
    },
};

// The action ids and labels the editor offers in a context.
function actionChoices(context) {
    const actions = actionsForContext(context);
    return {ids: actions.map(([id]) => id), labels: actions.map(([, label]) => label)};
}

const UNAVAILABLE_NOTE = 'Unavailable in this version';
const NOT_HERE_NOTE = 'Not available in this list';
const MODIFIER_IDS = MODIFIER_COMBOS.map(([mods]) => mods);
const MODIFIER_LABELS = MODIFIER_COMBOS.map(([, label]) => label);

function stringList(labels) {
    return Gtk.StringList.new(labels);
}

// Popup list items that show the whole text (libadwaita's default items are cut off at 20
// characters) with a check mark on the selected one. `widget` is the Adw.ComboRow or
// Gtk.DropDown; any failure leaves the default items in place.
function showFullLabels(widget) {
    try {
        const factory = new Gtk.SignalListItemFactory();
        const handlers = new Map();
        factory.connect('setup', (_factory, listItem) => {
            const box = new Gtk.Box({orientation: Gtk.Orientation.HORIZONTAL, spacing: 12});
            const label = new Gtk.Label({xalign: 0, hexpand: true});
            const check = new Gtk.Image({icon_name: 'object-select-symbolic', opacity: 0});
            box.append(label);
            box.append(check);
            listItem.set_child(box);
        });
        factory.connect('bind', (_factory, listItem) => {
            const box = listItem.get_child();
            const label = box.get_first_child();
            const check = box.get_last_child();
            label.label = listItem.get_item()?.string ?? '';
            const update = () => {
                check.opacity = widget.selected_item === listItem.get_item() ? 1 : 0;
            };
            update();
            handlers.set(listItem, widget.connect('notify::selected-item', update));
        });
        factory.connect('unbind', (_factory, listItem) => {
            const id = handlers.get(listItem);
            if (id !== undefined)
                widget.disconnect(id);
            handlers.delete(listItem);
        });
        widget.list_factory = factory;
    } catch (e) {
        // keep the default items
    }
}

// Reads one context's rules from the settings.
function readRules(settings, context) {
    return parseRules(settings.get_value(rulesKey(context)).recursiveUnpack());
}

// Writes one context's rules; the caller holds the echo guard.
function writeRules(settings, context, rules) {
    settings.set_value(rulesKey(context), new GLib.Variant('a(uss)', serializeRules(rules)));
}

const NO_MODIFIER_NOTE = 'No modifier: plain scrolling triggers this rule.';

// The "Press a mouse button" dialog. `onAdd(button, mods, action)` is called on Add.
// Adw.Dialog (libadwaita 1.5) presented from the window; a modal Adw.Window as fallback.
function showRuleDialog(window, context, existingRules, onAdd) {
    const choices = actionChoices(context);
    const box = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, spacing: 12,
        margin_top: 24, margin_bottom: 24, margin_start: 24, margin_end: 24,
    });
    const prompt = new Gtk.Label({
        label: 'Click a mouse button here, or turn the mouse wheel.',
        css_classes: ['title-3'], wrap: true, justify: Gtk.Justification.CENTER,
    });
    const hint = new Gtk.Label({
        label: 'Hold modifier keys while you click or scroll to pre-fill the modifier.',
        css_classes: ['dim-label'], wrap: true, justify: Gtk.Justification.CENTER,
    });
    const status = new Gtk.Label({label: '', wrap: true, css_classes: ['error'], visible: false});
    box.append(prompt);
    box.append(hint);
    box.append(status);

    const group = new Adw.PreferencesGroup({visible: false});
    const buttonRow = new Adw.ActionRow({title: 'Button'});
    const modifierRow = new Adw.ComboRow({title: 'Modifier', model: stringList(MODIFIER_LABELS)});
    const actionRow = new Adw.ComboRow({title: 'Action', model: stringList(choices.labels)});
    showFullLabels(modifierRow);
    showFullLabels(actionRow);
    // Wheel rules need a modifier by default so normal scrolling is never taken over.
    const requireRow = new Adw.SwitchRow({
        title: 'Require a modifier', active: true, visible: false,
        subtitle: 'Turn off to run the action on plain scrolling.',
    });
    group.add(buttonRow);
    group.add(requireRow);
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
    const detect = (button, state) => {
        detected = button;
        const wheel = isWheelButton(button);
        buttonRow.subtitle = wheel
            ? 'Mouse wheel, as your system reports it (natural scrolling flips the directions)'
            : buttonName(button) + (button > 9 || button === 2 ? '' : ` (button ${button})`);
        buttonRow.title = wheel ? buttonName(button) : 'Button';
        const held = MODIFIER_IDS.indexOf(modifiersFromState(state, GTK_MASKS, false));
        // A wheel rule without held modifiers starts on Ctrl (the first row after None).
        modifierRow.selected = Math.max(wheel && held <= 0 ? MODIFIER_IDS.indexOf('ctrl') : 0, held);
        requireRow.visible = wheel;
        prompt.label = 'Choose the modifier and the action.';
        hint.visible = false;
        group.visible = true;
        validate();
    };
    const showStatus = text => {
        status.label = text ?? '';
        status.visible = !!text;
    };
    // Add is enabled only for a bindable, not yet bound (button, modifier).
    const validate = () => {
        if (detected === null)
            return;
        const wheel = isWheelButton(detected);
        modifierRow.sensitive = !(wheel && !requireRow.active);
        const mods = wheel && !requireRow.active ? '' : MODIFIER_IDS[modifierRow.selected] ?? '';
        let problem = unbindableReason(detected, mods, wheel && !requireRow.active);
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
        if (isWheelButton(button)) {
            // 4 to 7 are the wheel numbers, never real buttons; do not turn a click into a wheel rule.
            showStatus('Not a usable mouse button.');
            return;
        }
        if (button === 1 || button === 3) {
            // Primary and secondary are refused; this click may be on Cancel, so it is not claimed.
            showStatus(unbindableReason(button, ''));
            return;
        }
        detect(button, state);
    });
    box.add_controller(gesture);

    // The wheel: the first scroll event picks Wheel up, down, left or right (the axis with
    // the larger delta, vertical on a tie), as GNOME reports it (so it follows the natural
    // scrolling setting). Positive dx = right is the GTK convention (UNVERIFIED here).
    const scroll = new Gtk.EventControllerScroll({flags: Gtk.EventControllerScrollFlags.BOTH_AXES});
    scroll.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
    scroll.connect('scroll', (_controller, dx, dy) => {
        if (detected !== null || (dx === 0 && dy === 0))
            return false;
        const state = scroll.get_current_event_state() & Gtk.accelerator_get_default_mod_mask();
        if (Math.abs(dx) > Math.abs(dy))
            detect(dx < 0 ? WHEEL_LEFT : WHEEL_RIGHT, state);
        else
            detect(dy < 0 ? WHEEL_UP : WHEEL_DOWN, state);
        return true;
    });
    box.add_controller(scroll);
    modifierRow.connect('notify::selected', validate);
    requireRow.connect('notify::active', validate);

    let dialog = null;
    try {
        dialog = new Adw.Dialog({title: 'Press a button or turn the wheel', child: box, content_width: 420});
        dialog.present(window);
    } catch (e) {
        // Fallback: a modal window on top of the preferences window.
        dialog = new Adw.Window({
            title: 'Press a button or turn the wheel', modal: true, transient_for: window,
            default_width: 420, content: box,
        });
        dialog.present();
    }

    cancel.connect('clicked', () => dialog.close());
    add.connect('clicked', () => {
        if (detected === null)
            return;
        const bare = isWheelButton(detected) && !requireRow.active;
        const mods = bare ? '' : MODIFIER_IDS[modifierRow.selected] ?? '';
        if (unbindableReason(detected, mods, bare) || findDuplicate(existingRules, detected, mods) >= 0)
            return;
        onAdd(detected, mods, choices.ids[actionRow.selected] ?? 'none');
        dialog.close();
    });
}

export default class DesktopMouseNavPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage({
            title: 'Mouse buttons and wheel',
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

        const wheelGroup = new Adw.PreferencesGroup({
            title: 'Mouse wheel',
            description: 'How wheel rules count scrolling. Events are added up in one direction; an action runs when the sum reaches the amount, then wheel events are ignored for the pause.',
        });
        for (const [key, title, subtitle, min, max, step, digits] of WHEEL_SETTINGS) {
            const row = new Adw.SpinRow({
                title, subtitle, digits,
                adjustment: new Gtk.Adjustment({lower: min, upper: max, step_increment: step}),
            });
            settings.bind(key, row, 'value', Gio.SettingsBindFlags.DEFAULT);
            wheelGroup.add(row);
        }
        page.add(wheelGroup);
        addSwitches('Advanced', ADVANCED_SWITCHES);

        // Keep the settings object alive as long as the window (gjs.guide pattern).
        window._settings = settings;
        window.add(page);
    }

    _buildContextGroup(window, settings, context, toast) {
        const group = new Adw.PreferencesGroup(CONTEXT_TEXT[context]);
        const key = rulesKey(context);

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
                const row = this._buildRuleRow(rule, context, {
                    change: (field, value) => {
                        const current = readRules(settings, context);
                        if (!current[index])
                            return false;
                        const next = {...current[index], [field]: value};
                        if (field === 'mods') {
                            // A wheel rule set to no modifier is the user's explicit choice.
                            const problem = unbindableReason(next.input.button, next.mods, true);
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
            showRuleDialog(window, context, readRules(settings, context), (button, mods, action) => {
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
    _buildRuleRow(rule, context, edit) {
        const choices = actionChoices(context);
        const availability = actionAvailability(rule.action, context);
        const wheel = isWheelButton(rule.input.button);
        const row = new Adw.ActionRow({title: buttonName(rule.input.button)});
        let mods = rule.mods;
        const showNote = () => {
            row.subtitle = availability === 'unavailable' ? UNAVAILABLE_NOTE
                : availability === 'not-here' ? NOT_HERE_NOTE
                : wheel && mods === '' ? NO_MODIFIER_NOTE : '';
        };
        showNote();

        const modifierDrop = new Gtk.DropDown({
            model: stringList(MODIFIER_LABELS), valign: Gtk.Align.CENTER,
            selected: Math.max(0, MODIFIER_IDS.indexOf(mods)),
        });
        const actionDrop = new Gtk.DropDown({
            model: stringList(choices.labels), valign: Gtk.Align.CENTER,
            selected: Math.max(0, choices.ids.indexOf(rule.action)),
        });
        showFullLabels(modifierDrop);
        showFullLabels(actionDrop);
        let reverting = false;
        modifierDrop.connect('notify::selected', () => {
            if (reverting)
                return;
            const wanted = MODIFIER_IDS[modifierDrop.selected] ?? '';
            if (edit.change('mods', wanted)) {
                mods = wanted;
                showNote();
            } else {
                reverting = true;
                modifierDrop.selected = Math.max(0, MODIFIER_IDS.indexOf(mods));
                reverting = false;
            }
        });
        actionDrop.connect('notify::selected', () => {
            if (reverting)
                return;
            edit.change('action', choices.ids[actionDrop.selected] ?? 'none');
        });

        const remove = new Gtk.Button({
            icon_name: 'user-trash-symbolic', valign: Gtk.Align.CENTER,
            css_classes: ['flat'], tooltip_text: 'Delete this rule',
        });
        remove.connect('clicked', () => edit.remove());

        row.add_suffix(modifierDrop);
        // A disabled action is kept as saved (the dropdown would silently change it).
        if (availability === 'ok')
            row.add_suffix(actionDrop);
        row.add_suffix(remove);
        return row;
    }
}
