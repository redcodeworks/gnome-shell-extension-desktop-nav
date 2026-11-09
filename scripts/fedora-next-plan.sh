#!/usr/bin/env bash
# Plan for the fedora-next workflow: which Fedora image is the NEXT release after the one
# nox runs? Candidates in order: docker.io/library/fedora:<baseline+1>, then
# docker.io/library/fedora:branched; the first that exists wins. rawhide is not used.
# Nothing to test (no candidate exists, or the registry lookup failed) is not an error:
# prints a notice, writes run=false and exits 0.
#
# Environment: FEDORA_BASELINE (required, the Fedora release nox runs), SKOPEO (default
#   skopeo), ATTEMPTS (default 3) and RETRY_WAIT (seconds, default 5) per lookup,
#   GITHUB_OUTPUT (run=, image=), GITHUB_STEP_SUMMARY.
# Exit: 0 always when the inputs are valid, 2 = FEDORA_BASELINE is not a number.
set -uo pipefail

baseline=${FEDORA_BASELINE:-}
[[ $baseline =~ ^[0-9]+$ ]] || { echo "FEDORA_BASELINE must be a number, got '$baseline'" >&2; exit 2; }
skopeo=${SKOPEO:-skopeo}
attempts=${ATTEMPTS:-3}
wait_s=${RETRY_WAIT:-5}
candidates=("docker.io/library/fedora:$((baseline+1))" "docker.io/library/fedora:branched")

out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1" >> "$GITHUB_OUTPUT"; return 0; }
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"; return 0; }
nothing() { # REASON
    echo "::notice::no newer Fedora image yet, nothing to test ($1)"
    summary "### fedora-next: no newer Fedora image yet, nothing to test"
    summary "Baseline $baseline; $1."
    out "run=false"
    exit 0
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
lookup_failed=
for img in "${candidates[@]}"; do
    state=
    for ((a=1; a<=attempts; a++)); do
        if "$skopeo" inspect --no-tags "docker://$img" > "$tmp/inspect.json" 2> "$tmp/err.txt"; then state=found; break; fi
        # a missing tag is final; anything else (network, rate limit) is retried
        if grep -qiE 'manifest unknown|not found|404|name unknown' "$tmp/err.txt"; then state=absent; break; fi
        [ "$a" -lt "$attempts" ] && sleep "$wait_s"
    done
    case $state in
        found)
            ver=$(jq -r '(.Labels // {})["org.opencontainers.image.version"] // empty' "$tmp/inspect.json" 2>/dev/null || true)
            created=$(jq -r '.Created // empty' "$tmp/inspect.json" 2>/dev/null || true)
            info=${ver:+version $ver}${ver:+, }${created:+created $created}
            echo "fedora-next: using $img (${info:-no version or date in the image metadata})"
            summary "### fedora-next: testing against \`$img\`"
            summary "Baseline (nox): Fedora $baseline. Image metadata: ${info:-none}."
            out "run=true"; out "image=$img"
            exit 0 ;;
        absent) echo "fedora-next: $img does not exist" ;;
        *) echo "fedora-next: lookup of $img failed after $attempts attempts: $(tr '\n' ' ' < "$tmp/err.txt")"; lookup_failed=1; break ;;
    esac
done
if [ -n "$lookup_failed" ]; then nothing "the registry lookup failed"; fi
nothing "none of ${candidates[*]} exists"
