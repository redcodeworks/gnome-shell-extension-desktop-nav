#!/usr/bin/env bash
# API probe: do the GNOME Shell symbols the extension depends on still exist in the
# Shell JavaScript of the INSTALLED gnome-shell package?
#
# Data: tests/shell-api.txt, one line per symbol, three TAB-separated fields:
#   file-in-the-shell-source (js/ui/main.js)  <TAB>  symbol or ERE  <TAB>  where the extension uses it
# Result per line: found (the pattern matches the file's text), missing (the file is
# there, the pattern is not), unverifiable (the file could not be obtained).
#
# Where the Shell sources come from, in order:
#   1. PROBE_SRC=DIR, a directory that holds js/... (tests and local use).
#   2. gresource files of the installed package (GRES_DIR, default /usr/share/gnome-shell):
#      the entries below /org/gnome/shell/ and /org/gnome/Shell/Extensions/js/ are
#      extracted. The main Shell code (js/ui/main.js and friends) is not readable there
#      on Fedora 45, only the Extensions resource is.
#   3. The source RPM of the installed version (dnf download --source, the *-source
#      repositories enabled), then the js/ directory of its tarball (rpm2cpio | cpio, tar).
# Everything is written to a temporary directory; every pattern is matched against a
# file on disk (never producer | grep -q under pipefail).
#
# Environment: PROBE_SRC, GRES_DIR, DATA (default tests/shell-api.txt), PROBE_DNF
#   (default dnf5, else dnf), PROBE_SRC_REPOS (space separated repo ids; default: every
#   *-source repo that is not a testing repo), PROBE_PKG (default gnome-shell), GITHUB_STEP_SUMMARY.
# Exit: 0 = no symbol missing, or the sources were unavailable (prints "API probe
#   skipped: Shell sources unavailable"); 1 = at least one symbol missing; 2 = bad data
#   file or usage.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
data=${DATA:-$here/tests/shell-api.txt}
pkg=${PROBE_PKG:-gnome-shell}
gres_dir=${GRES_DIR:-/usr/share/gnome-shell}
say() { echo "api-probe: $*"; }
bad() { echo "api-probe: bad data: $*" >&2; exit 2; }

[ -r "$data" ] || bad "cannot read $data"
tab=$'\t'
files=() syms=() wheres=() lines=()
n=0
while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1))
    case $line in ''|'#'*) continue ;; esac
    IFS=$tab read -r f s w extra <<<"$line"
    [ -n "${extra:-}" ] && bad "line $n: more than three TAB-separated fields"
    [ -n "$f" ] && [ -n "$s" ] && [ -n "${w:-}" ] || bad "line $n: needs three non-empty TAB-separated fields"
    [[ $f =~ ^js/[A-Za-z0-9_./-]+\.js$ ]] || bad "line $n: file '$f' is not a js/... path"
    # an invalid regular expression makes grep exit 2
    rc=0; grep -E -- "$s" /dev/null >/dev/null 2>&1 || rc=$?
    [ "$rc" -le 1 ] || bad "line $n: '$s' is not a valid extended regular expression"
    files+=("$f"); syms+=("$s"); wheres+=("$w"); lines+=("$n")
done < "$data"
[ "${#files[@]}" -gt 0 ] || bad "no data lines in $data"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
roots=()   # directories that hold js/...

if [ -n "${PROBE_SRC:-}" ]; then
    [ -d "$PROBE_SRC" ] && roots+=("$PROBE_SRC")
