// SPDX-License-Identifier: GPL-2.0-or-later
//
// Desktop Mouse Nav: the mouse Back/Forward buttons run a configurable action
// (preferences window), separately for the empty desktop (the background, not a
// window, not the overview, not a modal dialog) and for anywhere else. Defaults:
// workspace switching on the desktop, nothing elsewhere.

import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {BUTTONS, CONTEXTS, overviewAllowed, pickAction, settingsKey} from './actions.js';

// Button numbers as reported by event.get_button() (X11-style numbering:
// 4-7 are scroll, so the side buttons are 8 and 9). UNVERIFIED on Shell 51.
const BUTTON_NAMES = new Map([[8, 'back'], [9, 'forward']]);

// Idea, not built yet: a `wrap` setting.
const WRAP = false;

export default class DesktopMouseNav extends Extension {
    enable() {
        this._pressedButton = null;
        this._settings = this.getSettings();
        this._loadActions();
        this._settingsChangedId = this._settings.connect('changed', () => this._loadActions());
        this._capturedId = global.stage.connect(
            'captured-event', (_stage, event) => this._onCapturedEvent(event));
    }

    disable() {
        if (this._capturedId) {
            global.stage.disconnect(this._capturedId);
            this._capturedId = 0;
        }
        if (this._settingsChangedId) {
            this._settings.disconnect(this._settingsChangedId);
            this._settingsChangedId = 0;
        }
        this._settings = null;
        this._actions = null;
        this._flags = null;
        this._pressedButton = null;
    }

    // Cache the configured actions so a button press never reads GSettings.
    _loadActions() {
        this._actions = {};
        for (const context of CONTEXTS) {
            for (const button of BUTTONS) {
                const key = settingsKey(context, button);
                this._actions[key] = this._settings.get_string(key);
            }
        }
        this._flags = {
            inOverview: this._settings.get_boolean('work-in-overview'),
            inAppGrid: this._settings.get_boolean('work-in-app-grid'),
        };
    }

    _onCapturedEvent(event) {
        const type = event.type();
        if (type !== Clutter.EventType.BUTTON_PRESS &&
            type !== Clutter.EventType.BUTTON_RELEASE)
            return Clutter.EVENT_PROPAGATE;

        const button = event.get_button();
        const name = BUTTON_NAMES.get(button);
        if (!name)
            return Clutter.EVENT_PROPAGATE;

        if (type === Clutter.EventType.BUTTON_RELEASE) {
            // Swallow the release only when we swallowed the press.
            if (this._pressedButton === button) {
                this._pressedButton = null;
                return Clutter.EVENT_STOP;
            }
            return Clutter.EVENT_PROPAGATE;
        }

        // Cheapest checks first: nothing configured for this button, nothing to do.
        const read = key => this._actions[key];
        const desktopSet = read(settingsKey('desktop', name)) !== 'none';
        const anywhereSet = read(settingsKey('anywhere', name)) !== 'none';
        if (!desktopSet && !anywhereSet)
            return Clutter.EVENT_PROPAGATE;

        if (Main.sessionMode.isLocked || (Main.modalCount > 0 && !Main.overview.visible))
            return Clutter.EVENT_PROPAGATE;

        // Overview gate (UNVERIFIED detector: showAppsButton.checked). Note that
        // Main.overview.toggle while the overview is open closes it, and the
        // toggle-app-grid action while the grid is showing is already handled in
        // _toggleAppGrid; both keep their behavior when the toggle allows it.
        const overviewVisible = Main.overview.visible;
        const appGridShowing = overviewVisible && Main.overview.dash.showAppsButton.checked;
        if (!overviewAllowed({overviewVisible, appGridShowing}, this._flags))
            return Clutter.EVENT_PROPAGATE;

        const onDesktop = desktopSet && this._pointerOnEmptyDesktop(event);
        const action = pickAction(read, onDesktop, name);
        if (action === 'none' || !this._runAction(action))
            return Clutter.EVENT_PROPAGATE;

        this._pressedButton = button;
        return Clutter.EVENT_STOP;
    }

    _pointerOnEmptyDesktop(event) {
        if (Main.overview.visible)
            return false;

        const [x, y] = event.get_coords();
        const actor = global.stage.get_actor_at_pos(Clutter.PickMode.REACTIVE, x, y);
        if (!actor)
            return false;

        // Windows live in global.window_group, above the background group, so a
        // background actor under the pointer means no window is there.
        const backgroundGroup = Main.layoutManager._backgroundGroup;
        for (let a = actor; a; a = a.get_parent()) {
            if (a instanceof Meta.BackgroundActor || a === backgroundGroup)
                return true;
        }
        return false;
    }

    // Runs one action through the Shell API; returns false when it did nothing.
    _runAction(action) {
        switch (action) {
        case 'prev-workspace':
            return this._switchWorkspace(-1);
        case 'next-workspace':
            return this._switchWorkspace(1);
        case 'toggle-overview':
            Main.overview.toggle();
            return true;
        case 'toggle-app-grid':
            this._toggleAppGrid();
            return true;
        case 'move-window-prev-workspace':
            return this._moveFocusedWindow(-1);
        case 'move-window-next-workspace':
            return this._moveFocusedWindow(1);
        default:
            return false;
        }
    }

    _toggleAppGrid() {
        if (Main.overview.visible && Main.overview.dash.showAppsButton.checked)
            Main.overview.hide();
        else
            Main.overview.showApps();
    }

    // The workspace `step` away from the active one, or null at the ends.
    _neighborWorkspace(step) {
        const manager = global.workspace_manager;
        const count = manager.get_n_workspaces();
        let index = manager.get_active_workspace_index() + step;

        if (WRAP)
            index = (index + count) % count;
        else if (index < 0 || index >= count)
            return null;

        return manager.get_workspace_by_index(index);
    }

    _switchWorkspace(step) {
        const workspace = this._neighborWorkspace(step);
        if (!workspace)
            return false;
        workspace.activate(global.get_current_time());
        return true;
    }

    _moveFocusedWindow(step) {
        const window = global.display.focus_window;
        if (!window || window.get_window_type() !== Meta.WindowType.NORMAL ||
            window.is_on_all_workspaces())
            return false;
        const workspace = this._neighborWorkspace(step);
        if (!workspace)
            return false;
        window.change_workspace(workspace);
        workspace.activate_with_focus(window, global.get_current_time());
        return true;
    }
}
