#!/usr/bin/env bash
# Is the GNOME Shell major in Fedora's upcoming release newer than metadata.json's
# shell-version list? If so, open ONE issue "Support GNOME Shell <N>".
#
# Runs inside a Fedora container (dnf repoquery). Channels are tried in the order of
# $CHANNELS (default "branched rawhide released"); the FIRST that answers wins and is
# reported. "branched" is the next Fedora release before it ships (beta); when it does
# not exist yet its repositories do not resolve, the channel is skipped with a log line
# and rawhide is used.
#
# Environment: METADATA (path to metadata.json), REPO (owner/name, for gh),
#   CHANNELS, PACKAGE (default gnome-shell), DNF (default dnf), GH (default gh),
#   RELEASED_VER (default: VERSION_ID of /etc/os-release), DRY_RUN=1 (never touch GitHub),
#   RELEASEVER_<channel> / REPOS_<channel> to override a channel's definition,
#   RAWHIDE_REPO_FILE (default /usr/share/dnf5/repos.d/fedora-rawhide.repo, from the
#   package fedora-repos-rawhide): the rawhide repository id is READ from this file
#   (first [section]), never hard-coded; without the file the rawhide channel is skipped.
# The version string is data: it is only matched against a regex and compared as numbers.
# Exit: 0 = done (issue created or nothing to do), 1 = error, 3 = no channel produced a version.
set -uo pipefail

metadata=${METADATA:?METADATA is not set}
package=${PACKAGE:-gnome-shell}
dnf=${DNF:-dnf}
gh=${GH:-gh}
channels=${CHANNELS:-branched rawhide released}
repo=${REPO:-}
say() { echo "gnome-version-watch: $*"; }

released=${RELEASED_VER:-}
if [ -z "$released" ] && [ -r /etc/os-release ]; then
    released=$(. /etc/os-release && echo "${VERSION_ID:-}")
fi
[[ $released =~ ^[0-9]+$ ]] || { say "cannot determine the released Fedora version (set RELEASED_VER)"; exit 1; }

rawhide_repo_file=${RAWHIDE_REPO_FILE:-/usr/share/dnf5/repos.d/fedora-rawhide.repo}
rawhide_repo_id() { # first [id] of the .repo file shipped by fedora-repos-rawhide
    [ -r "$rawhide_repo_file" ] || return 1
    sed -n 's/^\[\([A-Za-z0-9._-]\{1,\}\)\][[:space:]]*$/\1/p' "$rawhide_repo_file" | head -n 1
}

# channel definition: "<releasever> <repo ids>"
channel_def() {
    case $1 in
        released) echo "${RELEASEVER_released:-$released} ${REPOS_released:-fedora,updates}" ;;
        branched) echo "${RELEASEVER_branched:-$((released + 1))} ${REPOS_branched:-fedora,updates,updates-testing}" ;;
        rawhide)
            local rid=${REPOS_rawhide:-$(rawhide_repo_id)}
            [ -n "$rid" ] || { say "rawhide channel: no repository id (is fedora-repos-rawhide installed? looked in $rawhide_repo_file)" >&2; return 1; }
            echo "${RELEASEVER_rawhide:-rawhide} $rid" ;;
        *) return 1 ;;
    esac
}

