#!/usr/bin/env bash
# Unpack an extension zip into the extensions directory, replacing the previous
# copy of that uuid only. Shared by `just install` and `just install-release`.
# Usage: install-zip.sh ZIP EXTDIR UUID
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: $0 ZIP EXTDIR UUID" >&2; exit 2; }
zip=$1 extdir=$2 uuid=$3
command -v unzip >/dev/null || { echo "error: unzip is not installed" >&2; exit 1; }
[ -f "$zip" ] || { echo "error: $zip not found" >&2; exit 1; }
if unzip -Z1 "$zip" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
    echo "error: $zip has absolute or parent-relative paths, refusing" >&2; exit 1
fi
zuuid=$(unzip -p "$zip" metadata.json | jq -r .uuid)
[ "$zuuid" = "$uuid" ] || { echo "error: the zip's metadata.json uuid ($zuuid) does not match $uuid" >&2; exit 1; }
target="$extdir/$uuid"
mkdir -p "$extdir"
# Unpack next to the target (same filesystem), then swap: a failed unzip keeps the old copy.
stage=$(mktemp -d "$extdir/.${uuid}.new.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
unzip -q "$zip" -d "$stage"
# The zip ships the schema XML only: EGO and `gnome-extensions install` compile it, this unpack route must.
if compgen -G "$stage/schemas/*.gschema.xml" >/dev/null; then
    command -v glib-compile-schemas >/dev/null || {
        echo "error: glib-compile-schemas is not installed (Fedora: glib2-devel); kept the existing copy" >&2; exit 1; }
    glib-compile-schemas --strict "$stage/schemas"
fi
rm -rf -- "$target"
mv -- "$stage" "$target"
trap - EXIT
echo "Installed to $target"
echo "On Wayland, log out and in first, then run: just enable"
