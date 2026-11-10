#!/usr/bin/env bash
# fedora-next workflow: triggers, pins, plan logic (stub skopeo), verdict behavior per event,
# nothing uploaded or published, the required-check workflows untouched. No network.
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
if set(on) != {"push", "pull_request", "schedule", "workflow_dispatch"}: err("triggers must be push, pull_request, schedule, workflow_dispatch")
if on["push"] != {"branches": ["testing"]}: err("push only on testing")
if on["pull_request"] != {"branches": ["testing"]}: err("pull_request only into testing")
cr = on["schedule"][0]["cron"]
if not re.fullmatch(r"0 \d{1,2} \* \* \d", cr): err("cron must be on the hour: " + cr)
if cr == "23 6 * * 3" or cr.startswith("23 "): err("cron coincides with gnome-version-watch")
if y.get("permissions") != {"contents": "read"}: err("top-level permissions must be contents: read")
c = y.get("concurrency", {})
if c.get("cancel-in-progress") is not True or "pull_request.number" not in c.get("group", ""): err("concurrency per PR/ref with cancel-in-progress")
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
if re.search(r"upload-artifact|download-artifact|gh release|release create|attest|actions: write|contents: write|gh issue|git push", txt): err("must upload and publish nothing")
nt = jobs["next-test"]
if nt.get("if") != "needs.plan.outputs.run == 'true'": err("next-test must run only when the plan found an image")
if nt.get("container") != "${{ needs.plan.outputs.image }}": err("container must be the plan's image")
if "continue-on-error" in nt: err("next-test must not use job-level continue-on-error")
steps = {s.get("id"): s for s in nt["steps"] if s.get("id")}
for sid in ("install", "suite", "schema", "pack", "preflight", "probe"):
    if sid not in steps or steps[sid].get("continue-on-error") is not True: err("step %s needs continue-on-error: true" % sid)
if "just test" not in steps["suite"]["run"] or "just pack" not in steps["pack"]["run"]: err("suite must run just test and just pack")
if "ego-preflight.sh" not in steps["preflight"]["run"]: err("pre-flight step missing")
if "api-probe.sh" not in steps["probe"]["run"]: err("probe step missing")
inst = steps["install"]["run"]
for pkg in "git nodejs gnome-shell just unzip zip jq glib2-devel python3-pyyaml".split():
    if not re.search(r"\b%s\b" % re.escape(pkg), inst): err("install lacks " + pkg)
verdict = [s for s in nt["steps"] if s.get("name") == "Verdict"]
if len(verdict) != 1 or verdict[0].get("if") != "always()": err("one Verdict step with if: always()")
else:
    open(out + "/verdict.sh", "w").write(verdict[0]["run"])
    for k in ("INSTALL", "SUITE", "SCHEMA", "PACK", "PREFLIGHT", "PROBE", "EVENT", "IMAGE"):
        if k not in verdict[0]["env"]: err("Verdict lacks env " + k)
plan = jobs["plan"]
if "scripts/fedora-next-plan.sh" not in str(plan["steps"]): err("plan job must run scripts/fedora-next-plan.sh")
if set(plan["outputs"]) != {"run", "image"}: err("plan outputs run and image")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && pass "fedora-next.yml structure" || fail "fedora-next.yml structure"

# the workflows that carry the required checks (and promotion) stay as they were; update these
# sums on purpose when one of them is changed
declare -A sums=(
    [ci.yml]=91e54c398f0551b8593a81b1bbe8c7deead2cb5bbb6f9936231b839a9dbb5b57
    [promote.yml]=fafaa783bfa647406619ac92e28ac16e25a6dc18386e585d57524c09f26afcc4
    [require-testing-branch.yml]=efc25cf8404e56c1e0d561454984cd47ab178f69fa5ae6a8331812abe3d2b29f
)
for f in "${!sums[@]}"; do
    got=$(sha256sum "$root/.github/workflows/$f" | cut -d' ' -f1)
    [ "$got" = "${sums[$f]}" ] && pass "$f unchanged" || fail "$f changed (sum $got); update tests/test-fedora-next.sh if that was intended"
done

# verdict step per event: push and pull_request warn and stay green; schedule and dispatch go red
ve() { # EVENT [VAR=outcome ...]
    local ev=$1; shift
    env -i PATH="$PATH" GITHUB_STEP_SUMMARY="$tmp/sum.md" EVENT="$ev" IMAGE=docker.io/library/fedora:46 \
        INSTALL=success SUITE=success SCHEMA=success PACK=success PREFLIGHT=success PROBE=success "$@" bash "$tmp/verdict.sh"
}
for ev in push pull_request; do
    expect_rc 0 "verdict: all good on $ev" ve $ev
    expect_rc 0 "verdict: probe failure on $ev stays green" ve $ev PROBE=failure
    expect_out '::warning::extension may break on docker.io/library/fedora:46: failed steps: api-probe' "verdict: $ev warns"
done
for ev in schedule workflow_dispatch; do
    expect_rc 0 "verdict: all good on $ev" ve $ev
    expect_rc 1 "verdict: suite failure on $ev goes red" ve $ev SUITE=failure
    expect_out '::error::extension may break on .*just-test' "verdict: $ev reports"
    expect_rc 1 "verdict: install failure on $ev goes red" ve $ev INSTALL=failure SUITE=skipped PACK=skipped PROBE=skipped
done
expect_rc 0 "verdict: skipped steps are not failures" ve push SUITE=skipped
grep -q 'extension may break' "$tmp/sum.md" && pass "verdict writes a summary" || fail "verdict writes a summary"

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
