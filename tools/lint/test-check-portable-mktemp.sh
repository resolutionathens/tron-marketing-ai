#!/usr/bin/env bash
# Smoke for check-portable-mktemp.sh: valid trailing-X templates pass while a
# suffixed template fails, preventing the BSD mktemp portability regression.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-portable-mktemp.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/portable-mktemp-lint.XXXXXX")"
LOG="$(mktemp "${TMPDIR:-/tmp}/portable-mktemp-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'trash "$FIXTURE" "$LOG"' EXIT

write_fixture() {
  mkdir -p "$FIXTURE/skills/example" "$FIXTURE/tools/example" "$FIXTURE/hooks"
  printf '%s\n' "$2" >"$FIXTURE/$1"
}

reset_fixture() {
  [ ! -e "$FIXTURE/skills" ] || trash "$FIXTURE/skills"
  [ ! -e "$FIXTURE/tools" ] || trash "$FIXTURE/tools"
  [ ! -e "$FIXTURE/hooks" ] || trash "$FIXTURE/hooks"
}

xrun='XXXXXX'

bash "$SCRIPT" "$REPO_ROOT" >/dev/null || fail "should pass on the real repo"
pass "passes clean on the real repo"

reset_fixture
write_fixture 'skills/example/SKILL.md' "BODY=\"\$(mktemp \"\${TMPDIR:-/tmp}/body.$xrun\")\""
bash "$SCRIPT" "$FIXTURE" >/dev/null || fail "should accept a trailing-X template"
pass "accepts a trailing-X template"

reset_fixture
bad_suffix='.md'
write_fixture 'tools/example/example.py' "body = mktemp('/tmp/body.$xrun$bad_suffix')"
write_fixture 'hooks/example-hook' "BODY=\"\$(mktemp \"\${TMPDIR:-/tmp}/hook.$xrun$bad_suffix\")\""
if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
  fail "should reject a suffixed template"
fi
rg -q 'body\.XXXXXX\.md' "$LOG" || fail "failure should identify the bad Python template"
rg -q 'hook\.XXXXXX\.md' "$LOG" || fail "failure should identify the bad hook template"
rg -q 'check-portable-mktemp: FAILED' "$LOG" || fail "failure should identify the lint"
pass "rejects suffixed templates in Python and hooks"

echo "check-portable-mktemp smoke: $PASS assertions passed"
