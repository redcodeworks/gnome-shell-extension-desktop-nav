#!/usr/bin/env bash
# Write manifest.json for a packed extension zip: what the promote workflow later
# verifies. "version-name" is the ZIP's (a testing zip is stamped <target>.rc<N>);
# "target-version-name" is the clean one from the tree.
# Usage: make-manifest.sh EXT_DIR ZIP OUT_JSON  (run inside the git checkout)
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: $0 EXT_DIR ZIP OUT_JSON" >&2; exit 2; }
ext=$1 zip=$2 out=$3
[ -f "$ext/metadata.json" ] || { echo "error: $ext/metadata.json missing" >&2; exit 1; }
[ -f "$zip" ] || { echo "error: $zip missing" >&2; exit 1; }
sum=$(sha256sum "$zip" | cut -d' ' -f1)
zipver=$(unzip -p "$zip" metadata.json | jq -r '.["version-name"] // empty')
commit=$(git rev-parse HEAD)
tree=$(git rev-parse 'HEAD^{tree}')
jq -n --slurpfile m "$ext/metadata.json" \
    --arg commit "$commit" --arg tree "$tree" \
    --arg zip "$(basename "$zip")" --arg sum "$sum" --arg zipver "$zipver" '
  $m[0] as $meta
  | {uuid: $meta.uuid,
     "version-name": ($zipver | if . == "" then null else . end),
     "target-version-name": ($meta["version-name"] // null),
     commit: $commit, tree: $tree,
     zip: $zip, zip_sha256: $sum,
     "shell-version": $meta["shell-version"]}' > "$out"
echo "wrote $out"
