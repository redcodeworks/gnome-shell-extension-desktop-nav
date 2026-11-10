#!/usr/bin/env bash
# fedora-next workflow: triggers, pins, release lookup (stub gh), plan logic (stub skopeo),
# verdict behavior, nothing uploaded or published, the required-check workflows untouched. No network.
. "$(dirname "$0")/lib.sh"
py=(python3 -I)
"${py[@]}" -c 'import yaml' 2>/dev/null || {
    if command -v uv >/dev/null; then py=(uv run --no-project --quiet --with pyyaml python -I)
    else echo "SKIP: no PyYAML (install python3-pyyaml)"; exit 0; fi; }
wf=$root/.github/workflows/fedora-next.yml
[ -f "$wf" ] || { fail "fedora-next.yml exists"; finish; exit; }

"${py[@]}" - "$wf" "$tmp" <<'PY'
import sys, re, yaml
f, out = sys.argv[1], sys.argv[2]; bad = 0
def err(m):
    global bad; bad += 1; print("FAIL", m, file=sys.stderr)
txt = open(f).read(); y = yaml.safe_load(txt)
on = y.get(True, y.get("on"))
if set(on) != {"schedule", "workflow_dispatch"}: err("triggers must be schedule and workflow_dispatch only (no push, no pull_request)")
cr = on["schedule"][0]["cron"]
if cr != "0 6 * * 1": err("cron must be Monday 06:00 UTC: " + cr)
if y.get("permissions") != {"contents": "read"}: err("top-level permissions must be contents: read")
c = y.get("concurrency", {})
if c.get("cancel-in-progress") is not True or c.get("group") != "fedora-next": err("one concurrency group, cancel-in-progress")
if str(y["env"].get("FEDORA_BASELINE")) != "45": err("FEDORA_BASELINE must be 45 (the release nox runs)")
jobs = y["jobs"]
if set(jobs) != {"plan", "next-test"}: err("jobs must be exactly plan and next-test (never test or secrets: those are required check names)")
for jn, j in jobs.items():
    if j.get("runs-on") != "ubuntu-26.04": err(jn + ": runner must be ubuntu-26.04")
    if "permissions" in j: err(jn + ": no job-level permissions")
    if "needs" in j and j["needs"] != "plan": err(jn + ": only next-test may need plan")
for i, line in enumerate(txt.splitlines(), 1):
    m = re.match(r"\s*-?\s*uses:\s*(\S+)(.*)", line)
    if m:
        if not re.search(r"@[0-9a-f]{40}$", m.group(1)): err(f"line {i}: action not pinned by SHA")
        if not re.search(r"#\s*v\d", m.group(2)): err(f"line {i}: no version comment")
if re.search(r"upload-artifact|download-artifact|gh release (create|delete|upload|edit)|release create|attest|actions: write|contents: write|gh issue|git push", txt): err("must upload and publish nothing")
nt = jobs["next-test"]
if nt.get("if") != "needs.plan.outputs.run == 'true'": err("next-test must run only when the plan found an image")
if nt.get("container") != "${{ needs.plan.outputs.image }}": err("container must be the plan's image")
if "continue-on-error" in nt: err("next-test must not use job-level continue-on-error")
steps = {s.get("id"): s for s in nt["steps"] if s.get("id")}
for sid in ("install", "suite", "schema", "zip", "preflight", "probe"):
    if sid not in steps or steps[sid].get("continue-on-error") is not True: err("step %s needs continue-on-error: true" % sid)
if "just test" not in steps["suite"]["run"]: err("suite must run just test")
if "releases/download/$TAG" not in steps["zip"]["run"] or "sha256sum -c" not in steps["zip"]["run"]: err("the released zip must be downloaded and checksum-verified")
co = [s for s in nt["steps"] if str(s.get("uses", "")).startswith("actions/checkout")]
if len(co) != 1 or co[0].get("with", {}).get("ref") != "${{ needs.plan.outputs.tag }}": err("next-test must check out the release tag, not the branch")
if "ego-preflight.sh" not in steps["preflight"]["run"]: err("pre-flight step missing")
if "api-probe.sh" not in steps["probe"]["run"]: err("probe step missing")
inst = steps["install"]["run"]
for pkg in "git nodejs gnome-shell just unzip zip jq glib2-devel python3-pyyaml".split():
    if not re.search(r"\b%s\b" % re.escape(pkg), inst): err("install lacks " + pkg)
