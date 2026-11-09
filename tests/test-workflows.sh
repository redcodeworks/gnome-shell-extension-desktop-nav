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
    if "pull_request" in (on if isinstance(on, dict) else {}) or "pull_request_target" in (on if isinstance(on, dict) else {}):
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
# least privilege
for f, y in docs.items():
    top = y.get("permissions")
    if top is None: err(f + ": no top-level permissions")
    for jn, j in y["jobs"].items():
        p = {**(top or {}), **(j.get("permissions") or {})}
        for k in ("id-token", "attestations", "issues", "contents"):
            if p.get(k) == "write" and not (f, jn, k) in {("promote.yml", "promote", "id-token"), ("promote.yml", "promote", "attestations"), ("promote.yml", "promote", "contents"), ("gnome-version-watch.yml", "watch", "issues")}:
                err(f"{f}: job {jn} has {k}: write")
print("workflows OK" if not bad else "")
sys.exit(1 if bad else 0)
PY
rc=$?
[ $rc -eq 0 ] && pass "workflow checks" || fail "workflow checks"
finish
