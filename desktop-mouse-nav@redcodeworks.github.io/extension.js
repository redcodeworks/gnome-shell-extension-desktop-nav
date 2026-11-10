// SPDX-License-Identifier: GPL-2.0-or-later
//
// Desktop Mouse Nav: mouse button rules (button, modifiers, action) per context, edited
// in the preferences window: the empty desktop, other Shell surfaces such as the top
// bar, the overview and the app grid. GNOME never passes presses over application
// windows to extensions. Default: Back/Forward switch workspaces on the empty desktop.

import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
// Namespace import: a missing export must not stop the extension from loading.
import * as OverviewControls from 'resource:///org/gnome/shell/ui/overviewControls.js';

import {
    CONTEXTS, WHEEL_DOWN, WHEEL_UP, anyRuleUsesButton, debugLine, findRule,
    isEmulatedScroll, modifiersFromState, newWheelState, pageTarget, parseRules, pointerContext,
    resolveAction, rulesKey, scrollInput, scrollMeta, wheelConfig, wheelNote, wheelReset, wheelStep,
    workspaceTarget,
} from './actions.js';

// Modifier bits of event.get_state() that count. Everything else except `ignore` (Caps
// Lock, Num Lock, the button bits) means "not exactly the rule". Super counts as either
// SUPER_MASK (1<<26) or MOD4_MASK (1<<6): which one Shell 51 reports is UNVERIFIED.
const MODIFIER_MASKS = {
    shift: Clutter.ModifierType.SHIFT_MASK,
    ctrl: Clutter.ModifierType.CONTROL_MASK,
    alt: Clutter.ModifierType.MOD1_MASK,
    super: Clutter.ModifierType.SUPER_MASK | Clutter.ModifierType.MOD4_MASK,
    ignore: Clutter.ModifierType.LOCK_MASK | Clutter.ModifierType.MOD2_MASK |
        Clutter.ModifierType.BUTTON1_MASK | Clutter.ModifierType.BUTTON2_MASK |
        Clutter.ModifierType.BUTTON3_MASK | Clutter.ModifierType.BUTTON4_MASK |
        Clutter.ModifierType.BUTTON5_MASK,
};

// Result for a press of a button no rule uses (shared, so nothing is allocated per press).
const NOT_USED = Object.freeze({
    mods: null, context: null, found: null, result: 'ignored', reason: 'no-rule-uses-button',
});

// Clutter.ScrollDirection by name, for scrollInput (pure, so it cannot import Clutter).
const SCROLL_NAMES = new Map([
    [Clutter.ScrollDirection.UP, 'up'],
    [Clutter.ScrollDirection.DOWN, 'down'],
    [Clutter.ScrollDirection.LEFT, 'left'],
    [Clutter.ScrollDirection.RIGHT, 'right'],
    [Clutter.ScrollDirection.SMOOTH, 'smooth'],
]);

// Events mutter synthesizes (the smooth twin of a wheel notch, the discrete steps of a
// touchpad) carry this flag and are skipped (UNVERIFIED binding name; undefined = no filter).
const EMULATED_FLAG = Clutter.EventFlags?.POINTER_EMULATED;

// ControlsState.APP_GRID is 2 (UNVERIFIED export, hence the fallback).
const APP_GRID_STATE = OverviewControls.ControlsState?.APP_GRID ?? 2;

export default class DesktopMouseNav extends Extension {
    enable() {
        this._pressedButton = null;
        this._wheel = newWheelState();
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
        this._rules = null;
        this._debug = false;
        this._pressedButton = null;
        this._wheel = null;
    }

    // Cache the parsed rules so a button press never reads GSettings.
    _loadActions() {
        this._rules = {};
        for (const context of CONTEXTS)
            this._rules[context] = parseRules(this._settings.get_value(rulesKey(context)).recursiveUnpack());
        this._wrap = this._settings.get_boolean('wrap-workspaces');
        this._debug = this._settings.get_boolean('debug-log');
        this._wheelConfig = wheelConfig(this._settings.get_double('wheel-threshold'),
            this._settings.get_double('wheel-min-interval'));
        this._wheel = wheelReset(this._wheel ?? newWheelState());
    }

    _onCapturedEvent(event) {
        const type = event.type();
        if (type === Clutter.EventType.SCROLL)
            return this._onScroll(event);
        if (type !== Clutter.EventType.BUTTON_PRESS &&
            type !== Clutter.EventType.BUTTON_RELEASE)
            return Clutter.EVENT_PROPAGATE;

        // Primary and secondary buttons are never touched.
        const button = event.get_button();
        if (button === 1 || button === 3)
            return Clutter.EVENT_PROPAGATE;

        if (type === Clutter.EventType.BUTTON_RELEASE) {
            // Swallow the release only when we swallowed the press.
            if (this._pressedButton === button) {
                this._pressedButton = null;
                return Clutter.EVENT_STOP;
            }
            return Clutter.EVENT_PROPAGATE;
        }

        // No rule at all uses this button: nothing to decide.
        const info = anyRuleUsesButton(this._rules, button)
            ? this._handlePress(event, button)
            : NOT_USED;
        this._logPress(event, button, info);
        if (info.result !== 'ran')
            return Clutter.EVENT_PROPAGATE;

        this._pressedButton = button;
        return Clutter.EVENT_STOP;
    }

