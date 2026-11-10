# Desktop Mouse Nav

A GNOME Shell extension: choose what your extra mouse buttons and the mouse wheel do, with optional modifier keys. By default, pressing one while the pointer is over the empty desktop moves to the previous or next workspace, and windows, games and the overview keep their own Back and Forward behavior.

## Requirements

- GNOME Shell 51 (Wayland)
- For the install commands: [`just`](https://github.com/casey/just), `unzip`, and (for `just install`) the GitHub CLI `gh`

## Install

Pick one:

- `just install`: the latest release (no build tools needed). `just install 0.1.1` installs a specific release. It verifies the checksum first, says "already installed" when nothing would change, and `--dry-run` shows what it would do.
- `just install --testing`: the latest testing build, a rolling prerelease that is replaced on every push to the `testing` branch once its checks pass. Meant for trying changes before they are released.
- `just install-local`: builds the zip from your working tree and unpacks it (needs `gnome-extensions`).

You can also download the zip from the Releases page and unpack it into `~/.local/share/gnome-shell/extensions/desktop-mouse-nav@redcodeworks.github.io/`, then run `glib-compile-schemas schemas/` inside that directory. All unpack routes need `glib-compile-schemas` for the settings schema (Fedora package `glib2-devel`).

On Wayland, log out and back in after the first install, then run `just enable`. `just uninstall` removes it again.

## Usage

By default, with no window under the pointer, Back goes to the previous workspace and Forward to the next one (it stops at the first and last workspace).

**Default rules** (a fresh install has these, no setup):

| Input | Desktop, top bar, overview | App grid |
|---|---|---|
| Back button (desktop only) | Previous workspace | |
| Forward button (desktop only) | Next workspace | |
| Alt + wheel up | Step in | Step in |
| Alt + wheel down | Step out | Step out |
| Alt + wheel left | Previous workspace | App grid: previous page |
| Alt + wheel right | Next workspace | App grid: next page |

Plain scrolling is never taken over, because every wheel rule needs Alt. All of this can be edited or deleted in the settings.

Open the extension's settings (for example `gnome-extensions prefs desktop-mouse-nav@redcodeworks.github.io`, or the Extensions app). Each group is a list of rules: a mouse button, an optional modifier (Ctrl, Shift, Alt, Super or a combination) and an action. The first matching rule wins, and a rule only matches when exactly its modifiers are held.

**Add a rule:** choose "Add rule" at the end of a list, then click the mouse button you want to use. The button is detected, and any modifier keys you hold are pre-filled. Pick the modifier and the action, then choose Add. You can change the modifier or the action later in the list, or delete a rule with the trash button. The primary and secondary buttons cannot be used, the middle button only together with a modifier, and the same button and modifier cannot be bound twice in one list.

**Where rules apply:**

- **On the empty desktop**: the pointer is over the desktop background (not over a window). If no rule here matches, the rules for the top bar and shell surfaces are tried too.
- **Top bar and shell surfaces**: the top bar and other parts of the Shell.
- **Overview** and **App grid**: while they are open, only their own rules apply. A list with no rules does nothing. Previous and next workspace switch workspaces there too; the app grid list also offers "App grid: previous page" and "App grid: next page" to turn the pages of the grid.

GNOME never passes mouse buttons pressed over application windows to extensions (the Shell maintainers confirmed this on the GNOME Discourse in 2020; I have not re-checked it for Shell 51), so there is nothing to set for windows: applications always keep their buttons.

**Mouse wheel:** "Add rule" also detects the wheel: turn it in the dialog to pick Wheel up or Wheel down. Wheel rules need a modifier by default (Ctrl is pre-selected), so normal scrolling is never taken over; turn off "Require a modifier" in the dialog to run an action on plain scrolling. Wheel support was written without a live test session. Still to verify on a real desktop: the natural scrolling direction, and whether Super plus the wheel reaches the extension even over windows (not built); the debug log, which shows the scroll source and flags, is the way to find out. Directions are as GNOME reports them, so they follow your natural scrolling setting. The wheel includes the horizontal directions, Wheel left and Wheel right (tilt wheels and horizontal two-finger scrolling); the same amount and pause settings apply to all four directions, and one pause is shared, so a burst in any direction runs one action. Like the buttons, the wheel only works over the empty desktop, Shell surfaces, the overview and the app grid, not over application windows.

The "Mouse wheel" settings group keeps one burst of scrolling from switching several workspaces: scrolling is added up until it reaches "Scroll needed per action" (default 1 notch, one click of a notched wheel), then the action runs and wheel events are ignored for "Pause between actions" (default 400 ms). Raise the amount for a high-resolution or free-spin wheel.

Actions: previous or next workspace, toggle the overview, toggle the app grid, step out, step in, toggle the quick settings menu, toggle the calendar, turn the app grid page (app grid list only), or do nothing. When the overview is open, the two toggles switch between the window picker and the app grid instead of doing nothing (toggle the overview closes it from the window picker).

**Step out and Step in** work with any input and in any list. Step out goes one level at a time from the desktop to the overview (window picker) and then to the app grid; Step in goes back the other way, from the app grid to the window picker and then to the desktop. They do not wrap: at the end nothing happens (the rule still takes the event). A handy pair: Ctrl + Wheel down = Step out, Ctrl + Wheel up = Step in.

**Quick settings and calendar:** "Toggle quick settings" and "Toggle calendar" open or close those top bar menus. They are offered in the desktop and top bar lists only; opening a menu over the overview could not be checked without a live session, so they are not offered in the Overview and App grid lists. While a menu is open, GNOME treats the Shell as modal and the rule does not run, so close the menu by clicking elsewhere or pressing Escape.

Other settings:

- "Wrap around workspaces" (off by default): Back on the first workspace goes to the last, and Forward on the last goes to the first. Also applies to moving a window.
- "Log button presses" (Advanced, off by default): for troubleshooting. Writes one line per mouse button press or wheel event to the journal, including presses that were ignored and why; read it with `journalctl --user -b -o cat | grep desktop-mouse-nav`.

Changes in 0.6.0: the Alt + wheel default rules above (up and down step in and out, left and right switch workspaces or turn app grid pages). Written without a live GNOME session.

Changes in 0.5.0: Wheel left and Wheel right as inputs (numbers 6 and 7 in the saved rules, which used to be plain button numbers that real mice do not send); the actions Step out and Step in; the actions Toggle quick settings and Toggle calendar. All of this was written without a live GNOME session. The window move actions are still hidden.

Changes in 0.4.1: previous and next workspace switch workspaces again in the app grid (0.4.0 turned the grid's pages with them; the new page actions do that now, and rules you saved keep their action); the dropdown lists show the full action names; the two toggles switch between the overview and the app grid. The "move the focused window to another workspace" actions are disabled for now because they did not work (they are planned to return): a rule that already uses one stays in the list as "Unavailable in this version" and does nothing.

Upgrading from 0.5.0: saved rules keep working. The new default rules apply to every list you never edited, so if you left a list untouched it now has the Alt + wheel rules (and an empty list you never touched is no longer empty); a list you edited, even to empty it, stays as it is. To remove the new rules, delete them in the settings.

Upgrading from 0.4.1: nothing to do, saved rules keep working.

Upgrading from 0.3.0: nothing to do, existing rules keep working.

Upgrading from 0.2.0: the old per-button settings are gone, and the default rules (Back and Forward switch workspaces on the desktop) are back; other choices from 0.2.0 have to be added again as rules.

## Contributing

Work happens on a branch (`feat/<topic>`, `fix/<topic>`) that goes by pull request into `testing`, and a pull request promotes `testing` to `main`. Maintainer notes are in `CLAUDE.md`. Run `just test` first; a weekly check (Mondays) tries the latest release against the next Fedora release and only warns. A new release needs a new `version-name` in `metadata.json` (digits and periods, for example `0.6.0`).

## License

GPL-2.0-or-later, see `LICENSE`.

## Credits

Written with the help of Claude (Anthropic). Built on GNOME Shell's extension API.

## Disclaimer

This is a personal project, written with Claude's help, so please excuse the slop. I only tested it on my own setup and will not actively maintain it beyond my own needs. If you find something valuable here, please fork it.
