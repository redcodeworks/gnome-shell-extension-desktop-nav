#!/usr/bin/env bash
# Which release does the fedora-next workflow test? The current Latest release of this
# repository (`gh release view` without a tag skips prereleases, so the rolling `testing`
# prerelease is never picked, and a tag ending in .rc<N> is refused). No release yet is an error: the weekly run must say so
# clearly instead of testing nothing.
#
# Environment: GH (default gh), GH_REPO or the current repository (gh decides),
#   GITHUB_OUTPUT (tag=, version=), GITHUB_STEP_SUMMARY.
# Exit: 0 = found, 1 = no release or the lookup failed.
set -uo pipefail

gh=${GH:-gh}
out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >> "$GITHUB_OUTPUT"; return 0; }
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"; return 0; }

tag=$("$gh" release view --json tagName --jq .tagName 2>/dev/null) || tag=
if [[ ! $tag =~ ^v[0-9][0-9A-Za-z.]*$ || $tag =~ \.rc[0-9]+$ ]]; then
    echo "::error::fedora-next: no published release found (got '${tag}'); there is nothing to test yet"
    summary "### fedora-next: no published release found, nothing to test"
    exit 1
fi
version=${tag#v}
echo "fedora-next: testing release $tag"
summary "### Release under test: \`$tag\` (version-name $version)"
out "tag=$tag"
out "version=$version"
