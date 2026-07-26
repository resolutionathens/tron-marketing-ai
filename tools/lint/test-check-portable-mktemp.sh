#!/usr/bin/env bash
# Smoke for check-portable-mktemp.sh: valid trailing-X templates pass while a
# suffixed template fails, preventing the BSD mktemp portability regression.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-portable-mktemp.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/portable-mktemp-lint.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'trash "$FIXTURE"' EXIT

write_fixture() {
  mkdir -p "$FIXTURE/skills/example" "$FIXTURE/tools/example"
  printf '%s\n' "$2" >"$FIXTURE/$1"
}

reset_fixture() {
  [ ! -e "$FIXTURE/skills" ] || trash "$FIXTURE/skills"
  [ ! -e "$FIXTURE/tools" ] || trash "$FIXTURE/tools"
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
write_fixture 'tools/example/example.sh' "BODY=\"\$(mktemp \"\${TMPDIR:-/tmp}/body.$xrun$bad_suffix\")\""
if bash "$SCRIPT" "$FIXTURE" >/tmp/portable-mktemp-smoke-out.$$ 2>&1; then
  fail "should reject a suffixed template"
fi
rg -q 'body\.XXXXXX\.md' /tmp/portable-mktemp-smoke-out.$$ || fail "failure should identify the bad template"
rg -q 'check-portable-mktemp: FAILED' /tmp/portable-mktemp-smoke-out.$$ || fail "failure should identify the lint"
pass "rejects a suffixed template"

echo "check-portable-mktemp smoke: $PASS assertions passed"
