set shell := ["bash", "-euo", "pipefail", "-c"]

# One source of truth for the uuid; `install` refuses to run if metadata.json disagrees.
uuid := "desktop-mouse-nav@redcodeworks.github.io"
extdir := env_var_or_default("GNOME_EXTENSIONS_DIR", env_var("HOME") + "/.local/share/gnome-shell/extensions")

default:
    @just --list

# Check metadata.json is valid JSON and extension.js parses (as an ES module).
[group('development')]
lint:
    node -e 'JSON.parse(require("fs").readFileSync("{{uuid}}/metadata.json","utf8"))'
    d=$(mktemp -d) && cp {{uuid}}/extension.js "$d/extension.mjs" && node --check "$d/extension.mjs"; rc=$?; rm -rf "$d"; exit $rc

# Build the installable zip into dist/ (creates the directory first).
[group('development')]
pack:
    mkdir -p dist
    gnome-extensions pack --force --out-dir dist {{uuid}}

# Build the zip and unpack it into the extensions directory (replaces this uuid only).
[group('extension')]
install: pack
    scripts/install-zip.sh "dist/{{uuid}}.shell-extension.zip" "{{extdir}}" "{{uuid}}"

# Install a released zip (latest or a version), checksum verified; --dry-run installs nothing.
[group('extension')]
[positional-arguments]
install-release *args:
    #!/usr/bin/env bash
    set -uo pipefail
    export UUID="{{uuid}}" GNOME_EXTENSIONS_DIR="{{extdir}}"
    exec scripts/install-release.sh "$@"

# Enable the extension (log out and in once after the first install).
[group('extension')]
enable:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! gnome-extensions info "{{uuid}}" >/dev/null 2>&1; then
        echo "The Shell does not know {{uuid}} yet: log out and in first." >&2
        exit 1
    fi
    gnome-extensions enable "{{uuid}}"

# Disable (if known) and remove this uuid's directory.
[group('extension')]
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${SKIP_GNOME_EXTENSIONS:-}" ] && command -v gnome-extensions >/dev/null && gnome-extensions info "{{uuid}}" >/dev/null 2>&1; then
        gnome-extensions disable "{{uuid}}" || true
    fi
    rm -rf -- "{{extdir}}/{{uuid}}"
    echo "Removed {{extdir}}/{{uuid}}. Undo with: just install"
# Show what the Shell knows and whether the extension directory exists.
[group('extension')]
status:
    #!/usr/bin/env bash
    gnome-extensions info "{{uuid}}" || echo "not known to the Shell"
    if [ -d "{{extdir}}/{{uuid}}" ]; then echo "directory: {{extdir}}/{{uuid}} (exists)"; else echo "directory: {{extdir}}/{{uuid}} (missing)"; fi

# Lint, temp-dir install and uninstall, and the script tests (real home untouched).
[group('development')]
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
    rc=0
    for t in tests/test-*.sh; do
        echo "== $t"
        bash "$t" || rc=1
    done
    exit $rc