    // Wheel events: reduced to up/down (horizontal scrolling is never touched), then the
    // same rule lookup as a button press (the wheel is button 4 and 5), then the
    // accumulator decides whether the action runs. A matching event is always swallowed
    // (also while it only accumulates or is rate limited), so the Shell does not also act
    // on it; everything else propagates.
    _onScroll(event) {
        const direction = SCROLL_NAMES.get(event.get_scroll_direction());
        const flags = event.get_flags?.();
        // Calibration fields, built only for the debug line.
        const meta = this._debug
            ? scrollMeta(direction, event.get_scroll_source?.(), flags)
            : null;
        if (isEmulatedScroll(flags, EMULATED_FLAG)) {
            if (this._debug)
                this._logPress(event, 0, {...NOT_USED, reason: 'emulated', note: meta});
            return Clutter.EVENT_PROPAGATE;
        }
        let dx = 0, dy = 0;
        if (direction === 'smooth') {
            try {
                [dx, dy] = event.get_scroll_delta();
            } catch (e) {
                return Clutter.EVENT_PROPAGATE;
            }
            // The end of a touchpad or kinetic scroll: start counting again.
            if (typeof event.get_scroll_finish_flags === 'function' &&
                event.get_scroll_finish_flags() !== 0)
                this._wheel = wheelReset(this._wheel);
        }
        const input = scrollInput(direction, dx, dy);
        if (!input)
            return Clutter.EVENT_PROPAGATE;

        const button = input.dir === 'up' ? WHEEL_UP : WHEEL_DOWN;
        input.time = event.get_time();
        input.meta = meta;
        const info = anyRuleUsesButton(this._rules, button)
            ? this._handlePress(event, button, input)
            : (this._debug ? {...NOT_USED, note: meta} : NOT_USED);
        this._logPress(event, button, info);
        return info.result === 'ran' || info.result === 'held'
            ? Clutter.EVENT_STOP
            : Clutter.EVENT_PROPAGATE;
    }

    // The only log call; nothing is logged (and nothing computed) unless the setting is on.
    _logPress(event, button, info) {
        if (this._debug) {
            console.log(this._pressLine(event, button, info));
        }
    }

    // The debug line of a press (only called with debug-log on).
    _pressLine(event, button, info) {
        const state = event.get_state();
        // Presses that returned before the modifier check still show their modifiers.
        const mods = info.mods ?? modifiersFromState(state, MODIFIER_MASKS, true);
        return debugLine(true, button, state, mods, info.context ?? this._contextOf(event),
            info.found, info.result, info.reason, info.note ?? null);
    }

    // Decides and runs; returns {mods, context, found, result, reason, note}, result 'ran',
    // 'propagated', 'at-end', 'ignored' or (wheel only) 'held'. `context` stays null when
    // it was not needed. `input` is the scrollInput result for a wheel event, else null.
    _handlePress(event, button, input = null) {
        const info = {
            mods: null, context: null, found: null, result: 'ignored', reason: null, note: null,
        };
        if (Main.sessionMode.isLocked || (Main.modalCount > 0 && !Main.overview.visible)) {
            info.reason = 'locked-or-modal';
            return info;
        }

        info.mods = modifiersFromState(event.get_state(), MODIFIER_MASKS, true);
        if (info.mods === null) {
            info.reason = 'other-modifier-bits';
            return info;
        }

        const overviewVisible = Main.overview.visible;
        const appGridShowing = overviewVisible && this._appGridShowing();

        // The actor lookup only when a desktop rule uses this button.
        const desktopUsed = this._rules.desktop.some(rule => rule.input.button === button);
        const context = pointerContext({
            overviewVisible, appGridShowing,
            onEmptyDesktop: !overviewVisible && desktopUsed && this._pointerOnEmptyDesktop(event),
        });
        info.context = context;
        info.found = findRule(this._rules, context, button, info.mods);
        if (!info.found) {
            info.result = 'propagated';
            info.reason = 'no-matching-rule';
            return info;
        }

        if (input) {
            const step = wheelStep(this._wheel, input, this._wheelConfig);
            this._wheel = step.state;
            info.note = wheelNote(input, step.state);
            if (!step.fire) {
                info.result = 'held';
                info.reason = step.reason;
                return info;
            }
        }

        const todo = resolveAction(info.found.rule.action, context);
        try {
            info.result = todo.type === 'page'
                ? this._pageAppGrid(todo.step)
                : this._runAction(todo.id);
        } catch (e) {
            info.result = 'propagated';
            info.reason = 'action-threw';
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