found_channel= found_nevr= found_repo= found_ver= found_rv=
for ch in $channels; do
    def=$(channel_def "$ch") || { say "channel '$ch' not usable, skipped"; continue; }
    rv=${def%% *} repos=${def#* }
    err=$(mktemp)
    out=$("$dnf" repoquery --releasever="$rv" --repo="$repos" --arch=x86_64,noarch --latest-limit=1 \
        --queryformat '%{name}|%{epoch}|%{version}|%{release}|%{arch}|%{repoid}\n' "$package" 2>"$err")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        say "channel $ch (releasever $rv): unavailable (dnf exit $rc: $(head -n 1 "$err" | cut -c1-200))"
        [ "$ch" = branched ] && say "no branched/beta release yet, falling back to the next channel"
        rm -f "$err"; continue
    fi
    rm -f "$err"
    line=$(printf '%s\n' "$out" | grep -E "^$package\|" | sort -t'|' -k3,3V | tail -n 1)
    if [ -z "$line" ]; then say "channel $ch (releasever $rv): no $package found"; continue; fi
    IFS='|' read -r n epoch ver rel arch rid <<<"$line"
    if ! [[ $ver =~ ^[0-9]+([.~][0-9A-Za-z.~_+]*)?$ ]]; then
        say "channel $ch: unparseable version '$ver', skipped"; continue
    fi
    found_channel=$ch found_rv=$rv found_ver=$ver found_repo=$rid
    found_nevr="$n-${epoch:-0}:$ver-$rel.$arch"
    say "channel $ch (releasever $rv): $found_nevr from repository $rid"
    break
done
[ -n "$found_channel" ] || { say "no channel produced a $package version"; exit 3; }

# Major versions, compared numerically. 52.alpha, 52~beta -> 52.
major=$((10#${found_ver%%[!0-9]*}))
listed_max=-1 listed=()
while IFS= read -r v; do
    [[ $v =~ ^([0-9]+) ]] || continue
    n=$((10#${BASH_REMATCH[1]})); listed+=("$n")
    [ "$n" -gt "$listed_max" ] && listed_max=$n
done < <(jq -r '.["shell-version"][]? | tostring' "$metadata")
[ "$listed_max" -ge 0 ] || { say "metadata.json lists no usable shell-version"; exit 1; }
say "found major $major ($found_ver) via $found_channel; metadata lists: ${listed[*]} (max $listed_max)"

if [ "$major" -le "$listed_max" ]; then
    say "GNOME Shell $major is not newer than the listed majors, nothing to do"
    exit 0
fi

title="Support GNOME Shell $major"
if [ "${DRY_RUN:-0}" = 1 ]; then say "dry run: would open issue '$title'"; exit 0; fi
[ -n "$repo" ] || { say "REPO is not set"; exit 1; }

# Dedupe: an open issue with this title or the label means someone already knows.
open=$("$gh" issue list -R "$repo" --state open --label gnome-version --json number,title) || { say "cannot list issues"; exit 1; }
if [ "$(jq 'length' <<<"$open")" -gt 0 ]; then
    say "open gnome-version issue exists ($(jq -r '[.[]|"#\(.number) \(.title)"]|join(", ")' <<<"$open")), nothing to do"
    exit 0
fi
open=$("$gh" issue list -R "$repo" --state open --search "\"$title\" in:title" --json number,title) || { say "cannot search issues"; exit 1; }
if [ "$(jq --arg t "$title" '[.[]|select(.title == $t)]|length' <<<"$open")" -gt 0 ]; then
    say "open issue titled '$title' exists, nothing to do"
    exit 0
fi

labels=$("$gh" label list -R "$repo" --json name --limit 200) || { say "cannot list labels"; exit 1; }
if [ "$(jq '[.[]|select(.name == "gnome-version")]|length' <<<"$labels")" -eq 0 ]; then
    "$gh" label create gnome-version -R "$repo" --color 5319e7 --description "A newer GNOME Shell major is coming" || { say "cannot create the label"; exit 1; }
fi

body=$(mktemp)
cat > "$body" <<BODY
A newer GNOME Shell major shows up in Fedora's upcoming release and is not in \`shell-version\` of \`metadata.json\` (listed: ${listed[*]}).

- Version found: \`$found_ver\` (major $major)
- Package: \`$found_nevr\`
- Repository: \`$found_repo\` (channel \`$found_channel\`, releasever \`$found_rv\`)
- Found by the weekly gnome-version-watch workflow.

Checklist:
- [ ] Test in a nested session: \`dbus-run-session gnome-shell --devkit --wayland\`
- [ ] Add \`"$major"\` to \`shell-version\` in \`metadata.json\`
- [ ] Bump \`version-name\` (no hyphens, 1-16 characters)
- [ ] Test again (back/forward buttons on the empty desktop, on a window, in the overview)
- [ ] Merge the pull request from \`testing\` into \`main\`
- [ ] Check the new release (the promote workflow publishes it when the version-name is new)
BODY
"$gh" issue create -R "$repo" --title "$title" --label gnome-version --body-file "$body" || { rm -f "$body"; say "cannot create the issue"; exit 1; }
rm -f "$body"
say "opened '$title'"
