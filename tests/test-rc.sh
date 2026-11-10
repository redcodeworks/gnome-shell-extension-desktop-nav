#!/usr/bin/env bash
# Release-candidate numbers: scripts/rc-number.sh on fixture repos shaped like this repo's
# history (release tags sit on merge commits of main that testing does not contain), and
# scripts/stamp-rc.sh on a zip.
. "$(dirname "$0")/lib.sh"
command -v zip >/dev/null || { echo "zip is required for this test" >&2; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

r=$tmp/repo
git init -q -b testing "$r"
mkdir -p "$r/$uuid"
meta() { printf '{"name":"x","description":"x","uuid":"%s","shell-version":["51"],"version-name":"%s","version":7}\n' "$uuid" "$1" > "$r/$uuid/metadata.json"; }
g() { git -C "$r" "$@"; }
n=0
merge() { # one squash merge into testing: a new commit with a different tree
    n=$((n+1)); echo "change $n" > "$r/$uuid/extension.js"; g add -A; g commit -q -m "change $n (#$n)"
}
release() { # TAG : promote testing's tip to main as a merge commit and tag it (testing does not get it back)
    local tip; tip=$(g rev-parse refs/heads/testing)
    if g rev-parse -q --verify refs/heads/main >/dev/null; then
        g checkout -q main; g merge -q --no-ff -m "promote $1" refs/heads/testing; g tag "$1"; g checkout -q testing
    else
        g checkout -q -b main "$tip"; g commit -q --allow-empty -m "root of main"; g checkout -q testing
        g checkout -q main; g merge -q --no-ff -m "promote $1" refs/heads/testing; g tag "$1"; g checkout -q testing
    fi
}
rc() { ( cd "$r" && "$root/scripts/rc-number.sh" "$@" ); }
expect_n() { # WANT NAME [REF]
    local got; got=$(rc "${@:3}"); [ "$got" = "$1" ] && pass "$2 (rc$1)" || fail "$2 (got $got, wanted $1)"
}

meta 0.1.0; n=0; merge
expect_n 1 "no tags, one commit"
merge; merge
expect_n 3 "no tags, three commits"
release v0.1.0
expect_n 1 "right after a release: 0 commits since, floor 1"
merge
expect_n 1 "one merge after the release"
merge; merge
expect_n 3 "three merges after the release"
g tag testing   # the rolling prerelease tag must be ignored
git -C "$r" tag -l | grep -q '^testing$' && expect_n 3 "the rolling testing tag is ignored"
release v0.2.0
expect_n 1 "a second release resets the count"
merge
expect_n 1 "first merge after the second release"
merge
expect_n 2 "second merge after the second release"
# a tag on the PR-style merge commit of main whose tree appears on testing earlier in history still resets there
expect_n 2 "explicit HEAD gives the same answer" HEAD
expect_n 1 "REF one commit back" HEAD~1

# stamp
meta 0.2.1; g add -A; g commit -q -m "bump (#x)"
ext=$r/$uuid
mkdir -p "$tmp/pk"; cp "$ext"/* "$tmp/pk/"; echo "// x" > "$tmp/pk/actions.js"; make_zip "$tmp/pk" "$tmp/z.zip"
clean_before=$(sha256sum "$ext/metadata.json" | cut -d' ' -f1)
( cd "$r" && GITHUB_OUTPUT=$tmp/o "$root/scripts/stamp-rc.sh" "$uuid" "$tmp/z.zip" ) > "$tmp/last.out" 2>&1 && pass "stamp runs" || { fail "stamp runs"; cat "$tmp/last.out" >&2; }
want=$(rc); want="0.2.1-rc$want"
zm=$(unzip -p "$tmp/z.zip" metadata.json)
[ "$(jq -r '.["version-name"]' <<<"$zm")" = "$want" ] && pass "zip version-name is $want" || fail "zip version-name"
[ "$(jq -r .version <<<"$zm")" = 7 ] && pass "integer version field unchanged" || fail "integer version changed"
[ "$(jq -S 'del(.["version-name"])' <<<"$zm")" = "$(jq -S 'del(.["version-name"])' "$ext/metadata.json")" ] && pass "only version-name differs from the tree's metadata.json" || fail "other metadata fields changed"
[ "$(sha256sum "$ext/metadata.json" | cut -d' ' -f1)" = "$clean_before" ] && [ "$(jq -r '.["version-name"]' "$ext/metadata.json")" = 0.2.1 ] && pass "checked-in metadata.json stays clean" || fail "checked-in metadata.json changed"
[ "$(unzip -p "$tmp/z.zip" extension.js)" = "$(cat "$ext/extension.js")" ] && [ "$(unzip -Z1 "$tmp/z.zip" | sort | tr '\n' ' ')" = "actions.js extension.js metadata.json " ] && pass "other zip entries untouched" || fail "other zip entries changed"
grep -qx "rc=$(rc)" "$tmp/o" && grep -qx "target=0.2.1" "$tmp/o" && grep -qx "version=$want" "$tmp/o" && pass "outputs rc, target, version" || fail "stamp outputs"
# the manifest records both names
( cd "$r" && "$root/scripts/make-manifest.sh" "$uuid" "$tmp/z.zip" "$tmp/man.json" >/dev/null )
[ "$(jq -r '.["version-name"]' "$tmp/man.json")" = "$want" ] && [ "$(jq -r '.["target-version-name"]' "$tmp/man.json")" = 0.2.1 ] && pass "manifest: zip version-name and target" || fail "manifest names"
# a dirty version in the tree is refused
meta "1.0-beta"; expect_rc 1 "stamp refuses a version-name that is not clean" bash -c "cd '$r' && '$root/scripts/stamp-rc.sh' '$uuid' '$tmp/z.zip'"
# the EGO pre-flight must keep rejecting a stamped zip (it never goes to EGO)
rm -rf "$tmp/pf"; mkdir "$tmp/pf"; cp -r "$root/$uuid/." "$tmp/pf/"; make_zip "$tmp/pf" "$tmp/pfz.zip"
( cd "$root" && "$root/scripts/stamp-rc.sh" "$uuid" "$tmp/pfz.zip" >/dev/null )
expect_rc 1 "pre-flight rejects a stamped (-rc) zip" "$root/scripts/ego-preflight.sh" "$tmp/pfz.zip" --repo-url https://github.com/redcodeworks/gnome-shell-extension-desktop-nav --license-dir "$root"
expect_out 'version-name must be' "pre-flight: version-name message"
finish
