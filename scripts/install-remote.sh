#!/usr/bin/env bash
# Install a published zip: the latest real release (default), a named release, or the rolling
# `testing` prerelease. Behind `just install`.
# Usage: install-remote.sh [VERSION] [--testing] [--dry-run] [help]
# Environment: UUID (required), GNOME_EXTENSIONS_DIR, RELEASE_REPO, GH (the gh command, for tests),
# RETRY_WAIT (seconds between download attempts, default 3).
set -uo pipefail

repo=${RELEASE_REPO:-redcodeworks/gnome-shell-extension-desktop-nav}
gh=${GH:-gh}
uuid=${UUID:?UUID is not set}
extdir=${GNOME_EXTENSIONS_DIR:-$HOME/.local/share/gnome-shell/extensions}
wait_s=${RETRY_WAIT:-3}
here=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<USAGE
Usage: just install [VERSION] [--testing] [--dry-run]

Downloads a build of $repo, verifies its .sha256 file and unpacks it into
  $extdir/$uuid

  (no argument)  the latest release (the newest one that is not a prerelease)
  VERSION        that release, for example 0.1.1 or v0.1.1
  --testing      the latest testing build (the rolling 'testing' prerelease);
                 cannot be combined with VERSION
  --dry-run      download and verify into a temp directory, install nothing
  help           this text

Other route: just install-local builds the working tree instead of downloading.
Undo: just uninstall.   Needs: gh (logged in, or the repo is public), unzip, jq.
USAGE
}

version= testing=0 dry=0
for a in "$@"; do
    case $a in
        help|--help|-h) usage; exit 0 ;;
        --dry-run) dry=1 ;;
        --testing) testing=1 ;;
        -*) echo "error: unknown option $a" >&2; usage >&2; exit 1 ;;
        *) [ -z "$version" ] || { echo "error: only one VERSION allowed" >&2; usage >&2; exit 1; }; version=$a ;;
    esac
done
if [ "$testing" = 1 ] && [ -n "$version" ]; then
    echo "error: --testing cannot be combined with a VERSION" >&2; usage >&2; exit 1
fi
if [ -n "$version" ] && ! [[ $version =~ ^v?[0-9A-Za-z.]+$ ]]; then
    echo "error: bad version '$version'" >&2; usage >&2; exit 1
fi
if [[ $version =~ \.rc[0-9]+$ ]]; then
    echo "error: $version is a testing build (release candidate), not a release; use: just install --testing" >&2; exit 1
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# retry CMD...: up to 3 attempts, output of the last one in $tmp/err
retry() {
    local i
    for i in 1 2 3; do
        if "$@" > "$tmp/out" 2> "$tmp/err"; then return 0; fi
        grep -qi 'not found' "$tmp/err" && return 2
        echo "attempt $i of 3 failed: $*" >&2; sleep "$wait_s"
    done
    return 1
}

if [ "$testing" = 1 ]; then
    tag=testing
elif [ -n "$version" ]; then
    tag=v${version#v}
else
    retry "$gh" release view -R "$repo" --json tagName --jq .tagName; rc=$?
    if [ $rc = 2 ]; then
        echo "There is no release of $repo yet." >&2
        echo "Try the latest testing build: just install --testing" >&2
        echo "or build the working tree:    just install-local" >&2
        exit 1
    fi
    [ $rc = 0 ] || { echo "error: could not look up the latest release of $repo; re-run: just install" >&2; cat "$tmp/err" >&2; exit 1; }
    tag=$(tr -d '[:space:]' < "$tmp/out")
    [ -n "$tag" ] || { echo "error: the latest release has no tag" >&2; exit 1; }
fi

retry "$gh" release download "$tag" -R "$repo" -p '*.zip' -p '*.sha256' -D "$tmp" --clobber; rc=$?
if [ $rc = 2 ]; then
    if [ "$tag" = testing ]; then
        echo "error: there is no testing build yet (it is published after a push to the testing branch passes CI)" >&2
    else
        echo "error: release $tag of $repo not found" >&2
    fi
    exit 1
fi
[ $rc = 0 ] || { echo "error: could not download $tag of $repo; re-run: just install ${version:+$version }${testing:+--testing}" >&2; exit 1; }

shopt -s nullglob
zips=("$tmp"/*.zip) sums=("$tmp"/*.sha256)
[ ${#zips[@]} -eq 1 ] && [ ${#sums[@]} -eq 1 ] || { echo "error: expected exactly one .zip and one .sha256 in $tag" >&2; exit 1; }
zip=${zips[0]}
( cd "$tmp" && sha256sum -c "$(basename "${sums[0]}")" >/dev/null ) || { echo "error: checksum mismatch, nothing installed" >&2; exit 1; }
sum=$(sha256sum "$zip" | cut -d' ' -f1)

new=$(unzip -p "$zip" metadata.json | jq -r '.["version-name"] // "?"')
cur= cursum=
[ -f "$extdir/$uuid/metadata.json" ] && cur=$(jq -r '.["version-name"] // "?"' "$extdir/$uuid/metadata.json")
[ -f "$extdir/.$uuid.zip-sha256" ] && cursum=$(cat "$extdir/.$uuid.zip-sha256")

if [ "$dry" = 1 ]; then
    echo "dry run: $tag verified (version-name $new, checksum ok, ${cur:+installed: $cur, }would unpack to $extdir/$uuid); nothing installed"
    exit 0
fi
if [ "$cur" = "$new" ] && [ "$cursum" = "$sum" ]; then
    echo "already installed: $tag, version $new, same zip in $extdir/$uuid (nothing to do)"
    exit 0
fi
"$here/install-zip.sh" "$zip" "$extdir" "$uuid" || exit 1
echo "Installed $tag, version $new (undo: just uninstall)"
