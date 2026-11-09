# Desktop Mouse Nav

A GNOME Shell extension: press the mouse Back or Forward button while the pointer is over the empty desktop to move to the previous or next workspace. Windows, games and the overview keep their own Back and Forward behavior.

## Requirements

- GNOME Shell 51 (Wayland)
- For the install commands: [`just`](https://github.com/casey/just), `unzip`, and (for `just install-release`) the GitHub CLI `gh`

## Install

Pick one:

- From a release (no build tools needed): `just install-release` installs the latest release, `just install-release 0.1.0` a specific one. It verifies the checksum first; `--dry-run` shows what it would do. You can also download the zip from the Releases page and unpack it into `~/.local/share/gnome-shell/extensions/desktop-mouse-nav@redcodeworks.github.io/`.
- From source: `just install` builds the zip and unpacks it into the extensions directory (needs `gnome-extensions`).

On Wayland, log out and back in after the first install, then run `just enable`. `just uninstall` removes it again.

## Usage

With no window under the pointer, Back goes to the previous workspace and Forward to the next one. It stops at the first and last workspace (no wrap-around).

## Contributing

Changes go through pull requests from the `testing` branch into `main`; run `just test` first. A new release needs a new `version-name` in `metadata.json` (digits and periods, for example `0.1.1`).

## License

GPL-2.0-or-later, see `LICENSE`.

## Credits

Written with the help of Claude (Anthropic). Built on GNOME Shell's extension API.

## Disclaimer

This is a personal project, written with Claude's help, so please excuse the slop. I only tested it on my own setup and will not actively maintain it beyond my own needs. If you find something valuable here, please fork it.
