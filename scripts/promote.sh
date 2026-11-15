#!/usr/bin/env bash
# Promote the tested build of the new main commit to a release.
#
# Finds the successful `ci` run on `testing` whose commit has the same TREE as
# the checked-out main commit (equal for merge, squash and rebase merges),
# downloads its artifact and verifies it. It never builds anything. The tested zip of a
# testing build carries version-name <version>.rc<N> (scripts/stamp-rc.sh); the release must
# carry the clean <version>, so the script REPACKS: it copies the tested zip and replaces
# only its metadata.json with the one committed in this tree (checked first: the zip's
# metadata.json equals the tree's except for version-name, and every other zip entry is
# compared by CRC with the tested zip afterwards). It publishes nothing itself: it writes
# outputs for the workflow's attest and release steps.
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
[[ $version =~ \.rc[0-9]+$ ]] && fail "version-name '$version' looks like a release candidate (.rc<N> is only for testing builds)"
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
tested=$(jq -r '.["version-name"]' <<<"$zmeta")
[[ $tested == "$version" || $tested =~ ^"$version"\.rc[0-9]+$ ]] || fail "version-name inside the zip ($tested) is neither $version nor $version.rc<N>"
# the tested zip's metadata.json is the tree's with only version-name stamped
[ "$(jq -S 'del(.["version-name"])' <<<"$zmeta")" = "$(jq -S 'del(.["version-name"])' "$meta")" ] || fail "metadata.json inside the zip differs from the tree beyond version-name"
echo "verified: tested zip sha256 $have, uuid $uuid, tested version-name $tested, release version-name $version"

# 4. Repack for release: same entries, the tree's own metadata.json (clean version-name).
rel="$work/release"; mkdir -p "$rel"
relzip="$rel/$zipname"
cp "$zip" "$relzip"
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
cp "$meta" "$stage/metadata.json"
( cd "$stage" && zip -q -X "$relzip" metadata.json ) || fail "cannot repack the zip"
[ "$(unzip -p "$relzip" metadata.json | sha256sum)" = "$(sha256sum < "$meta")" ] || fail "repacked metadata.json differs from the tree's"
crcs() { unzip -v "$1" | awk 'NF >= 8 && $NF != "metadata.json" && $1 ~ /^[0-9]+$/ {print $1, $7, $NF}' | sort; }
[ "$(crcs "$zip")" = "$(crcs "$relzip")" ] && [ -n "$(crcs "$relzip")" ] || fail "repacked zip differs from the tested zip in entries other than metadata.json"
[ "$(unzip -Z1 "$zip" | sort)" = "$(unzip -Z1 "$relzip" | sort)" ] || fail "repacked zip lists different files than the tested zip"
rhave=$(sha256sum "$relzip" | cut -d' ' -f1)
echo "repacked: release zip sha256 $rhave (clean version-name $version; only metadata.json replaced)"

echo "$rhave  $zipname" > "$relzip.sha256"
emit release true
emit tag "$tag"
emit version "$version"
emit tested_version "$tested"
emit zip "$relzip"
emit sha256file "$relzip.sha256"
emit sha256 "$rhave"
emit tested_sha256 "$have"
emit run "$run"
emit tree "$tree"
