#!/usr/bin/env bash
# Release-candidate number of a testing build: how many first-parent commits (squash merges
# into `testing`) lie between the last release and REF, with a floor of 1. Prints the number.
#
# "The last release" is found by TREE, not by ancestry: a release tag sits on a merge commit
# of `main` that `testing` does not contain, but the tested tip of `testing` has the same
# tree. So walk REF's first-parent history newest first and stop at the first commit whose
# tree equals the tree of any `v<digits>...` tag; the commits walked past are N. No such
# tag in the history: every commit counts. Right after a promotion the walk stops at REF
# itself (0 commits), which the floor turns into 1.
#
# Usage: rc-number.sh [REF]   (default HEAD; run inside the git checkout, tags fetched)
set -euo pipefail
ref=${1:-HEAD}
declare -A released=()
while IFS= read -r t; do
    [ -n "$t" ] || continue
    released[$(git rev-parse "$t^{tree}")]=$t
done < <(git tag -l 'v[0-9]*')
n=0
while IFS= read -r tree; do
    [ -z "${released[$tree]:-}" ] || break
    n=$((n+1))
done < <(git log --first-parent --format=%T "$ref" --)
[ "$n" -ge 1 ] || n=1
echo "$n"
