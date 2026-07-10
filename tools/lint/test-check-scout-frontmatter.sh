#!/usr/bin/env bash
# Smoke for check-scout-frontmatter.sh: confirms it passes on the real repo,
# and — the actual regression tests — confirms it catches each shape
# parseScoutMeta() in tron-os silently tolerates: an invalid category, an
# inputs entry missing a label, and a surface: true skill missing its
# display copy. Also confirms a valid surface: true block passes.
#
#   bash tools/lint/test-check-scout-frontmatter.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-scout-frontmatter.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/scout-lint-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$FIXTURE"; exit 1; }
trap 'rm -rf "$FIXTURE"' EXIT

echo "check-scout-frontmatter smoke: fixture=$FIXTURE"

write_skill() {
  local name="$1" body="$2"
  mkdir -p "$FIXTURE/skills/$name"
  printf '%s' "$body" >"$FIXTURE/skills/$name/SKILL.md"
}

reset_fixture() {
  rm -rf "$FIXTURE/skills"
  mkdir -p "$FIXTURE/skills"
}

# --- real repo passes clean --------------------------------------------------
bash "$SCRIPT" "$REPO_ROOT" >/dev/null || fail "check-scout-frontmatter.sh should pass on the real repo"
pass "passes clean on the real repo"

# --- a valid surface: true block passes --------------------------------------
reset_fixture
write_skill valid-skill '---
name: valid-skill
model: sonnet
effort: medium
description: "A valid skill."
scout:
  surface: true
  title: "Do the thing"
  blurb: "Does the thing well."
  when: "When you need the thing done."
  category: qa
  effects: [report]
  inputs:
    - key: target
      label: "Target"
      type: text
      required: true
---

# /valid-skill
'
bash "$SCRIPT" "$FIXTURE" >/dev/null || fail "should pass a well-formed surface: true block"
pass "passes a well-formed surface: true block"

# --- invalid category fails ---------------------------------------------------
reset_fixture
write_skill bad-category '---
name: bad-category
scout:
  surface: true
  title: "Do the thing"
  blurb: "Does the thing well."
  when: "When you need the thing done."
  category: sales
  effects: [report]
---
'
if bash "$SCRIPT" "$FIXTURE" >/tmp/scout-smoke-out.$$ 2>&1; then
  fail "should have failed an invalid category"
fi
grep -q "FAIL bad-category" /tmp/scout-smoke-out.$$ || fail "failure output should name the broken skill"
grep -q "category 'sales'" /tmp/scout-smoke-out.$$ || fail "failure output should name the bad category value"
pass "catches an invalid category"

# --- inputs entry missing a label fails ---------------------------------------
reset_fixture
write_skill missing-label '---
name: missing-label
scout:
  surface: developer
  effects: [local]
  inputs:
    - key: target
      type: text
      required: true
---
'
if bash "$SCRIPT" "$FIXTURE" >/tmp/scout-smoke-out.$$ 2>&1; then
  fail "should have failed an inputs entry missing a label"
fi
grep -q "FAIL missing-label" /tmp/scout-smoke-out.$$ || fail "failure output should name the broken skill"
grep -q "missing a non-empty label" /tmp/scout-smoke-out.$$ || fail "failure output should call out the missing label"
pass "catches an inputs entry missing a label"

# --- surface: true missing display copy fails ---------------------------------
reset_fixture
write_skill missing-copy '---
name: missing-copy
scout:
  surface: true
  effects: [report]
---
'
if bash "$SCRIPT" "$FIXTURE" >/tmp/scout-smoke-out.$$ 2>&1; then
  fail "should have failed a surface: true skill missing display copy"
fi
grep -q "FAIL missing-copy" /tmp/scout-smoke-out.$$ || fail "failure output should name the broken skill"
grep -q "requires a non-empty title" /tmp/scout-smoke-out.$$ || fail "failure output should call out the missing title"
grep -q "requires a non-empty category" /tmp/scout-smoke-out.$$ || fail "failure output should call out the missing category"
pass "catches a surface: true skill missing display copy"

# --- bad surface value fails ---------------------------------------------------
reset_fixture
write_skill bad-surface '---
name: bad-surface
scout:
  surface: yes
  effects: [local]
---
'
if bash "$SCRIPT" "$FIXTURE" >/tmp/scout-smoke-out.$$ 2>&1; then
  fail "should have failed a surface value outside true | developer | false"
fi
grep -q "FAIL bad-surface" /tmp/scout-smoke-out.$$ || fail "failure output should name the broken skill"
grep -q "surface 'yes'" /tmp/scout-smoke-out.$$ || fail "failure output should name the bad surface value"
pass "catches a surface value outside true | developer | false"

# --- bad effects entry fails ----------------------------------------------------
reset_fixture
write_skill bad-effects '---
name: bad-effects
scout:
  surface: developer
  effects: [deploy]
---
'
if bash "$SCRIPT" "$FIXTURE" >/tmp/scout-smoke-out.$$ 2>&1; then
  fail "should have failed an invalid effects entry"
fi
grep -q "FAIL bad-effects" /tmp/scout-smoke-out.$$ || fail "failure output should name the broken skill"
grep -q "effects entry 'deploy'" /tmp/scout-smoke-out.$$ || fail "failure output should name the bad effects value"
pass "catches an invalid effects entry"

# --- bad inputs type falls back silently in tron-os, so this lint catches it --
reset_fixture
write_skill bad-type '---
name: bad-type
scout:
  surface: developer
  effects: [local]
  inputs:
    - key: target
      label: "Target"
      type: number
---
'
if bash "$SCRIPT" "$FIXTURE" >/tmp/scout-smoke-out.$$ 2>&1; then
  fail "should have failed an invalid inputs type"
fi
grep -q "FAIL bad-type" /tmp/scout-smoke-out.$$ || fail "failure output should name the broken skill"
grep -q "type 'number'" /tmp/scout-smoke-out.$$ || fail "failure output should name the bad type value"
pass "catches an invalid inputs type"

# --- a skill with no scout: block at all is skipped, not flagged ---------------
reset_fixture
write_skill no-scout '---
name: no-scout
description: "No scout block yet."
---
'
bash "$SCRIPT" "$FIXTURE" >/dev/null || fail "should not fail a skill with no scout: block"
pass "skips a skill with no scout: block"

# --- CCAL-2092: effects: [] must not crash the linter under set -u -----------
# `effects: []` parses to a non-empty effects_raw string ("[]") but strips down to an empty
# `effs` array — an unguarded "${effs[@]}" there throws "unbound variable" on macOS system
# bash 3.2 (bash < 4.4). An empty effects list isn't itself an error (only surface: true
# requires a non-empty one), so this should pass clean, not crash.
reset_fixture
write_skill empty-effects '---
name: empty-effects
scout:
  surface: developer
  effects: []
---
'
bash "$SCRIPT" "$FIXTURE" >/dev/null || fail "effects: [] should not crash the linter (CCAL-2092 effs[@] regression)"
pass "effects: [] parses to an empty effs[@] safely under set -u (CCAL-2092)"

rm -f /tmp/scout-smoke-out.$$
echo "check-scout-frontmatter smoke: $PASS passed"