verdict = [s for s in nt["steps"] if s.get("name") == "Verdict"]
if len(verdict) != 1 or verdict[0].get("if") != "always()": err("one Verdict step with if: always()")
else:
    open(out + "/verdict.sh", "w").write(verdict[0]["run"])
    for k in ("INSTALL", "SUITE", "SCHEMA", "ZIP", "PREFLIGHT", "PROBE", "RELEASE", "IMAGE"):
        if k not in verdict[0]["env"]: err("Verdict lacks env " + k)
plan = jobs["plan"]
if "scripts/fedora-next-plan.sh" not in str(plan["steps"]): err("plan job must run scripts/fedora-next-plan.sh")
if set(plan["outputs"]) != {"run", "image", "tag", "version"}: err("plan outputs run, image, tag and version")
if "scripts/fedora-next-release.sh" not in str(plan["steps"]): err("plan job must run scripts/fedora-next-release.sh")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && pass "fedora-next.yml structure" || fail "fedora-next.yml structure"

# the workflows that carry the required checks (and promotion) stay as they were; update these
# sums on purpose when one of them is changed
declare -A sums=(
    [ci.yml]=a94ea2e353adb1adcf5a0745ba8005be97470aec0ff6052073cf5ed919cf49e8
    [promote.yml]=906907a04ac7a9e54a1b34dcc6ee94f8cca820825a950abda19791c99eb12114
    [require-testing-branch.yml]=efc25cf8404e56c1e0d561454984cd47ab178f69fa5ae6a8331812abe3d2b29f
)
for f in "${!sums[@]}"; do
    got=$(sha256sum "$root/.github/workflows/$f" | cut -d' ' -f1)
    [ "$got" = "${sums[$f]}" ] && pass "$f unchanged" || fail "$f changed (sum $got); update tests/test-fedora-next.sh if that was intended"
done

# verdict step: a failure always goes red (the run is the early warning), skipped steps are not failures
ve() { # [VAR=outcome ...]
    env -i PATH="$PATH" GITHUB_STEP_SUMMARY="$tmp/sum.md" RELEASE=v0.4.1 IMAGE=docker.io/library/fedora:46 \
        INSTALL=success SUITE=success SCHEMA=success ZIP=success PREFLIGHT=success PROBE=success "$@" bash "$tmp/verdict.sh"
}
expect_rc 0 "verdict: all good" ve
grep -q 'release `v0.4.1` passed on `docker.io/library/fedora:46`' "$tmp/sum.md" && pass "verdict: summary names the release and the image" || fail "verdict: summary names the release and the image"
expect_rc 1 "verdict: probe failure goes red" ve PROBE=failure
expect_out '::error::release v0.4.1 may break on docker.io/library/fedora:46: failed steps: api-probe' "verdict: reports release, image and step"
expect_rc 1 "verdict: suite failure goes red" ve SUITE=failure
expect_rc 1 "verdict: zip failure goes red" ve ZIP=failure PREFLIGHT=skipped
expect_out 'release-zip' "verdict: names the zip step"
expect_rc 1 "verdict: install failure goes red" ve INSTALL=failure SUITE=skipped ZIP=skipped PROBE=skipped
expect_rc 0 "verdict: skipped steps are not failures" ve SUITE=skipped
grep -q 'may break' "$tmp/sum.md" && pass "verdict writes a summary" || fail "verdict writes a summary"

# release lookup with a stub gh
cat > "$tmp/gh" <<'STUB'
#!/usr/bin/env bash
# usage: gh release view --json tagName --jq .tagName ; TAG = printed tag, GHFAIL=1 = no release
[ -n "${GHFAIL:-}" ] && { echo "release not found" >&2; exit 1; }
echo "gh $*" >> "$LOG"
echo "$TAG"
STUB
chmod +x "$tmp/gh"
LOG=$tmp/gh.log; export LOG
rel() { : > "$tmp/gh.out"; : > "$tmp/sum3.md"
    env -i PATH="$PATH" LOG="$LOG" GH="$tmp/gh" GITHUB_OUTPUT="$tmp/gh.out" GITHUB_STEP_SUMMARY="$tmp/sum3.md" "$@" "$root/scripts/fedora-next-release.sh"; }
