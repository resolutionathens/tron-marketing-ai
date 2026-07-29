#!/usr/bin/env bash
# Smoke for check-reference-contents.sh: short docs are exempt, a long doc with
# a contents list at the top passes, and a long doc that has none — or has one
# pushed past the truncation window — fails with the offending path and its
# line count.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-reference-contents.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/reference-contents-lint.XXXXXX")"
LOG="$(mktemp "${TMPDIR:-/tmp}/reference-contents-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'trash "$FIXTURE" "$LOG"' EXIT

# body <count> — emit <count> filler lines.
body() {
  i=0
  while [ "$i" -lt "$1" ]; do
    echo "filler line $i"
    i=$((i + 1))
  done
}

reset_fixture() {
  [ ! -e "$FIXTURE/skills" ] || trash "$FIXTURE/skills"
  [ ! -e "$FIXTURE/tools" ] || trash "$FIXTURE/tools"
  mkdir -p "$FIXTURE/skills/example/reference" "$FIXTURE/tools/example"
  # A compliant long doc, so every case below still has something to scan.
  {
    echo "# Long and compliant"
    echo
    echo "## Contents"
    echo
    echo "- [Section](#section)"
    echo
    echo "## Section"
    body 120
  } >"$FIXTURE/tools/example/compliant.md"
}

# expect_fail <needle> <label>
expect_fail() {
  if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
    fail "$2: lint should have failed"
  fi
  rg -q -- "$1" "$LOG" || { cat "$LOG" >&2; fail "$2: failure should report \"$1\""; }
  rg -q 'check-reference-contents: FAILED' "$LOG" || fail "$2: failure should identify the lint"
  pass "$2"
}

bash "$SCRIPT" "$REPO_ROOT" >/dev/null || fail "should pass on the real repo"
pass "passes clean on the real repo"

reset_fixture
# Exactly 100 lines — the threshold itself, which must stay exempt.
{ echo "# Short reference"; echo; echo "## Only section"; body 97; } \
  >"$FIXTURE/skills/example/reference/short.md"
[ "$(wc -l <"$FIXTURE/skills/example/reference/short.md" | tr -d '[:space:]')" = 100 ] \
  || fail "fixture should be exactly 100 lines to pin the threshold"
bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1 || { cat "$LOG" >&2; fail "should pass on compliant + short docs"; }
rg -q 'check-reference-contents: OK \(1 of 2 reference docs over 100 lines\)' "$LOG" \
  || { cat "$LOG" >&2; fail "should scan 2 docs and check only the long one"; }
pass "exempts a doc of exactly 100 lines and checks only the longer one"

reset_fixture
{ echo "# Long and bare"; echo; echo "## Section"; body 120; } \
  >"$FIXTURE/skills/example/reference/bare.md"
expect_fail 'FAIL skills/example/reference/bare\.md: 123 lines and no "## Contents" list in the first 20' \
  "rejects a long reference doc with no contents list"

reset_fixture
{ echo "# Contents too far down"; body 25; echo "## Contents"; echo; echo "- [Section](#section)"; body 100; } \
  >"$FIXTURE/tools/example/late.md"
expect_fail 'FAIL tools/example/late\.md: 129 lines and no "## Contents" list in the first 20' \
  "rejects a contents list pushed past the truncation window"

reset_fixture
trash "$FIXTURE/tools/example/compliant.md"
if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
  fail "an empty scan should not report a false green"
fi
rg -q 'found no reference docs to scan' "$LOG" || { cat "$LOG" >&2; fail "empty scan should say so"; }
pass "fails loudly rather than reporting a false green when nothing is scanned"

echo "check-reference-contents smoke: $PASS assertions passed"
