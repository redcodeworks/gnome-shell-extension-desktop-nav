uuid := "desktop-mouse-nav@redcodeworks.github.io"

default:
    @just --list

# Quick checks: JSON validity and JS syntax (extension.js is ESM, checked as a .mjs copy).
lint:
    node -e 'JSON.parse(require("fs").readFileSync("{{uuid}}/metadata.json","utf8"))'
    d=$(mktemp -d) && cp {{uuid}}/extension.js "$d/extension.mjs" && node --check "$d/extension.mjs"; rc=$?; rm -rf "$d"; exit $rc

# Build the installable zip into dist/.
pack:
    gnome-extensions pack --force --out-dir dist {{uuid}}

# Print the install commands (does not touch your home).
install-local:
    @echo "just pack"
    @echo "gnome-extensions install --force dist/{{uuid}}.shell-extension.zip"
    @echo "# Wayland: log out and in, then:"
    @echo "gnome-extensions enable {{uuid}}"
    @echo "# logs: journalctl -f -o cat /usr/bin/gnome-shell"
