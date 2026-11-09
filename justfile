set shell := ["bash", "-euo", "pipefail", "-c"]

# One source of truth for the uuid; `install` refuses to run if metadata.json disagrees.
uuid := "desktop-mouse-nav@redcodeworks.github.io"
extdir := env_var_or_default("GNOME_EXTENSIONS_DIR", env_var("HOME") + "/.local/share/gnome-shell/extensions")

default:
    @just --list

# Quick checks: JSON validity and JS syntax (extension.js is ESM, checked as a .mjs copy).
lint:
    node -e 'JSON.parse(require("fs").readFileSync("{{uuid}}/metadata.json","utf8"))'
    d=$(mktemp -d) && cp {{uuid}}/extension.js "$d/extension.mjs" && node --check "$d/extension.mjs"; rc=$?; rm -rf "$d"; exit $rc

# Build the installable zip into dist/ (gnome-extensions pack segfaults if the directory is missing).
pack:
    mkdir -p dist
    gnome-extensions pack --force --out-dir dist {{uuid}}

# Unpack the zip into the extensions directory, replacing the previous copy of this uuid only.
install: pack
    #!/usr/bin/env bash
    set -euo pipefail
    command -v unzip >/dev/null || { echo "error: unzip is not installed" >&2; exit 1; }
    meta=$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync("{{uuid}}/metadata.json","utf8")).uuid)')
    [ "$meta" = "{{uuid}}" ] || { echo "error: metadata.json uuid ($meta) does not match the justfile ({{uuid}})" >&2; exit 1; }
    target="{{extdir}}/{{uuid}}"
    mkdir -p "{{extdir}}"
    rm -rf -- "$target"
    unzip -q "dist/{{uuid}}.shell-extension.zip" -d "$target"
    echo "Installed to $target"
    echo "On Wayland, log out and in first, then run: just enable"

# Enable the extension (it must be known to the Shell, which needs a log out and in after the first install).
enable:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! gnome-extensions info "{{uuid}}" >/dev/null 2>&1; then
        echo "The Shell does not know {{uuid}} yet: log out and in first." >&2
        exit 1
    fi
    gnome-extensions enable "{{uuid}}"

# Disable (if known) and remove this uuid's directory.
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${SKIP_GNOME_EXTENSIONS:-}" ] && command -v gnome-extensions >/dev/null && gnome-extensions info "{{uuid}}" >/dev/null 2>&1; then
        gnome-extensions disable "{{uuid}}" || true
    fi
    rm -rf -- "{{extdir}}/{{uuid}}"
    echo "Removed {{extdir}}/{{uuid}}. Undo with: just install"

status:
    #!/usr/bin/env bash
    gnome-extensions info "{{uuid}}" || echo "not known to the Shell"
    if [ -d "{{extdir}}/{{uuid}}" ]; then echo "directory: {{extdir}}/{{uuid}} (exists)"; else echo "directory: {{extdir}}/{{uuid}} (missing)"; fi

# Install into a temp directory and uninstall again (no gnome-extensions enable/disable, real home untouched).
test: lint
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    export GNOME_EXTENSIONS_DIR="$tmp" SKIP_GNOME_EXTENSIONS=1
    just install
    for f in metadata.json extension.js; do
        [ -f "$tmp/{{uuid}}/$f" ] || { echo "FAIL: $f missing after install" >&2; exit 1; }
    done
    just install   # reinstall replaces the old copy
    just uninstall
    [ ! -e "$tmp/{{uuid}}" ] || { echo "FAIL: directory still there after uninstall" >&2; exit 1; }
    echo "install/uninstall test OK"
