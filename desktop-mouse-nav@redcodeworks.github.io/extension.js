// SPDX-License-Identifier: GPL-2.0-or-later
//
// Desktop Mouse Nav: the mouse Back/Forward buttons switch workspaces, but only
// while the pointer is over the empty desktop (the background, not a window,
// not the overview, not a modal dialog).

import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Button numbers as reported by event.get_button() (X11-style numbering:
// 4-7 are scroll, so the side buttons are 8 and 9). UNVERIFIED on Shell 51.
const BUTTON_BACK = 8;
const BUTTON_FORWARD = 9;

// Ideas, not built yet: a `wrap` setting and a `swap buttons` setting.
const WRAP = false;
const SWAP_BUTTONS = false;

const LOG_PREFIX = 'desktop-mouse-nav:';

export default class DesktopMouseNav extends Extension {
    enable() {
        this._pressedButton = null;
        this._capturedId = global.stage.connect(
            'captured-event', (_stage, event) => this._onCapturedEvent(event));
    }

    disable() {
        if (this._capturedId) {
            global.stage.disconnect(this._capturedId);
            this._capturedId = 0;
        }
        this._pressedButton = null;
    }

    _onCapturedEvent(event) {
        const type = event.type();
        if (type !== Clutter.EventType.BUTTON_PRESS &&
            type !== Clutter.EventType.BUTTON_RELEASE)
            return Clutter.EVENT_PROPAGATE;

        const button = event.get_button();
        if (button !== BUTTON_BACK && button !== BUTTON_FORWARD)
            return Clutter.EVENT_PROPAGATE;

        if (type === Clutter.EventType.BUTTON_RELEASE) {
            // Swallow the release only when we swallowed the press.
            if (this._pressedButton === button) {
                this._pressedButton = null;
                return Clutter.EVENT_STOP;
            }
            return Clutter.EVENT_PROPAGATE;
        }

        if (!this._pointerOnEmptyDesktop(event))
            return Clutter.EVENT_PROPAGATE;

        const back = SWAP_BUTTONS ? button === BUTTON_FORWARD : button === BUTTON_BACK;
        this._switchWorkspace(back ? -1 : 1);
        this._pressedButton = button;
        return Clutter.EVENT_STOP;
    }

    _pointerOnEmptyDesktop(event) {
        if (Main.overview.visible || Main.modalCount > 0 || Main.sessionMode.isLocked)
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
        console.debug(`${LOG_PREFIX} not the desktop: ${actor}`);
        return false;
    }

    _switchWorkspace(step) {
        const manager = global.workspace_manager;
        const count = manager.get_n_workspaces();
        let index = manager.get_active_workspace_index() + step;

        if (WRAP)
            index = (index + count) % count;
        else if (index < 0 || index >= count)
            return;

        const workspace = manager.get_workspace_by_index(index);
        if (!workspace)
            return;
        console.debug(`${LOG_PREFIX} activating workspace ${index}`);
        workspace.activate(global.get_current_time());
    }
}
