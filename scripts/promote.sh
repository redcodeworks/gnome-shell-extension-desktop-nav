#!/usr/bin/env bash
# Promote the tested build of the new main commit to a release candidate.
#
# Finds the successful `ci` run on `testing` whose commit has the same TREE as
# the checked-out main commit (equal for merge, squash and rebase merges),
# downloads its artifact and verifies it. It never builds anything. It publishes
# nothing itself: it writes outputs for the workflow's attest and release steps.
#
# Environment: REPO (owner/name), EXT_DIR (extension directory in the checkout),
# WORKDIR (where the artifact goes), GITHUB_OUTPUT (optional), GH (gh command, for tests).
# Exit: 0 = ready to release, or tag already exists (release=false); 1 = failure, publish nothing.
set -uo pipefail

repo=${REPO:?REPO is not set}
ext=${EXT_DIR:?EXT_DIR is not set}
work=${WORKDIR:?WORKDIR is not set}
gh=${GH:-gh}
out=${GITHUB_OUTPUT:-/dev/null}

fail() { echo "::error::promote: $*" >&2; exit 1; }
emit() { echo "$1=$2" >> "$out"; }

tree=$(git rev-parse 'HEAD^{tree}') || fail "cannot read the tree of HEAD"
commit=$(git rev-parse HEAD)
meta="$ext/metadata.json"
[ -f "$meta" ] || fail "$meta missing"
version=$(jq -r '.["version-name"] // empty' "$meta")
uuid=$(jq -r '.uuid // empty' "$meta")
[ -n "$version" ] || fail "metadata.json has no version-name (bump it by hand, for example 0.1.0)"
[[ $version =~ ^[0-9A-Za-z.]{1,16}$ ]] || fail "version-name '$version' must be 1-16 characters of letters, numbers and periods (no spaces or hyphens)"
[ -n "$uuid" ] || fail "metadata.json has no uuid"
tag="v$version"
echo "main commit $commit, tree $tree, version-name $version, tag $tag"

# 1. Tag already released: green notice, publish nothing.
rc=0; res=$("$gh" api "repos/$repo/git/ref/tags/$tag" 2>&1) || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "::notice::version $version already released ($tag exists); bump version-name to release"
    emit release false
    exit 0
elif ! grep -q '404' <<<"$res"; then
    fail "cannot check whether tag $tag exists: $res"
fi

# 2. The tested build of this tree.
name="extension-$tree"
arts=$("$gh" api "repos/$repo/actions/artifacts?name=$name&per_page=100") || fail "cannot list artifacts"
mapfile -t runs < <(jq -r --arg n "$name" '.artifacts[]
    | select(.name == $n and .expired == false and .workflow_run.head_branch == "testing")
    | .workflow_run.id' <<<"$arts")
[ ${#runs[@]} -gt 0 ] || fail "no tested build of tree $tree on testing (no unexpired artifact $name); nothing published. Push this content to testing and let CI pass first; the build is never redone here"

run=
for r in "${runs[@]}"; do
    concl=$("$gh" api "repos/$repo/actions/runs/$r" --jq .conclusion) || fail "cannot read run $r"
    if [ "$concl" = success ]; then run=$r; break; fi
    echo "run $r concluded '$concl', skipping"
done
[ -n "$run" ] || fail "artifact $name exists but none of its runs (${runs[*]}) succeeded; nothing published"
echo "using run $run"

# 3. Download and verify.
mkdir -p "$work"
"$gh" run download "$run" -R "$repo" -n "$name" -D "$work" || fail "cannot download artifact $name of run $run"
man="$work/manifest.json"
[ -f "$man" ] || fail "manifest.json missing in the artifact"
zipname=$(jq -r .zip "$man")
[[ $zipname =~ ^[A-Za-z0-9@._-]+\.zip$ ]] || fail "unexpected zip name in manifest: $zipname"
zip="$work/$zipname"
[ -f "$zip" ] || fail "$zipname missing in the artifact"

want=$(jq -r .zip_sha256 "$man")
have=$(sha256sum "$zip" | cut -d' ' -f1)
[ "$want" = "$have" ] || fail "zip sha256 $have does not match the manifest ($want)"
[ "$(jq -r .tree "$man")" = "$tree" ] || fail "manifest tree $(jq -r .tree "$man") differs from main tree $tree"
[ "$(jq -r .uuid "$man")" = "$uuid" ] || fail "manifest uuid differs from the tree's metadata.json"
zmeta=$(unzip -p "$zip" metadata.json) || fail "no metadata.json inside the zip"
[ "$(jq -r .uuid <<<"$zmeta")" = "$uuid" ] || fail "uuid inside the zip differs from the tree"
[ "$(jq -r '.["version-name"]' <<<"$zmeta")" = "$version" ] || fail "version-name inside the zip differs from the tree"
echo "verified: zip sha256 $have, uuid $uuid, version-name $version"

echo "$have  $zipname" > "$work/$zipname.sha256"
emit release true
emit tag "$tag"
emit version "$version"
emit zip "$zip"
emit sha256file "$zip.sha256"
emit sha256 "$have"
emit run "$run"
emit tree "$tree"
