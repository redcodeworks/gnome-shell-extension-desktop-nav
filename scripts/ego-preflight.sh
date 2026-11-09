#!/usr/bin/env bash
# EGO (extensions.gnome.org) pre-flight for a packed extension zip.
#
# Checks the zip against the review guidelines as READ BY US (heuristics, not the
# official linter; passing this does not guarantee approval). FAIL = hard rule,
# WARN = heuristic or judgment call, the reviewer decides.
#
# Usage: ego-preflight.sh ZIP [--repo-url URL] [--license-dir DIR] [--report FILE]
# Exit 0 = no FAIL, 1 = at least one FAIL, 2 = usage. The report is Markdown (stdout too).
set -uo pipefail

zip= repo_url=${GITHUB_REPOSITORY:+https://github.com/$GITHUB_REPOSITORY} lic_dir=. report=
while [ $# -gt 0 ]; do
    case $1 in
        --repo-url) repo_url=$2; shift ;;
        --license-dir) lic_dir=$2; shift ;;
        --report) report=$2; shift ;;
        -*) echo "unknown option $1" >&2; exit 2 ;;
        *) zip=$1 ;;
    esac
    shift
done
[ -f "$zip" ] || { echo "usage: $0 ZIP [--repo-url URL] [--license-dir DIR] [--report FILE]" >&2; exit 2; }
command -v jq >/dev/null && command -v unzip >/dev/null || { echo "jq and unzip are required" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
rows="$tmp/rows"; : > "$rows"
nfail=0 nwarn=0 npass=0
add() { # LEVEL check detail
    case $1 in FAIL) nfail=$((nfail+1)) ;; WARN) nwarn=$((nwarn+1)) ;; *) npass=$((npass+1)) ;; esac
    printf '| %s | %s | %s |\n' "$1" "$2" "${3//|/\\|}" >> "$rows"
}

src="$tmp/src"; mkdir "$src"
if unzip -Z1 "$zip" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
    add FAIL "zip paths" "absolute or parent-relative entries"
else
    unzip -q "$zip" -d "$src" || add FAIL "zip" "cannot unpack"
fi

