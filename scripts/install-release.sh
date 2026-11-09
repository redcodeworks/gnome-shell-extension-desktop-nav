#!/usr/bin/env bash
# Install a released zip (default: the latest release) into the extensions directory.
# Usage: install-release.sh [VERSION|latest] [--dry-run] [help]
# Environment: UUID (required), GNOME_EXTENSIONS_DIR, RELEASE_REPO, GH (the gh command, for tests).
set -uo pipefail

repo=${RELEASE_REPO:-redcodeworks/gnome-shell-extension-desktop-nav}
gh=${GH:-gh}
uuid=${UUID:?UUID is not set}
extdir=${GNOME_EXTENSIONS_DIR:-$HOME/.local/share/gnome-shell/extensions}
here=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<USAGE
Usage: just install-release [VERSION] [--dry-run]

Downloads the latest release (or v<VERSION>, for example 0.1.0) of $repo,
verifies its .sha256 file and unpacks it into
  $extdir/$uuid
Same result as 'just install', without building anything.

  --dry-run   download and verify into a temp directory, install nothing
  help        this text
Undo: just uninstall.   Needs: gh (logged in or the repo is public), unzip, jq.
USAGE
}

version=latest dry=0
for a in "$@"; do
    case $a in
        help|--help|-h) usage; exit 0 ;;
        --dry-run) dry=1 ;;
        -*) echo "error: unknown option $a" >&2; usage >&2; exit 1 ;;
        *) version=$a ;;
    esac
done
if [ "$version" != latest ] && ! [[ $version =~ ^v?[0-9A-Za-z.]+$ ]]; then
    echo "error: bad version '$version'" >&2; exit 1
fi
tag=
[ "$version" = latest ] || tag=v${version#v}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

ok=0
for attempt in 1 2 3; do
    if "$gh" release download ${tag:+"$tag"} -R "$repo" -p '*.zip' -p '*.sha256' -D "$tmp" --clobber; then ok=1; break; fi
    echo "download failed (attempt $attempt of 3)" >&2; sleep 3
done
[ "$ok" = 1 ] || { echo "error: could not download the release of $repo (${tag:-latest}); re-run: just install-release ${version#latest}" >&2; exit 1; }

shopt -s nullglob
zips=("$tmp"/*.zip) sums=("$tmp"/*.sha256)
[ ${#zips[@]} -eq 1 ] && [ ${#sums[@]} -eq 1 ] || { echo "error: expected exactly one .zip and one .sha256 in the release" >&2; exit 1; }
zip=${zips[0]}
( cd "$tmp" && sha256sum -c "$(basename "${sums[0]}")" ) || { echo "error: checksum mismatch, nothing installed" >&2; exit 1; }

new=$(unzip -p "$zip" metadata.json | jq -r '.["version-name"] // "?"')
cur=
[ -f "$extdir/$uuid/metadata.json" ] && cur=$(jq -r '.["version-name"] // "?"' "$extdir/$uuid/metadata.json")

if [ "$dry" = 1 ]; then
    echo "dry run: release ${tag:-latest} verified (version-name $new, ${cur:+installed: $cur, }would unpack to $extdir/$uuid); nothing installed"
    exit 0
fi
if [ "$cur" = "$new" ]; then
    echo "already installed: version $new in $extdir/$uuid (nothing to do)"
    exit 0
fi
"$here/install-zip.sh" "$zip" "$extdir" "$uuid" || exit 1
echo "Installed release version $new (undo: just uninstall)"
