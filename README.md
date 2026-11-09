# Desktop Mouse Nav

A GNOME Shell extension: press the mouse Back or Forward button while the pointer is over the empty desktop to move to the previous or next workspace. Windows, games and the overview keep their own Back and Forward behavior.

## Requirements

- GNOME Shell 51 (Wayland)

## Install and usage

Build the zip and install it:

```
just pack
gnome-extensions install --force dist/desktop-mouse-nav@redcodeworks.github.io.shell-extension.zip
```

On Wayland, log out and back in, then enable it with `gnome-extensions enable desktop-mouse-nav@redcodeworks.github.io`.

Usage: with no window under the pointer, Back goes to the previous workspace and Forward to the next one. It stops at the first and last workspace (no wrap-around).

## Contributing

This is a private repository for now. Changes go through pull requests from the `testing` branch into `main`; run `just lint` first.

## License

GPL-2.0-or-later, see `LICENSE`.

## Credits

Written with the help of Claude (Anthropic). Built on GNOME Shell's extension API.

## Disclaimer

This is a personal project, written with Claude's help, so please excuse the slop. I only tested it on my own setup and will not actively maintain it beyond my own needs. If you find something valuable here, please fork it.
