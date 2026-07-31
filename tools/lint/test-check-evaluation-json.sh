#!/usr/bin/env bash
# Smoke for check-evaluation-json.sh: valid scenarios pass, a malformed scenario
# or golden run fails with its own path named, and an empty scan is reported as
# a failure rather than a clean pass.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-evaluation-json.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/evaluation-json-lint.XXXXXX")"
LOG="$(mktemp "${TMPDIR:-/tmp}/evaluation-json-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'trash "$FIXTURE" "$LOG"' EXIT

reset_fixture() {
  [ ! -e "$FIXTURE/evaluations" ] || trash "$FIXTURE/evaluations"
  [ ! -e "$FIXTURE/skills" ] || trash "$FIXTURE/skills"
  mkdir -p "$FIXTURE/evaluations/git-flow" "$FIXTURE/skills/example/example"
  printf '%s\n' '{"query":"commit this","expected_behavior":["commits atomically"]}' \
    >"$FIXTURE/evaluations/git-flow/valid.json"
  printf '%s\n' '{"query":"golden","expected_behavior":["runs the script"]}' \
    >"$FIXTURE/skills/example/example/golden.json"
}

# expect_fail <needle> <label>
expect_fail() {
  if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
    fail "$2: lint should have failed"
  fi
  rg -q -- "$1" "$LOG" || { cat "$LOG" >&2; fail "$2: failure should report \"$1\""; }
  pass "$2"
}

bash "$SCRIPT" "$REPO_ROOT" >"$LOG" 2>&1 || { cat "$LOG" >&2; fail "should pass on the real repo"; }
rg -q 'check-evaluation-json: OK \(72 evaluation JSON files parsed\)' "$LOG" \
  || { cat "$LOG" >&2; fail "should report the exact file count for the real repo"; }
pass "passes on the real repo and counts all 72 scenario/golden files"

reset_fixture
bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1 || { cat "$LOG" >&2; fail "should pass on a valid fixture"; }
rg -q 'check-evaluation-json: OK \(2 evaluation JSON files parsed\)' "$LOG" \
  || { cat "$LOG" >&2; fail "should count both the scenario and the golden run"; }
pass "passes on a valid fixture and counts both file locations"

reset_fixture
printf '%s\n' '{"query":"commit this",}' >"$FIXTURE/evaluations/git-flow/valid.json"
expect_fail 'FAIL evaluations/git-flow/valid\.json' "rejects a malformed evaluation scenario"
rg -q 'check-evaluation-json: FAILED' "$LOG" || fail "malformed scenario should identify the lint"

reset_fixture
printf '%s\n' 'not json at all' >"$FIXTURE/skills/example/example/golden.json"
expect_fail 'FAIL skills/example/example/golden\.json' "rejects a malformed co-located golden run"

reset_fixture
trash "$FIXTURE/evaluations" "$FIXTURE/skills"
expect_fail 'found no evaluation JSON to scan' "fails loudly rather than reporting a false green on an empty scan"

echo "check-evaluation-json smoke: $PASS assertions passed"
