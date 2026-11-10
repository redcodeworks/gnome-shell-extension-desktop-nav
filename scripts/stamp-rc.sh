#!/usr/bin/env bash
# Stamp a packed testing zip with its release-candidate number: version-name becomes
# <target>-rc<N> (hyphen form, for example 0.6.0-rc3) inside the ZIP's metadata.json only.
# The checked-in metadata.json is never touched (the target version stays clean), and no
# other field changes (the integer `version`, if there ever is one, stays as it is).
# N comes from scripts/rc-number.sh.
#
# Usage: stamp-rc.sh EXT_DIR ZIP   (run inside the git checkout)
# Writes rc=, target= and version= to $GITHUB_OUTPUT when set. A stamped zip is for testing
# only: the EGO pre-flight rejects the hyphen, and promote.sh releases a clean repack.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 EXT_DIR ZIP" >&2; exit 2; }
ext=$1 zip=$2
here=$(cd "$(dirname "$0")" && pwd)
[ -f "$ext/metadata.json" ] && [ -f "$zip" ] || { echo "error: $ext/metadata.json or $zip missing" >&2; exit 1; }
target=$(jq -r '.["version-name"] // empty' "$ext/metadata.json")
[[ $target =~ ^[0-9A-Za-z.]{1,16}$ ]] || { echo "error: version-name '$target' in the tree must be a clean version" >&2; exit 1; }
n=$("$here/rc-number.sh")
stamped="$target-rc$n"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
unzip -p "$zip" metadata.json | jq --arg v "$stamped" '.["version-name"] = $v' > "$tmp/metadata.json"
zipabs=$(cd "$(dirname "$zip")" && pwd)/$(basename "$zip")
( cd "$tmp" && zip -q -X "$zipabs" metadata.json )
[ "$(unzip -p "$zip" metadata.json | jq -r '.["version-name"]')" = "$stamped" ] || { echo "error: stamp did not land in $zip" >&2; exit 1; }
echo "stamped $zip: version-name $stamped (rc $n of target $target)"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    { echo "rc=$n"; echo "target=$target"; echo "version=$stamped"; } >> "$GITHUB_OUTPUT"
fi
