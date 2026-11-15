#!/usr/bin/env bash
# Workflow files: YAML parses, actions pinned by SHA, pinned runner, required job names, triggers.
. "$(dirname "$0")/lib.sh"
py=(python3 -I)
"${py[@]}" -c 'import yaml' 2>/dev/null || {
    if command -v uv >/dev/null; then py=(uv run --no-project --quiet --with pyyaml python -I)
    else echo "SKIP: no PyYAML (install python3-pyyaml)"; exit 0; fi; }
"${py[@]}" - "$root/.github/workflows" <<'PY'
import sys, re, glob, yaml
d = sys.argv[1]; bad = 0
def err(m):
    global bad; bad += 1; print("FAIL", m, file=sys.stderr)
files = sorted(glob.glob(d + "/*.yml"))
if not files: err("no workflows")
docs = {}
for f in files:
    txt = open(f).read()
    y = yaml.safe_load(txt); docs[f.rsplit("/", 1)[1]] = y
    on = y.get(True, y.get("on"))
    ond = on if isinstance(on, dict) else {}
    if "pull_request_target" in ond: err(f + ": has a pull_request_target trigger")
    if "pull_request" in ond and not f.endswith(("/ci.yml", "/require-testing-branch.yml")):
        err(f + ": has a pull_request trigger")
    for i, line in enumerate(txt.splitlines(), 1):
        m = re.match(r"\s*-?\s*uses:\s*(\S+)(.*)", line)
        if m and not m.group(1).startswith("./"):
            if not re.search(r"@[0-9a-f]{40}$", m.group(1)): err(f"{f}:{i}: action not pinned by SHA: {m.group(1)}")
            if not re.search(r"#\s*v\d", m.group(2)): err(f"{f}:{i}: no version comment")
    for jn, j in (y.get("jobs") or {}).items():
        r = j.get("runs-on", "")
        if not isinstance(r, str) or "latest" in r: err(f"{f}: job {jn}: runner not pinned: {r}")
ci = docs.get("ci.yml", {})
for name in ("test", "secrets"):
    if name not in ci.get("jobs", {}): err("ci.yml lacks job " + name)
    elif ci["jobs"][name].get("name", name) != name: err("ci.yml job %s has a different display name" % name)
on = ci.get(True, ci.get("on"))
if on.get("push", {}).get("branches") != ["testing"]: err("ci.yml must trigger on push to testing only")
if set(on) != {"push", "pull_request"}: err("ci.yml triggers must be exactly push and pull_request (a feature-branch push alone must not run)")
if on.get("pull_request", {}).get("branches") != ["testing"]: err("ci.yml pull_request must target testing only")
if "pull_request" not in str(ci.get("concurrency", {}).get("group", "")) and "github.event.pull_request.number" not in str(ci.get("concurrency", {}).get("group", "")): err("ci.yml concurrency must group per pull request")
if ci.get("concurrency", {}).get("cancel-in-progress") is not True: err("ci.yml must cancel in progress")
# PR runs validate only: every upload step is gated to a push on testing
for jn, j in ci["jobs"].items():
    for st in j.get("steps", []):
        if "upload-artifact" in str(st.get("uses", "")):
            c = str(st.get("if", ""))
            if "github.event_name == 'push'" not in c or "refs/heads/testing" not in c: err("ci.yml upload step must be gated to push on testing")
rt = docs.get("require-testing-branch.yml", {})
ron = rt.get(True, rt.get("on")) or {}
if ron != {"pull_request": {"branches": ["main"]}}: err("require-testing-branch.yml must trigger only on pull_request into main")
if rt.get("permissions") != {}: err("require-testing-branch.yml permissions must be {}")
if list(rt.get("jobs", {})) != ["require-testing-branch"]: err("require-testing-branch.yml needs the single job require-testing-branch")
elif any("checkout" in str(st.get("uses", "")) for st in rt["jobs"]["require-testing-branch"]["steps"]): err("require-testing-branch must not check out")
pr = docs.get("promote.yml", {}); on = pr.get(True, pr.get("on"))
if on.get("push", {}).get("branches") != ["main"]: err("promote.yml must trigger on push to main only")
if list(docs.get("prepare-ego.yml", {}).get(True, {}).keys()) != ["workflow_dispatch"]: err("prepare-ego.yml must be workflow_dispatch only")
w = docs.get("gnome-version-watch.yml", {}); on = w.get(True, w.get("on"))
if set(on) != {"schedule", "workflow_dispatch"}: err("gnome-version-watch.yml triggers must be schedule and workflow_dispatch")
# prepare-ego: Shexli is optional, report only, pinned, and installed with uv (no curl | sh, no pip --user)
pe = docs.get("prepare-ego.yml", {})
steps = [st for j in pe.get("jobs", {}).values() for st in j.get("steps", [])]
sx = [st for st in steps if "shexli" in st.get("name", "").lower()]
if len(sx) != 1: err("prepare-ego.yml needs exactly one Shexli step")
else:
    st = sx[0]; run = st.get("run", "")
    if st.get("continue-on-error") is not True: err("Shexli step must have continue-on-error: true")
    if not re.search(r"shexli==\d+\.\d+\.\d+", run): err("Shexli version is not pinned")
    if "venv --python 3.12" not in run: err("Shexli must run in a uv venv with Python 3.12")
    if "sha256sum -c" not in run: err("uv download is not checksum verified")
    if re.search(r"\|\s*(ba)?sh\b", run) or "--user" in run or "pip install -g" in run: err("Shexli step installs unsafely")
    if "exit 0" not in run.splitlines()[-1]: err("Shexli step must end with exit 0 (report only)")
