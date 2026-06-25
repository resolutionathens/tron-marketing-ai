#!/usr/bin/env bash
# Self-test for the evaluation harness. Offline only: exercises the deterministic
# runner with pass/fail fixtures and the judge runner via --dry-run (no model
# calls). Run after editing evaluate.mjs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
RUN="node $HERE/evaluate.mjs"
FIX="tools/evaluate/fixtures"

pass=0 fail=0
check() { # desc, expected_exit, actual_exit
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1));
  else echo "  ✗ $1 (expected exit $2, got $3)"; fail=$((fail+1)); fi
}

cd "$REPO_ROOT"

# 1) A passing deterministic fixture → exit 0.
set +e
$RUN "$FIX/det-pass.json" --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "passing fixture exits 0" 0 "$rc"

# 2) A failing deterministic fixture → exit 1.
set +e
$RUN "$FIX/det-fail.json" --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "failing fixture exits 1" 1 "$rc"

# 3) Mixed fixtures dir → at least one fail → exit 1.
set +e
$RUN "$FIX" --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "mixed fixtures dir exits 1" 1 "$rc"

# 4) --dry-run never executes or fails, even over the failing fixture → exit 0.
set +e
$RUN "$FIX" --dry-run >/dev/null 2>&1; rc=$?
set -e
check "dry-run exits 0" 0 "$rc"

# 5) Real co-located + central deterministic scenarios all pass → exit 0.
set +e
$RUN --deterministic-only >/dev/null 2>&1; rc=$?
set -e
check "repo deterministic scenarios pass" 0 "$rc"

# 6) JSON output is valid and reports the failing fixture.
set +e
out="$($RUN "$FIX" --deterministic-only --json 2>/dev/null)"
set -e
echo "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(j.failed<1)process.exit(1)})'
check "json summary reports a failure" 0 "$?"

# 7) --help exits 0.
set +e
$RUN --help >/dev/null 2>&1; rc=$?
set -e
check "help exits 0" 0 "$rc"

echo
if [ "$fail" -eq 0 ]; then echo "✅ evaluate harness smoke PASSED ($pass checks)"; exit 0;
else echo "❌ evaluate harness smoke FAILED ($fail of $((pass+fail)))"; exit 1; fi
