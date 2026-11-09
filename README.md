# Desktop Mouse Nav

A GNOME Shell extension: choose what the mouse Back and Forward buttons do. By default, pressing one while the pointer is over the empty desktop moves to the previous or next workspace, and windows, games and the overview keep their own Back and Forward behavior.

## Requirements

- GNOME Shell 51 (Wayland)
- For the install commands: [`just`](https://github.com/casey/just), `unzip`, and (for `just install-release`) the GitHub CLI `gh`

## Install

Pick one:

- From a release (no build tools needed): `just install-release` installs the latest release, `just install-release 0.1.0` a specific one. It verifies the checksum first; `--dry-run` shows what it would do. You can also download the zip from the Releases page and unpack it into `~/.local/share/gnome-shell/extensions/desktop-mouse-nav@redcodeworks.github.io/`, then run `glib-compile-schemas schemas/` inside that directory.
- From source: `just install` builds the zip and unpacks it into the extensions directory (needs `gnome-extensions`). Both unpack routes compile the settings schema, which needs `glib-compile-schemas` (Fedora package `glib2-devel`).

On Wayland, log out and back in after the first install, then run `just enable`. `just uninstall` removes it again.

## Usage

By default, with no window under the pointer, Back goes to the previous workspace and Forward to the next one (it stops at the first and last workspace).

Open the extension's settings (for example `gnome-extensions prefs desktop-mouse-nav@redcodeworks.github.io`, or the Extensions app) to pick an action for each button in two places: on the empty desktop, and anywhere else. Anywhere else defaults to "Do nothing", so applications keep their buttons until you choose otherwise. Actions: previous or next workspace, toggle the overview, toggle the app grid, move the focused window to the previous or next workspace, or do nothing. Two switches under "Overview" (both off by default) let the buttons also work while the overview is open ("Work in the Overview") or while the app grid is showing ("Work in the app grid"). If the desktop setting is "Do nothing", the anywhere setting applies on the desktop too.

## Contributing

Changes go through pull requests from the `testing` branch into `main`; run `just test` first. A new release needs a new `version-name` in `metadata.json` (digits and periods, for example `0.2.0`).

## License

GPL-2.0-or-later, see `LICENSE`.

## Credits

Written with the help of Claude (Anthropic). Built on GNOME Shell's extension API.

## Disclaimer

This is a personal project, written with Claude's help, so please excuse the slop. I only tested it on my own setup and will not actively maintain it beyond my own needs. If you find something valuable here, please fork it.
