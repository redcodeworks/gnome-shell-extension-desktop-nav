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
[ -f "$tmp/work/release/$uuid.shell-extension.zip.sha256" ] && pass ".sha256 file written" || fail ".sha256 file"
( cd "$tmp/work/release" && sha256sum -c "$uuid.shell-extension.zip.sha256" >/dev/null ) && pass ".sha256 file verifies" || fail ".sha256 verify"

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

# release candidates: the tested zip is stamped <version>.rc<N> (scripts/stamp-rc.sh), the release is a clean repack
crc() { unzip -v "$1" | awk 'NF >= 8 && $1 ~ /^[0-9]+$/ && $NF != "metadata.json" {print $1, $7, $NF}' | sort; }
rcrepo=$tmp/rcrepo; mk_repo "$rcrepo" 0.6.0
jq '. + {version: 7}' "$rcrepo/$uuid/metadata.json" > "$rcrepo/m" && mv "$rcrepo/m" "$rcrepo/$uuid/metadata.json"
( cd "$rcrepo" && git -c user.name=t -c user.email=t@t commit -q -am "integer version" )
rctree=$(git -C "$rcrepo" rev-parse 'HEAD^{tree}')
rcart=$tmp/rcart; mk_artifact "$rcrepo" "$rcart"
( cd "$rcrepo" && "$root/scripts/stamp-rc.sh" "$uuid" "$rcart/$uuid.shell-extension.zip" >/dev/null && "$root/scripts/make-manifest.sh" "$uuid" "$rcart/$uuid.shell-extension.zip" "$rcart/manifest.json" >/dev/null )
[ "$(unzip -p "$rcart/$uuid.shell-extension.zip" metadata.json | jq -r '.["version-name"]')" = "0.6.0.rc2" ] && pass "rc fixture: tested zip is stamped (2 commits, no tag)" || fail "rc fixture stamped"
export STUB_ARTIFACT_DIR=$rcart
reset; arts "$rctree" testing 43
expect_rc 0 "stamped testing zip is promoted" run_promote "$rcrepo"
rz=$tmp/work/release/$uuid.shell-extension.zip
[ "$(unzip -p "$rz" metadata.json | jq -r '.["version-name"]')" = "0.6.0" ] && pass "release zip carries the clean version-name" || fail "release zip version-name"
[ "$(unzip -p "$rz" metadata.json | sha256sum)" = "$(sha256sum < "$rcrepo/$uuid/metadata.json")" ] && pass "release metadata.json is byte-identical to the tree's" || fail "release metadata.json vs tree"
[ "$(unzip -p "$rz" metadata.json | jq -r .version)" = 7 ] && pass "integer version untouched" || fail "integer version"
[ "$(crc "$rz")" = "$(crc "$rcart/$uuid.shell-extension.zip")" ] && [ -n "$(crc "$rz")" ] && pass "release zip entries equal the tested zip's (except metadata.json)" || fail "repack changed other entries"
[ "$(unzip -p "$rcart/$uuid.shell-extension.zip" metadata.json | jq -r '.["version-name"]')" = "0.6.0.rc2" ] && pass "tested zip itself is left alone" || fail "tested zip modified"
( cd "$tmp/work/release" && sha256sum -c "$uuid.shell-extension.zip.sha256" >/dev/null ) && pass "release .sha256 covers the repacked zip" || fail "release sha256"
grep -q "^zip=$rz\$" "$tmp/gho" && pass "zip output is the release zip" || fail "zip output"
grep -q '^tested_version=0.6.0.rc2' "$tmp/gho" && pass "tested version output" || fail "tested_version output"

# a stamped zip whose metadata differs from the tree beyond version-name is refused
tam=$tmp/tam; cp -r "$rcart" "$tam"; t2=$tmp/t2; mkdir "$t2"
unzip -p "$tam/$uuid.shell-extension.zip" metadata.json | jq '.description = "tampered"' > "$t2/metadata.json"
( cd "$t2" && zip -q -X "$tam/$uuid.shell-extension.zip" metadata.json )
jq --arg s "$(sha256sum "$tam/$uuid.shell-extension.zip" | cut -d' ' -f1)" '.zip_sha256 = $s' "$tam/manifest.json" > "$tam/m" && mv "$tam/m" "$tam/manifest.json"
reset; arts "$rctree" testing 43; STUB_ARTIFACT_DIR=$tam expect_rc 1 "zip metadata that differs beyond version-name is refused" run_promote "$rcrepo"
expect_out 'beyond version-name' "beyond version-name: message"

# the old hyphen rc form is no longer accepted in the tested zip
oh=$tmp/oh; cp -r "$rcart" "$oh"
unzip -p "$oh/$uuid.shell-extension.zip" metadata.json | jq '.["version-name"] = "0.6.0-rc2"' > "$t2/metadata.json"
( cd "$t2" && zip -q -X "$oh/$uuid.shell-extension.zip" metadata.json )
jq --arg s "$(sha256sum "$oh/$uuid.shell-extension.zip" | cut -d' ' -f1)" '.zip_sha256 = $s' "$oh/manifest.json" > "$oh/m" && mv "$oh/m" "$oh/manifest.json"
reset; arts "$rctree" testing 43; STUB_ARTIFACT_DIR=$oh expect_rc 1 "the old hyphen rc form (0.6.0-rc2) in the zip is refused" run_promote "$rcrepo"
# a tree whose own version-name looks like an rc is never released
rr=$tmp/rr; mk_repo "$rr" 0.6.0.rc2
reset; arts x testing 1; expect_rc 1 "a tree version-name ending in .rc<N> is refused" run_promote "$rr"; expect_out 'release candidate' "rc tree message"

# a version-name that is not <version> or <version>.rc<N> is refused
odd=$tmp/odd; cp -r "$rcart" "$odd"
unzip -p "$odd/$uuid.shell-extension.zip" metadata.json | jq '.["version-name"] = "0.6.0-beta"' > "$t2/metadata.json"
( cd "$t2" && zip -q -X "$odd/$uuid.shell-extension.zip" metadata.json )
jq --arg s "$(sha256sum "$odd/$uuid.shell-extension.zip" | cut -d' ' -f1)" '.zip_sha256 = $s' "$odd/manifest.json" > "$odd/m" && mv "$odd/m" "$odd/manifest.json"
reset; arts "$rctree" testing 43; STUB_ARTIFACT_DIR=$odd expect_rc 1 "version-name 0.6.0-beta in the zip is refused" run_promote "$rcrepo"
export STUB_ARTIFACT_DIR=$art

# squash/rebase merge: another commit with the same tree still matches
( cd "$repo" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "second commit, same tree" )
reset; arts "$tree" testing 42
expect_rc 0 "same tree under a new commit (squash/rebase merge) matches" run_promote "$repo"
finish