: > "$tmp/gh.log"
expect_rc 0 "release: latest release found" rel TAG=v0.4.1
grep -qx tag=v0.4.1 "$tmp/gh.out" && grep -qx version=0.4.1 "$tmp/gh.out" && pass "release: tag and version output" || fail "release: tag and version output"
grep -q 'v0.4.1' "$tmp/sum3.md" && pass "release: summary names the release" || fail "release: summary names the release"
expect_rc 1 "release: no release yet fails" rel GHFAIL=1
expect_out 'no published release found' "release: clear message"
expect_rc 1 "release: empty answer fails" rel TAG=
expect_rc 1 "release: odd tag fails" rel 'TAG=testing'
# prereleases (the rolling testing build, its -rc names) must never be picked: the lookup is
# `gh release view` WITHOUT a tag, which GitHub answers with the Latest non-prerelease, and a
# tag that is not v<digits>... is refused even if some lookup returned one
: > "$tmp/gh.log"; LOG=$tmp/gh.log rel TAG=v0.4.1 >/dev/null 2>&1
[ "$(cat "$tmp/gh.log")" = "gh release view --json tagName --jq .tagName" ] && pass "release: asks for the latest release, not a named tag" || fail "release: lookup arguments ($(cat "$tmp/gh.log"))"
expect_rc 1 "release: an rc tag name is refused" rel LOG=$tmp/gh.log 'TAG=v0.6.0-rc2'
expect_rc 1 "release: the testing build title is refused" rel LOG=$tmp/gh.log 'TAG=testing (0.6.0-rc2, 0f65598)'
[ ! -s "$tmp/gh.out" ] && pass "release: nothing written on failure" || fail "release: nothing written on failure"

# plan script with a stub skopeo
cat > "$tmp/skopeo" <<'STUB'
#!/usr/bin/env bash
# usage: skopeo inspect --no-tags docker://IMAGE ; EXISTING = space separated images; NETFAIL=1 = transport error
img=${3#docker://}
echo "$img" >> "$STUB_LOG"
[ -n "${NETFAIL:-}" ] && { echo "dial tcp: i/o timeout" >&2; exit 1; }
for e in $EXISTING; do
    [ "$e" = "$img" ] && { echo '{"Created":"2026-11-01T00:00:00Z","Labels":{"org.opencontainers.image.version":"46"}}'; exit 0; }
done
echo "manifest unknown" >&2; exit 1
STUB
chmod +x "$tmp/skopeo"
plan() { : > "$tmp/log"; : > "$tmp/gh.out"; : > "$tmp/sum2.md"
    env -i PATH="$PATH" SKOPEO="$tmp/skopeo" STUB_LOG="$tmp/log" FEDORA_BASELINE=45 RETRY_WAIT=0 ATTEMPTS=2 \
        GITHUB_OUTPUT="$tmp/gh.out" GITHUB_STEP_SUMMARY="$tmp/sum2.md" "$@" "$root/scripts/fedora-next-plan.sh"; }
expect_rc 0 "plan: baseline+1 exists" plan EXISTING="docker.io/library/fedora:46 docker.io/library/fedora:branched"
grep -qx 'image=docker.io/library/fedora:46' "$tmp/gh.out" && grep -qx run=true "$tmp/gh.out" && pass "plan: fedora:46 wins over branched" || fail "plan: fedora:46 wins over branched"
[ "$(wc -l < "$tmp/log")" -eq 1 ] && pass "plan: stops at the first hit" || fail "plan: stops at the first hit"
grep -q 'version 46' "$tmp/sum2.md" && pass "plan: summary shows the image version" || fail "plan: summary shows the image version"
expect_rc 0 "plan: only branched exists" plan EXISTING="docker.io/library/fedora:branched"
grep -qx 'image=docker.io/library/fedora:branched' "$tmp/gh.out" && pass "plan: falls back to branched" || fail "plan: falls back to branched"
[ "$(sed -n 1p "$tmp/log")" = docker.io/library/fedora:46 ] && [ "$(sed -n 2p "$tmp/log")" = docker.io/library/fedora:branched ] && pass "plan: candidate order 46, branched" || fail "plan: candidate order"
expect_rc 0 "plan: nothing exists is green" plan EXISTING="docker.io/library/fedora:rawhide"
expect_out 'no newer Fedora image yet, nothing to test' "plan: notice text"
grep -qx run=false "$tmp/gh.out" && ! grep -q rawhide "$tmp/log" && pass "plan: run=false, rawhide never asked" || fail "plan: run=false, rawhide never asked"
expect_rc 0 "plan: lookup failure is green" plan NETFAIL=1
expect_out 'lookup failed' "plan: failure reported"
grep -qx run=false "$tmp/gh.out" && [ "$(wc -l < "$tmp/log")" -eq 2 ] && pass "plan: lookup retried, run=false" || fail "plan: lookup retried, run=false"
expect_rc 0 "plan: baseline is configurable" plan FEDORA_BASELINE=46 EXISTING="docker.io/library/fedora:47"
grep -qx 'image=docker.io/library/fedora:47' "$tmp/gh.out" && pass "plan: baseline 46 tries 47" || fail "plan: baseline 46 tries 47"
expect_rc 2 "plan: bad baseline" plan FEDORA_BASELINE=forty
finish