else
    # 2. gresource files of the installed package
    if command -v gresource >/dev/null 2>&1 && [ -d "$gres_dir" ]; then
        for r in "$gres_dir"/*.gresource; do
            [ -f "$r" ] || continue
            gresource list "$r" > "$work/list.txt" 2>/dev/null || continue
            while IFS= read -r p; do
                case $p in
                    /org/gnome/shell/*.js) rel=js/${p#/org/gnome/shell/} ;;
                    /org/gnome/Shell/Extensions/js/*.js) rel=js/${p#/org/gnome/Shell/Extensions/js/} ;;
                    *) continue ;;
                esac
                mkdir -p "$work/gres/$(dirname "$rel")"
                gresource extract "$r" "$p" > "$work/gres/$rel" 2>/dev/null || rm -f "$work/gres/$rel"
            done < "$work/list.txt"
        done
        [ -d "$work/gres/js" ] && roots+=("$work/gres")
    fi
    have_all() {
        local f d
        for f in "${files[@]}"; do
            d=0
            for r in "${roots[@]}"; do [ -f "$r/$f" ] && d=1; done
            [ "$d" -eq 1 ] || return 1
        done
    }
    if ! have_all; then
        # 3. the source RPM of the installed version
        dnf=${PROBE_DNF:-}
        [ -n "$dnf" ] || { command -v dnf5 >/dev/null 2>&1 && dnf=dnf5 || dnf=dnf; }
        evr=$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$pkg" 2>/dev/null) || evr=
        if command -v "$dnf" >/dev/null 2>&1 && command -v rpm2cpio >/dev/null 2>&1 && command -v cpio >/dev/null 2>&1; then
            repos=${PROBE_SRC_REPOS:-}
            if [ -z "$repos" ]; then
                repos=$("$dnf" repolist --all 2>/dev/null | awk '$1 ~ /-source$/ && $1 !~ /testing/ {print $1}' | tr '\n' ' ')
            fi
            args=(download --source --destdir "$work/srpm")
            for id in $repos; do args+=("--enable-repo=$id"); done
            mkdir -p "$work/srpm"
            ok=0
            # the exact installed version first, then whatever the source repos have
            if [ -n "$evr" ] && "$dnf" "${args[@]}" "$pkg-$evr" >"$work/dnf.log" 2>&1; then ok=1
            elif "$dnf" "${args[@]}" "$pkg" >>"$work/dnf.log" 2>&1; then ok=1; fi
            srpm=$(ls "$work"/srpm/"$pkg"-*.src.rpm 2>/dev/null | head -n 1)
            if [ "$ok" -eq 1 ] && [ -n "$srpm" ]; then
                mkdir -p "$work/rpm" "$work/tree"
                ( cd "$work/rpm" && rpm2cpio "$srpm" | cpio -idm --quiet ) >/dev/null 2>&1
                tarball=$(ls "$work"/rpm/"$pkg"-*.tar.* 2>/dev/null | head -n 1)
                if [ -n "$tarball" ] && tar -xf "$tarball" -C "$work/tree" --wildcards '*/js/*' 2>/dev/null; then
                    top=$(ls -d "$work"/tree/*/ 2>/dev/null | head -n 1)
                    [ -n "$top" ] && [ -d "${top}js" ] && roots+=("${top%/}")
                    say "Shell sources from $(basename "$srpm")"
                fi
            else
                say "source RPM download failed: $(tail -n 2 "$work/dnf.log" | tr '\n' ' ')"
            fi
        fi
    else
        say "Shell sources from the installed gresource files"
    fi
fi

if [ "${#roots[@]}" -eq 0 ]; then
    msg="API probe skipped: Shell sources unavailable"
    echo "$msg"
    [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$msg" >> "$GITHUB_STEP_SUMMARY"
    exit 0
fi

found=0 missing=0 unver=0
rows=()
for i in "${!files[@]}"; do
    f=${files[$i]} s=${syms[$i]} path=
    for r in "${roots[@]}"; do [ -f "$r/$f" ] && { path=$r/$f; break; }; done
    if [ -z "$path" ]; then res=unverifiable; unver=$((unver+1))
    else
        rc=0; grep -Eq -- "$s" "$path" || rc=$?
        case $rc in
            0) res=found; found=$((found+1)) ;;
            1) res=MISSING; missing=$((missing+1)) ;;
            *) bad "line ${lines[$i]}: grep failed on '$s'" ;;
        esac
    fi
    rows+=("$res$tab$f$tab$s$tab${wheres[$i]}")
done
printf '%-13s %-34s %-34s %s\n' RESULT FILE SYMBOL USED-IN
for row in "${rows[@]}"; do
    IFS=$tab read -r res f s w <<<"$row"
    printf '%-13s %-34s %-34s %s\n' "$res" "$f" "$s" "$w"
done
echo "API probe: found=$found missing=$missing unverifiable=$unver"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### API probe"; echo
        echo "| result | file | symbol | used in |"; echo "|---|---|---|---|"
        for row in "${rows[@]}"; do
            IFS=$tab read -r res f s w <<<"$row"
            s=${s//|/\\|}
            echo "| $res | $f | \`$s\` | $w |"
        done
        echo; echo "found=$found missing=$missing unverifiable=$unver"; echo
    } >> "$GITHUB_STEP_SUMMARY"
fi
[ "$missing" -eq 0 ]