# --- files in the zip ---
has_schema_xml=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    case $f in
        */) continue ;;
        extension.js|metadata.json|prefs.js|stylesheet.css) ;;
        schemas/*.gschema.xml) has_schema_xml=1 ;;
        schemas/gschemas.compiled) add WARN "files" "schemas/gschemas.compiled is shipped: confirm the guidelines want the compiled schema included (the Shell compiles schemas itself since 44)" ;;
        LICENSE|LICENSE.*|COPYING|COPYING.*) ;;
        *.po|*.pot|*.mo) add FAIL "files" "translation file $f (not allowed in the upload)" ;;
        *.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp|*.ico|*.mp3|*.ogg|*.wav|*.mp4|*.webm|*.ttf|*.otf|*.woff|*.woff2) add FAIL "files" "media/font file $f" ;;
        *.sh|Makefile|makefile|justfile|package.json|package-lock.json|*.py|*.mk|Dockerfile|*.yml|*.yaml) add FAIL "files" "build/script file $f" ;;
        *.so|*.o|*.a|*.bin|*.exe|*.dll|*.zip|*.tar|*.gz|*.xz) add FAIL "files" "binary or archive $f" ;;
        *.js|*.mjs) add WARN "files" "extra JS module $f (fine if extension.js imports it)" ;;
        *) add FAIL "files" "unexpected file $f (the zip may hold only extension.js, metadata.json, prefs.js, stylesheet.css, schemas)" ;;
    esac
done < <(unzip -Z1 "$zip")
# any remaining regular file with NUL bytes in the allowed text files is a binary
while IFS= read -r f; do
    if LC_ALL=C grep -qP '\x00' "$f" 2>/dev/null; then add FAIL "files" "binary content in ${f#"$src"/}"; fi
done < <(find "$src" -type f \( -name '*.js' -o -name '*.json' -o -name '*.css' -o -name '*.xml' \))
[ -f "$src/extension.js" ] && add PASS "files" "extension.js present" || add FAIL "files" "extension.js missing at the zip root"
[ -f "$src/metadata.json" ] && add PASS "files" "metadata.json present" || add FAIL "files" "metadata.json missing at the zip root"

# --- metadata.json ---
m="$src/metadata.json"
if [ -f "$m" ] && jq -e 'type == "object"' "$m" >/dev/null 2>&1; then
    mj() { jq -r "$1" "$m"; }
    mt() { jq -e "$1" "$m" >/dev/null 2>&1; }
    for k in name description uuid shell-version; do
        mt "has(\"$k\")" || add FAIL "metadata" "required field $k missing"
    done
    mt 'has("version")' && add FAIL "metadata" "has a \"version\" field: EGO assigns it, remove it (use version-name)" || add PASS "metadata" "no version field"
    if mt 'has("version-name")'; then
        vn=$(mj '.["version-name"]')
        [[ $vn =~ ^[0-9A-Za-z.\ ]{1,16}$ ]] && add PASS "metadata" "version-name '$vn'" || add FAIL "metadata" "version-name must be 1-16 characters of letters, numbers, spaces and periods"
    else
        add WARN "metadata" "no version-name (optional, but the release tag needs it)"
    fi
    if mt 'has("session-modes")'; then
        if mt '.["session-modes"] == ["user"]'; then add FAIL "metadata" "session-modes is just [\"user\"], the default: remove it"
        else add WARN "metadata" "session-modes set: confirm the extension really needs it and explain the unlock-dialog use to the reviewer"; fi
    else add PASS "metadata" "no session-modes"; fi
    if mt 'has("donations")'; then
        if mt '.donations == null or .donations == {} or .donations == "" or (.donations|type == "object" and ([.[]|select(. != null and . != "")]|length) == 0)'; then
            add FAIL "metadata" "donations is present but empty"
        else add PASS "metadata" "donations has entries"; fi
    else add PASS "metadata" "no donations field"; fi
    if mt '(.["shell-version"]|type == "array") and (.["shell-version"]|length) > 0 and all(.["shell-version"][]; type == "string" and test("^[0-9]+(\\.(alpha|beta|rc))?$"))'; then
        add PASS "metadata" "shell-version entries are major-version strings ($(jq -c '.["shell-version"]' "$m"))"
    else add FAIL "metadata" "shell-version must be a non-empty list of major-version strings like \"51\" (not 51.1, not numbers)"; fi
    if mt 'has("url")'; then
        u=$(mj .url)
        if [ -z "$repo_url" ]; then add WARN "metadata" "url not compared (no --repo-url and no GITHUB_REPOSITORY)"
        elif [ "$u" = "$repo_url" ]; then add PASS "metadata" "url equals the repository URL"
        else add FAIL "metadata" "url '$u' differs from the repository URL '$repo_url'"; fi
    else add WARN "metadata" "no url field"; fi
    uuid=$(mj '.uuid // ""')
    if [[ $uuid =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$ ]]; then
        dom=${uuid##*@}
        if [ "$dom" = gnome.org ] || [[ $dom == *.gnome.org ]]; then add FAIL "metadata" "uuid uses the gnome.org domain"
        else add PASS "metadata" "uuid format valid, not under gnome.org"; fi
    else add FAIL "metadata" "uuid '$uuid' must look like name@domain (letters, numbers, . _ -)"; fi
    if mt 'has("settings-schema")' && [ "$has_schema_xml" = 0 ]; then add FAIL "metadata" "settings-schema set but no schemas/*.gschema.xml in the zip"; fi
else
    [ -f "$m" ] && add FAIL "metadata" "metadata.json is not a JSON object"
fi

# --- license (repository, not the zip) ---
lic=
for c in LICENSE LICENSE.md LICENSE.txt COPYING COPYING.md; do [ -f "$lic_dir/$c" ] && { lic="$lic_dir/$c"; break; }; done
if [ -z "$lic" ]; then add FAIL "license" "no LICENSE or COPYING file in $lic_dir"
elif head -n 40 "$lic" | grep -qiE 'GNU (LESSER |AFFERO )?GENERAL PUBLIC LICENSE|MIT License|Permission is hereby granted, free of charge|BSD [23]-Clause|Redistribution and use in source and binary forms|Mozilla Public License'; then
    add PASS "license" "$(basename "$lic") looks GPL-compatible (GPL, LGPL, MIT, BSD or MPL text)"
else add WARN "license" "$(basename "$lic") not recognized as a GPL-compatible license: check by hand"; fi

# --- JavaScript ---
js_files=(); while IFS= read -r f; do js_files+=("$f"); done < <(find "$src" -type f \( -name '*.js' -o -name '*.mjs' \) | sort)
for f in "${js_files[@]}"; do
    n=${f#"$src"/}
    long=$(awk 'length > 300 { c++ } END { print c+0 }' "$f")
    [ "$long" -gt 0 ] && add FAIL "code" "$n: $long line(s) over 300 characters (minified or obfuscated code is rejected)"
    if grep -nE "(^|[^A-Za-z_])(ByteArray|Mainloop)\b|imports\.(byteArray|lang|mainloop)|gjs/modules/(lang|mainloop|byteArray)|import \* as Lang\b|\bLang\.(bind|Class)\b" "$f" >/dev/null; then
        add FAIL "code" "$n: deprecated module (ByteArray, Lang or Mainloop)"
    fi
    grep -qE '(^|[^A-Za-z_])imports\.' "$f" && add WARN "code" "$n: legacy imports.* syntax (use ESM imports)"
    grep -qE '\bconsole\.log\(' "$f" && add FAIL "code" "$n: console.log (remove it; the guidelines allow no debug noise)"
    grep -qE '(^|[^A-Za-z_.])(print|log)\(|\bconsole\.debug\(' "$f" && add WARN "code" "$n: console.debug/print/log present: make sure it is not inside an event handler or hot path"
    grep -qE 'Gio\.Subprocess|SubprocessLauncher' "$f" && add FAIL "code" "$n: Gio.Subprocess is not allowed here"
    grep -qE 'GLib\.spawn_|GLib\.spawn\b' "$f" && add WARN "code" "$n: GLib.spawn*: spawning processes needs a justification"

    # brace-depth heuristics: module-load / constructor work, signal pairing
    awk -v name="$n" '
      function cnt(s, ch,   t) { t = s; return gsub(ch, "", t) }
      BEGIN { depth = 0; inctor = 0; indis = 0 }
      {
        line = $0; sub(/\/\/.*$/, "", line)
        if (line ~ /^[[:space:]]*\/?\*/) next
        pat = "\\.connect[A-Za-z_]*\\(|new (St|Clutter|Meta|Gio|GLib|Shell|Gtk|Adw)\\.[A-Za-z]+|GLib\\.(timeout_add|idle_add)|setTimeout|setInterval"
        if (match(line, pat)) {
          if (depth == 0 && line !~ /^[[:space:]]*(import|export default class)/)
            print "FAIL|" name ": created or connected at module load (line " NR ")"
          if (inctor)
            print "FAIL|" name ": created or connected in the constructor (line " NR ")"
        }
        if (line ~ /^[[:space:]]*constructor[[:space:]]*\(/) { inctor = 1; ctordepth = depth }
        if (line ~ /^[[:space:]]*disable[[:space:]]*\([[:space:]]*\)/) { indis = 1; disdepth = depth }
        if (line ~ /\.connect(_after)?\(|\.connectObject\(|\.connectSignal\(|\.connect_after\(/) {
          if (line ~ /\.connectObject\(/) objc++; else conn++ }
        if (line ~ /\.disconnect\(|\.disconnect_object\(|\.disconnectSignal\(/) { disc_all++; if (indis) disc_dis++ }
        if (line ~ /\.disconnectObject\(|\.disconnectAll\(/) { objd_all++; if (indis) objd_dis++ }
        if (line ~ /(GLib\.(timeout_add|idle_add)|setTimeout|setInterval)/) timers++
        if (line ~ /(Source\.remove|clearTimeout|clearInterval|source_remove)/) timers_rm++
        depth += cnt(line, "{") - cnt(line, "}")
        if (inctor && depth <= ctordepth && line ~ /\}/) inctor = 0
        if (indis && depth <= disdepth && line ~ /\}/) indis = 0
      }
      END {
        if (conn > 0 && disc_dis < conn) {
          if (disc_all >= conn) print "WARN|" name ": " conn " signal connection(s), " disc_dis+0 " disconnect(s) in disable(), more elsewhere: check they are all reached from disable()"
          else print "FAIL|" name ": " conn " signal connection(s) but only " disc_all+0 " disconnect call(s): disconnect everything in disable()"
        }
        if (objc > 0 && objd_dis < 1) print "FAIL|" name ": connectObject used but no disconnectObject in disable()"
        if (timers > 0 && timers_rm < 1) print "FAIL|" name ": timer or idle source added but never removed"
        print "INFO|" name ": " conn+0 " connect, " objc+0 " connectObject, " disc_dis+0 " disconnect in disable()"
      }' "$f" > "$tmp/awk.out"
    while IFS='|' read -r lvl msg; do
        case $lvl in FAIL|WARN) add "$lvl" "code" "$msg" ;; INFO) add PASS "code" "$msg" ;; esac
    done < "$tmp/awk.out"
done
[ ${#js_files[@]} -gt 0 ] || add FAIL "code" "no JavaScript files"

# --- report ---
{
    echo "## EGO pre-flight: $(basename "$zip")"
    echo
    echo "Result: **$([ "$nfail" -eq 0 ] && echo PASS || echo FAIL)** ($nfail failed, $nwarn warnings, $npass passed). These are heuristics against the review guidelines as we read them, not the official linter."
    echo
    echo "| Level | Area | Finding |"
    echo "|---|---|---|"
    # failures first, then warnings, then passes
    for l in FAIL WARN PASS; do grep "^| $l " "$rows" || true; done
} > "$tmp/report.md"
[ -n "$report" ] && cp "$tmp/report.md" "$report"
cat "$tmp/report.md"
[ "$nfail" -eq 0 ]
