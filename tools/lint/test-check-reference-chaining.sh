#!/usr/bin/env bash
# Smoke for check-reference-chaining.sh: links to shared tools/ prose and to
# root-level repo docs pass, a link to a sibling or cross-skill reference doc
# fails with the resolved path, and example links inside fenced code blocks are
# not links at all.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-reference-chaining.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/reference-chaining-lint.XXXXXX")"
LOG="$(mktemp "${TMPDIR:-/tmp}/reference-chaining-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
trap 'trash "$FIXTURE" "$LOG"' EXIT

reset_fixture() {
  [ ! -e "$FIXTURE/skills" ] || trash "$FIXTURE/skills"
  [ ! -e "$FIXTURE/tools" ] || trash "$FIXTURE/tools"
  mkdir -p "$FIXTURE/skills/alpha/reference" "$FIXTURE/skills/beta/reference" \
    "$FIXTURE/tools/image"
  : >"$FIXTURE/tools/image/images-to-imagekit.md"
  : >"$FIXTURE/WORKER_CONTRACT.md"
  # A compliant doc, so every case below still has something to scan.
  {
    echo "# Compliant"
    echo
    echo "See [the pipeline](../../../tools/image/images-to-imagekit.md)."
  } >"$FIXTURE/skills/alpha/reference/images.md"
}

# expect_fail <needle> <label>
expect_fail() {
  if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
    fail "$2: lint should have failed"
  fi
  rg -q -- "$1" "$LOG" || { cat "$LOG" >&2; fail "$2: failure should report \"$1\""; }
  rg -q 'check-reference-chaining: FAILED' "$LOG" || fail "$2: failure should identify the lint"
  pass "$2"
}

bash "$SCRIPT" "$REPO_ROOT" >/dev/null || fail "should pass on the real repo"
pass "passes clean on the real repo"

# The exact shared-prose links MD-2541 decided are legitimate must stay quiet.
reset_fixture
{
  echo "# Shared prose and root docs"
  echo
  echo "Convert and upload per [\`tools/image/images-to-imagekit.md\`](../../../tools/image/images-to-imagekit.md)."
  echo "A hard gate, see [WORKER_CONTRACT.md](../../../WORKER_CONTRACT.md)."
} >"$FIXTURE/skills/beta/reference/source-types.md"
bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1 || { cat "$LOG" >&2; fail "shared prose and root docs should pass"; }
rg -q 'check-reference-chaining: OK \(3 markdown links across 2 reference docs\)' "$LOG" \
  || { cat "$LOG" >&2; fail "should count 3 links across 2 docs"; }
pass "allows links to shared tools/ prose and to a root-level repo doc"

# The violation that motivated the ticket: a bare sibling filename that in fact
# lives in a different skill's reference dir, so the link is also broken.
reset_fixture
{
  echo "# Chains to a sibling filename"
  echo
  echo "Per [reference/existing-page-search.md](existing-page-search.md)."
} >"$FIXTURE/skills/beta/reference/description-template.md"
expect_fail 'FAIL skills/beta/reference/description-template\.md:3 chains to the reference doc `skills/beta/reference/existing-page-search\.md`' \
  "rejects a chain to a sibling reference filename even when the target does not exist"

reset_fixture
{
  echo "# Chains across skills"
  echo
  echo "See [alpha's images doc](../../alpha/reference/images.md)."
} >"$FIXTURE/skills/beta/reference/cross.md"
expect_fail 'FAIL skills/beta/reference/cross\.md:3 chains to the reference doc `skills/alpha/reference/images\.md`' \
  "rejects a chain into another skill's reference dir"

reset_fixture
{
  echo "# Neither tools/ prose nor a root doc"
  echo
  echo "See [alpha's skill body](../../alpha/SKILL.md)."
} >"$FIXTURE/skills/beta/reference/skill-link.md"
expect_fail 'FAIL skills/beta/reference/skill-link\.md:3 links `skills/alpha/SKILL\.md`, which is not an allowed target' \
  "rejects a link to another skill's SKILL.md, which the closed allowlist excludes"

reset_fixture
{
  echo "# Walks out of the repo"
  echo
  echo "See [somewhere else](../../../../elsewhere/notes.md)."
} >"$FIXTURE/skills/beta/reference/escape.md"
expect_fail 'FAIL skills/beta/reference/escape\.md:3 links `\.\./\.\./\.\./\.\./elsewhere/notes\.md`, which walks above the repo root' \
  "rejects a link that walks above the repo root"

# tools/voice/facilitron-voice.md carries a copy-me snippet of its own path; the
# same shape in a reference doc must not be read as a link.
reset_fixture
{
  echo "# Fenced examples are not links"
  echo
  echo 'Copy this into a SKILL.md:'
  echo
  echo '````markdown'
  echo "Per [reference/existing-page-search.md](existing-page-search.md)."
  echo '```'
  echo "See [a sibling](../../alpha/reference/images.md)."
  echo '```'
  echo '````'
} >"$FIXTURE/skills/beta/reference/fenced.md"
bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1 \
  || { cat "$LOG" >&2; fail "links inside fenced blocks should not be checked"; }
rg -q 'check-reference-chaining: OK \(1 markdown links across 2 reference docs\)' "$LOG" \
  || { cat "$LOG" >&2; fail "fenced links should not be counted"; }
pass "ignores links inside fenced code blocks, including a nested fence"

reset_fixture
{
  echo "# Non-paths and non-markdown targets"
  echo
  echo "Read [the docs](https://example.com/reference/existing-page-search.md)."
  echo "Mail [us](mailto:eng@example.com)."
  echo "Jump to [a section](#contents)."
  echo "Run [the script](existing-page-search.sh)."
} >"$FIXTURE/skills/beta/reference/non-paths.md"
bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1 || { cat "$LOG" >&2; fail "non-paths should be skipped"; }
rg -q 'check-reference-chaining: OK \(1 markdown links across 2 reference docs\)' "$LOG" \
  || { cat "$LOG" >&2; fail "absolute URLs, mailto, anchors, and non-.md targets should not count"; }
pass "skips absolute URLs, mailto:, bare anchors, and non-markdown targets"

reset_fixture
{
  echo "# Two links on one line"
  echo
  echo "Both [one](existing-page-search.md) and [two](source-types.md) are chains."
} >"$FIXTURE/skills/beta/reference/two-per-line.md"
if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
  fail "two chains on one line should fail"
fi
[ "$(rg -c 'chains to the reference doc' "$LOG")" = 2 ] \
  || { cat "$LOG" >&2; fail "both links on a single line should be reported"; }
pass "reports every link on a line, not just the first"

reset_fixture
trash "$FIXTURE/skills/alpha/reference/images.md"
if bash "$SCRIPT" "$FIXTURE" >"$LOG" 2>&1; then
  fail "an empty scan should not report a false green"
fi
rg -q 'found no reference docs to scan' "$LOG" || { cat "$LOG" >&2; fail "empty scan should say so"; }
pass "fails loudly rather than reporting a false green when nothing is scanned"

echo "check-reference-chaining smoke: $PASS assertions passed"