if not any("shexli" in str((st.get("with") or {}).get("name", "")) for st in steps): err("no shexli artifact upload")
# publish-testing: only after test and secrets, push to testing only, the one job with contents: write in ci.yml, no v* tag
pt = ci.get("jobs", {}).get("publish-testing")
if not pt: err("ci.yml lacks job publish-testing")
else:
    if sorted(pt.get("needs", [])) != ["secrets", "test"]: err("publish-testing must need exactly test and secrets")
    if "refs/heads/testing" not in str(pt.get("if", "")) or "github.event_name == 'push'" not in str(pt.get("if", "")): err("publish-testing must be limited to a push on the testing branch")
    if (pt.get("permissions") or {}) != {"contents": "write", "actions": "read"}: err("publish-testing permissions must be contents: write and actions: read")
    run = "\n".join(st.get("run", "") for st in pt.get("steps", []))
    if "release create testing" not in run or "--prerelease" not in run: err("publish-testing must create the testing prerelease")
    if "release delete testing" not in run or "--cleanup-tag" not in run: err("publish-testing must replace the old testing release")
    if re.search(r"release (create|delete) v", run) or re.search(r"v\$", run): err("publish-testing must not touch a v* tag")
    if "docker build" in run or "gnome-extensions pack" in run or "just pack" in run: err("publish-testing must not rebuild")
# release candidate stamp: full history (tags) for the count, stamped before the manifest and the upload
ts = ci["jobs"]["test"]["steps"]
names = [st.get("name", "") for st in ts]
co = [st for st in ts if "checkout" in str(st.get("uses", ""))]
if not co or str((co[0].get("with") or {}).get("fetch-depth")) != "0": err("ci.yml test job must check out with fetch-depth 0 (rc number needs the tags)")
si = [i for i, st in enumerate(ts) if "scripts/stamp-rc.sh" in st.get("run", "")]
mi = [i for i, st in enumerate(ts) if "scripts/make-manifest.sh" in st.get("run", "")]
ui = [i for i, st in enumerate(ts) if "upload-artifact" in str(st.get("uses", ""))]
if not si or not mi or not ui or not (si[0] < mi[0] < ui[0]): err("ci.yml: stamp-rc.sh must run before make-manifest.sh and the upload")
if "git commit" in str(ci) or "git push" in str(ci): err("ci.yml must never commit the rc stamp")
# the stamped zip goes through the EGO pre-flight (the dotted rc form is a valid version-name), after the stamp
pi = [i for i, st in enumerate(ts) if "scripts/ego-preflight.sh" in st.get("run", "")]
if not pi or not si or not (si[0] < pi[0] < mi[0]): err("ci.yml: the EGO pre-flight must run after stamp-rc.sh and before make-manifest.sh")
# Shexli in ci.yml: its own job (not a required check name), report only, pinned, uv venv, never fails
sj = ci["jobs"].get("shexli")
if not sj: err("ci.yml lacks the report-only shexli job")
else:
    if "needs" in sj: err("shexli job must not gate anything (no needs)")
    if any("shexli" in str(st.get("needs", "")) for st in ci["jobs"].values()): err("no job may need shexli")
    if "shexli" in str(ci["jobs"]["publish-testing"].get("needs", [])): err("publish-testing must not need shexli")
    sst = [st for st in sj.get("steps", []) if "shexli" in st.get("name", "").lower()]
    if len(sst) != 1: err("shexli job needs exactly one Shexli step")
    else:
        st = sst[0]; run = st.get("run", "")
        if st.get("continue-on-error") is not True: err("ci.yml Shexli step must have continue-on-error: true")
        if not re.search(r"shexli==\d+\.\d+\.\d+", run): err("ci.yml Shexli version is not pinned")
        if not re.search(r"tree-sitter==\d+\.\d+\.\d+", run): err("ci.yml tree-sitter is not pinned")
        if "uv\" venv" not in run and "uv venv" not in run: err("ci.yml Shexli must run in a uv venv")
        if "sha256sum -c" not in run: err("ci.yml uv download is not checksum verified")
        if re.search(r"\|\s*(ba)?sh\b", run) or "--user" in run or re.search(r"(^|\n)\s*pip3? install", run): err("ci.yml Shexli step installs unsafely")
        if "exit 0" not in run.splitlines()[-1]: err("ci.yml Shexli step must end with exit 0 (report only)")
        if "::warning" not in run: err("ci.yml Shexli step must raise a warning annotation for findings")
    if "scripts/stamp-rc.sh" not in str(sj.get("steps")): err("shexli job must analyze the stamped zip")
for jn in ("test", "secrets"):
    if (ci["jobs"][jn].get("permissions") or {}).get("contents") == "write": err("ci.yml job " + jn + " must stay read-only")
if (ci.get("permissions") or {}) != {"contents": "read"}: err("ci.yml top-level permissions must stay contents: read")
pm = docs.get("promote.yml", {})
if "testing" in str(pm.get("on", pm.get(True))): err("promote.yml must not react to testing")
# least privilege
for f, y in docs.items():
    top = y.get("permissions")
    if top is None: err(f + ": no top-level permissions")
    for jn, j in y["jobs"].items():
        p = {**(top or {}), **(j.get("permissions") or {})}
        for k in ("id-token", "attestations", "issues", "contents"):
            if p.get(k) == "write" and not (f, jn, k) in {("promote.yml", "promote", "id-token"), ("promote.yml", "promote", "attestations"), ("promote.yml", "promote", "contents"), ("ci.yml", "publish-testing", "contents"), ("gnome-version-watch.yml", "watch", "issues")}:
                err(f"{f}: job {jn} has {k}: write")
print("workflows OK" if not bad else "")
sys.exit(1 if bad else 0)
PY
rc=$?
[ $rc -eq 0 ] && pass "workflow checks" || fail "workflow checks"
finish
