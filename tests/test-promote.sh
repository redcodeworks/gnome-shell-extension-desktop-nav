#!/usr/bin/env bash
# Logic of scripts/promote.sh against a temp git repo and a stub gh.
. "$(dirname "$0")/lib.sh"
command -v zip >/dev/null || { echo "zip is required for this test" >&2; exit 1; }

mk_repo() { # DIR VERSION : a repo with the extension, committed
    local d=$1 v=$2
    mkdir -p "$d/$uuid"; git init -q "$d"
    cat > "$d/$uuid/metadata.json" <<JSON
{"name":"x","description":"x","uuid":"$uuid","shell-version":["51"],"version-name":"$v","url":"https://example.invalid"}
JSON
    echo "// ext" > "$d/$uuid/extension.js"
    ( cd "$d" && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init )
}
mk_artifact() { # REPO ARTDIR : zip + manifest from the repo's tree
    mkdir -p "$2"; make_zip "$1/$uuid" "$2/$uuid.shell-extension.zip"
    ( cd "$1" && "$root/scripts/make-manifest.sh" "$uuid" "$2/$uuid.shell-extension.zip" "$2/manifest.json" >/dev/null )
}
export STUB_LOG=$tmp/log
export PATH="$root/tests/stubs:$PATH"
run_promote() { # REPO
    ( cd "$1" && GH=$root/tests/stubs/gh REPO=o/r EXT_DIR=$uuid WORKDIR=$tmp/work GITHUB_OUTPUT=$tmp/gho \
        "$root/scripts/promote.sh" )
}
arts() { # TREE BRANCH RUNID
    jq -n --arg n "extension-$1" --arg b "$2" --argjson id "$3" \
      '{artifacts:[{name:$n,expired:false,workflow_run:{id:$id,head_branch:$b}}]}' > "$tmp/arts.json"
    export STUB_ARTIFACTS=$tmp/arts.json
}
reset() { rm -rf "$tmp/work" "$tmp/gho"; : > "$tmp/log"; unset STUB_TAG_EXISTS STUB_TAG_ERROR STUB_CONCLUSION; }

repo=$tmp/repo; mk_repo "$repo" 0.1.0
tree=$(git -C "$repo" rev-parse 'HEAD^{tree}')
art=$tmp/art; mk_artifact "$repo" "$art"; export STUB_ARTIFACT_DIR=$art

reset; arts "$tree" testing 42
expect_rc 0 "matching tested build is promoted" run_promote "$repo"
grep -q '^release=true' "$tmp/gho" && pass "release=true output" || fail "release=true output"
grep -q '^tag=v0.1.0' "$tmp/gho" && pass "tag derived from version-name" || fail "tag output"
[ -f "$tmp/work/$uuid.shell-extension.zip.sha256" ] && pass ".sha256 file written" || fail ".sha256 file"
( cd "$tmp/work" && sha256sum -c "$uuid.shell-extension.zip.sha256" >/dev/null ) && pass ".sha256 file verifies" || fail ".sha256 verify"

reset; arts "$tree" testing 42; export STUB_TAG_EXISTS=1
expect_rc 0 "tag exists: green notice" run_promote "$repo"
expect_out 'already released' "tag exists: notice text"
grep -q '^release=false' "$tmp/gho" && pass "tag exists: release=false" || fail "release=false output"
grep -q 'run download' "$tmp/log" && fail "tag exists: must not download" || pass "tag exists: nothing downloaded"

reset; arts "$tree" testing 42; export STUB_TAG_ERROR=1
expect_rc 1 "tag check error (not 404) fails" run_promote "$repo"

reset; arts "0000000000000000000000000000000000000000" testing 42
expect_rc 1 "no matching tested build fails loudly" run_promote "$repo"
expect_out 'no tested build' "no build: message"
grep -q '^release=true' "$tmp/gho" 2>/dev/null && fail "no build: must not release" || pass "no build: nothing released"

reset; arts "$tree" feature 42
expect_rc 1 "artifact from another branch is ignored" run_promote "$repo"

reset; arts "$tree" testing 42; export STUB_CONCLUSION=failure
expect_rc 1 "run that did not succeed is rejected" run_promote "$repo"

# checksum mismatch: zip changed after the manifest was written
bad=$tmp/bad; cp -r "$art" "$bad"; echo tamper >> "$bad/$uuid.shell-extension.zip"
reset; arts "$tree" testing 42; STUB_ARTIFACT_DIR=$bad expect_rc 1 "checksum mismatch fails" run_promote "$repo"
expect_out 'does not match the manifest' "checksum mismatch: message"

# zip built from a different version than the tree says
other=$tmp/other; mk_repo "$other" 0.0.9
oart=$tmp/oart; mk_artifact "$other" "$oart"
jq --arg t "$tree" '.tree = $t' "$oart/manifest.json" > "$oart/m" && mv "$oart/m" "$oart/manifest.json"
reset; arts "$tree" testing 42; STUB_ARTIFACT_DIR=$oart expect_rc 1 "version-name inside the zip must match the tree" run_promote "$repo"

# manifest tree differs
mt=$tmp/mt; cp -r "$art" "$mt"; jq '.tree = "deadbeef"' "$mt/manifest.json" > "$mt/m" && mv "$mt/m" "$mt/manifest.json"
reset; arts "$tree" testing 42; STUB_ARTIFACT_DIR=$mt expect_rc 1 "manifest tree must equal the main tree" run_promote "$repo"

# version-name rules
bv=$tmp/bv; mk_repo "$bv" 1.0-beta
reset; arts x testing 1; expect_rc 1 "hyphen in version-name is rejected" run_promote "$bv"
nv=$tmp/nv; mk_repo "$nv" 0.1.0; jq 'del(.["version-name"])' "$nv/$uuid/metadata.json" > "$nv/m" && mv "$nv/m" "$nv/$uuid/metadata.json"
( cd "$nv" && git -c user.name=t -c user.email=t@t commit -q -am nov )
reset; arts x testing 1; expect_rc 1 "missing version-name is rejected" run_promote "$nv"

# squash/rebase merge: another commit with the same tree still matches
( cd "$repo" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "second commit, same tree" )
reset; arts "$tree" testing 42
expect_rc 0 "same tree under a new commit (squash/rebase merge) matches" run_promote "$repo"
finish
