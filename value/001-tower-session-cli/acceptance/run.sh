#!/usr/bin/env bash
# Acceptance runner for 001-tower-session-cli.
# Runs the e2e bats file whose @test names equal the scenario names in
# scenarios.feature, and writes results.json in the form run-acceptance.sh
# expects (VF_RESULT_DIR). The TAP output is kept as evidence.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="${VF_RESULT_DIR:-$HERE/results/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT/evidence"
TAP="$OUT/evidence/bats.tap"
(cd "$ROOT" && bats --formatter tap tests/e2e/test_acceptance_001.bats) >"$TAP" 2>&1
rc=$?
python3 - "$HERE/scenarios.feature" "$TAP" "$OUT/results.json" "$(basename "$OUT")" <<'PY'
import json, re, sys
feature, tap, out, run = sys.argv[1:5]
tags = {}
pending = []
for line in open(feature, encoding="utf-8"):
    s = line.strip()
    if s.startswith("@"):
        pending += s.split()
    elif s.startswith("シナリオ"):
        name = s.split(":", 1)[1].strip() if ":" in s else s.split("：", 1)[1].strip()
        tags[name] = pending
        pending = []
status = {}
for line in open(tap, encoding="utf-8"):
    m = re.match(r"^(ok|not ok) \d+ (.*?)(?: # skip.*)?$", line.rstrip())
    if m:
        status[m.group(2).strip()] = "pass" if m.group(1) == "ok" else "fail"
scen = []
for name, t in tags.items():
    scen.append({
        "name": name,
        "status": status.get(name, "fail"),
        "requirements": [x[1:] for x in t if x.startswith("@REQ-")],
        "userflow": next((x[1:] for x in t if x.startswith("@UF-")), ""),
    })
    if name not in status:
        print(f"NO TEST FOR SCENARIO: {name}", file=sys.stderr)
json.dump({"run": run, "runner": "bats tests/e2e/test_acceptance_001.bats", "scenarios": scen},
          open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
fails = [s["name"] for s in scen if s["status"] != "pass"]
print(f"scenarios: {len(scen)} pass: {len(scen)-len(fails)} fail: {len(fails)}")
for f in fails: print(f"  FAIL {f}")
sys.exit(1 if fails else 0)
PY
PYRC=$?
[[ $rc -eq 0 && $PYRC -eq 0 ]]
