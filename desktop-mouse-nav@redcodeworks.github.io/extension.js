// SPDX-License-Identifier: GPL-2.0-or-later
//
// Desktop Mouse Nav: the mouse Back/Forward buttons run a configurable action
// (preferences window): on the empty desktop (also while the overview or the app grid
// is open, when enabled) and on other Shell surfaces such as the top bar. GNOME never
// passes presses over application windows to extensions. Defaults: workspace
// switching on the desktop, nothing on Shell surfaces.

import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
// Namespace import: a missing export must not stop the extension from loading.
import * as OverviewControls from 'resource:///org/gnome/shell/ui/overviewControls.js';

import {
    BUTTONS, CONTEXTS, debugLine, overviewAllowed, pageTarget, pickAction, pointerContext,
    resolveAction, settingsKey, treatAsDesktop, workspaceTarget,
} from './actions.js';

// Button numbers as reported by event.get_button() (X11-style numbering:
// 4-7 are scroll, so the side buttons are 8 and 9). UNVERIFIED on Shell 51.
const BUTTON_NAMES = new Map([[8, 'back'], [9, 'forward']]);

// ControlsState.APP_GRID is 2 (UNVERIFIED export, hence the fallback).
const APP_GRID_STATE = OverviewControls.ControlsState?.APP_GRID ?? 2;

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
        this._debug = false;
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
        this._wrap = this._settings.get_boolean('wrap-workspaces');
        this._debug = this._settings.get_boolean('debug-log');
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

        const info = this._handlePress(event, name);
        // The only log call; nothing is logged unless the setting is on.
        if (this._debug) {
            const line = debugLine(this._debug, name, info.context ?? this._contextOf(event),
                info.action, info.result);
            if (line)
                console.debug(line);
        }
        if (info.result !== 'ran')
            return Clutter.EVENT_PROPAGATE;

        this._pressedButton = button;
        return Clutter.EVENT_STOP;
    }

    // Decides and runs; returns {context, action, result}, result 'ran', 'propagated'
    // or 'at-end'. `context` stays null when it was not needed (and logging is off).
    _handlePress(event, name) {
        const info = {context: null, action: 'none', result: 'propagated'};
        const read = key => this._actions[key];
        const desktopSet = read(settingsKey('desktop', name)) !== 'none';
        const shellSet = read(settingsKey('shell', name)) !== 'none';
        // Cheapest checks first: nothing configured for this button, nothing to do.
        if (!desktopSet && !shellSet)
            return info;

        if (Main.sessionMode.isLocked || (Main.modalCount > 0 && !Main.overview.visible))
            return info;

        const overviewVisible = Main.overview.visible;
        const appGridShowing = overviewVisible && this._appGridShowing();
        if (!overviewAllowed({overviewVisible, appGridShowing}, this._flags))
            return info;

        const context = pointerContext({
            overviewVisible, appGridShowing,
            onEmptyDesktop: !overviewVisible && desktopSet && this._pointerOnEmptyDesktop(event),
        });
        info.context = context;
        info.action = pickAction(read, treatAsDesktop(context), name);
        if (info.action === 'none')
            return info;

        const todo = resolveAction(info.action, context);
        try {
            info.result = todo.type === 'page'
                ? this._pageAppGrid(todo.step)
                : this._runAction(todo.id);
        } catch (e) {
            info.result = 'propagated';
        }
        return info;
    }

    // Context for a log line when the press returned early (debug only).
    _contextOf(event) {
        const overviewVisible = Main.overview.visible;
        return pointerContext({
            overviewVisible,
            appGridShowing: overviewVisible && this._appGridShowing(),
            onEmptyDesktop: !overviewVisible && this._pointerOnEmptyDesktop(event),
        });
    }

    // UNVERIFIED: Main.overview.controls; falls back to the private _overview.
    _controls() {
        return Main.overview.controls ?? Main.overview._overview?.controls ?? null;
    }

    // UNVERIFIED detector: the state adjustment at APP_GRID, else the dash button.
    _appGridShowing() {
        try {
            const adjustment = this._controls()?._stateAdjustment;
            if (adjustment)
                return adjustment.value >= APP_GRID_STATE - 0.001;
            return !!Main.overview.dash?.showAppsButton?.checked;
        } catch (e) {
            return false;
        }
    }

    // Pages the app grid; never wraps. UNVERIFIED on a live Shell (private _grid).
    _pageAppGrid(step) {
        const appDisplay = this._controls()?.appDisplay;
        const grid = appDisplay?._grid;
        if (!appDisplay || !grid || typeof appDisplay.goToPage !== 'function')
            return 'propagated';
        const target = pageTarget(grid.currentPage, grid.nPages, step);
        if (target === null)
            return 'at-end';
        appDisplay.goToPage(target);
        return 'ran';
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

    // Runs one action through the Shell API; returns 'ran', 'at-end' or 'propagated'.
    _runAction(action) {
        switch (action) {
        case 'prev-workspace':
            return this._switchWorkspace(-1);
        case 'next-workspace':
            return this._switchWorkspace(1);
        case 'toggle-overview':
            Main.overview.toggle();
            return 'ran';
        case 'toggle-app-grid':
            this._toggleAppGrid();
            return 'ran';
        case 'move-window-prev-workspace':
            return this._moveFocusedWindow(-1);
        case 'move-window-next-workspace':
            return this._moveFocusedWindow(1);
        default:
            return 'propagated';
        }
    }

    _toggleAppGrid() {
        if (Main.overview.visible && this._appGridShowing())
            Main.overview.hide();
        else
            Main.overview.showApps();
    }

    // The workspace `step` away from the active one, or null (ends, or one workspace).
    _neighborWorkspace(step) {
        const manager = global.workspace_manager;
        const index = workspaceTarget(manager.get_active_workspace_index(),
            manager.get_n_workspaces(), step, this._wrap);
        return index === null ? null : manager.get_workspace_by_index(index);
    }

    _switchWorkspace(step) {
        const workspace = this._neighborWorkspace(step);
        if (!workspace)
            return 'at-end';
        workspace.activate(global.get_current_time());
        return 'ran';
    }

    _moveFocusedWindow(step) {
        const window = global.display.focus_window;
        if (!window || window.get_window_type() !== Meta.WindowType.NORMAL ||
            window.is_on_all_workspaces())
            return 'propagated';
        const workspace = this._neighborWorkspace(step);
        if (!workspace)
            return 'at-end';
        window.change_workspace(workspace);
        workspace.activate_with_focus(window, global.get_current_time());
        return 'ran';
    }
}
