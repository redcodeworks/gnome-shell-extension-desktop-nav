# CLAUDE.md

GNOME Shell extension `desktop-mouse-nav@redcodeworks.github.io` (GPL-2.0-or-later, private repo `redcodeworks/desktop-mouse-nav`). Target: GNOME Shell 51 (Fedora 45, Wayland). Mouse Back/Forward (buttons 8/9) switch workspaces only when the pointer is over the empty desktop.

## Layout
Subdirectory layout: the extension lives in `desktop-mouse-nav@redcodeworks.github.io/` (`extension.js`, `metadata.json`) so the repo root can hold LICENSE, README, justfile, CI. `gnome-extensions pack <dir>` accepts a source directory, so no flat layout is needed.

## Design
- ESM; `extension.js` default-exports a class extending `Extension`.
- `enable()` connects `global.stage` `captured-event`; `disable()` disconnects it (no timers, no other state).
- Press of button 8 (Back) or 9 (Forward): act only if overview is closed, no modal is open, session is not locked, and `get_actor_at_pos(REACTIVE)` at the pointer is a `Meta.BackgroundActor` or inside `Main.layoutManager._backgroundGroup`. Handled press returns `EVENT_STOP` and remembers the button so the matching release is swallowed too; everything else returns `EVENT_PROPAGATE`.
- Switching: index arithmetic on `global.workspace_manager`, `workspace.activate(global.get_current_time())`. `WRAP` and `SWAP_BUTTONS` are constants (false) marking where future settings go.
- Logging: `console.debug` with the `desktop-mouse-nav:` prefix.

## Ideas, not built
- `wrap` setting (wrap around at the ends), `swap buttons` setting, a GSettings schema and prefs page.

## Unverified (no live Shell was available when this was written)
Everything about runtime behavior, in particular:
- Button numbers 8 and 9 for Back/Forward on Shell 51 (from memory of Mutter's evdev mapping, BTN_SIDE/BTN_EXTRA).
- That `get_actor_at_pos(REACTIVE)` returns the background actor (reactive because of the desktop context menu) on the empty desktop in Shell 51, and that `Meta.BackgroundActor` is still the class used.
- `Main.modalCount`, `Main.sessionMode.isLocked`, `Main.layoutManager._backgroundGroup` (private) still exist in 51.
- Whether the click reaches the stage at all with Dash to Dock, Tiling Shell, desktop-icon extensions (those add windows or chrome over the desktop, which then count as "not the desktop").
- `gnome-extensions pack --out-dir` segfaults (signal 11, exit 139) when the output directory does not exist: `just pack` and CI create `dist/` first. CI on the `fedora:45` container and `ubuntu-26.04` runner worked for the other steps.

## Testing
```
just lint            # JSON + JS syntax
just pack            # dist/*.zip
just install-local   # prints the install commands
```
Install, log out and in (Wayland), `gnome-extensions enable desktop-mouse-nav@redcodeworks.github.io`, watch logs with `journalctl -f -o cat /usr/bin/gnome-shell` (debug lines need debug logging enabled, e.g. `G_MESSAGES_DEBUG=all`). Test: click Back/Forward on empty desktop, on a window, in the overview.

## CI
`.github/workflows/ci.yml`, push to `testing` only, one required job `test` (runner `ubuntu-26.04`, `fedora:45` container, actions pinned by SHA): JSON, JS syntax, `gnome-extensions pack`.
