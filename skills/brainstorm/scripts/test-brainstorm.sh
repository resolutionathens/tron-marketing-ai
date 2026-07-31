#!/usr/bin/env bash
# Smoke for brainstorm.sh. Fully offline: slug derivation, the save skeleton
# (front-matter stamping, fence-stripping, no-clobber + --force), and the
# usage/error contract.
#
#   bash skills/brainstorm/scripts/test-brainstorm.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/brainstorm.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/brainstorm-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -qF "$2" <<<"$1" || fail "$3 — got: $1"; }
hasf() { grep -qF "$2" "$1" || fail "$3"; }

echo "brainstorm smoke: root=$ROOT"

# --- slug (pure) -------------------------------------------------------------
O="$(bash "$SCRIPT" slug 'Back-to-School Facility Prep!')"
[[ "$O" == "back-to-school-facility-prep" ]] || fail "slug should normalize (got: $O)"
pass "slug → lowercased, hyphenated, trimmed"

O="$(bash "$SCRIPT" slug '  Energy   Rebates  ')"
[[ "$O" == "energy-rebates" ]] || fail "slug should collapse whitespace (got: $O)"
pass "slug → collapses runs and trims"

# --- save: skeleton ----------------------------------------------------------
OUT="$ROOT/note.md"
P="$(bash "$SCRIPT" save 'Summer Maintenance Campaign' --audience 'K-12 facilities director' --format campaign --out "$OUT")"
[[ "$P" == "$OUT" ]] || fail "save should print the written path (got: $P)"
[[ -f "$OUT" ]] || fail "save should write the file"
pass "save → writes file and prints its path"

hasf "$OUT" "created: $(date +%F)" "front-matter created date stamped"
hasf "$OUT" "audience: K-12 facilities director" "audience stamped"
hasf "$OUT" "format: campaign" "format stamped"
hasf "$OUT" "# Ideation Note — Summer Maintenance Campaign" "title stamped"
hasf "$OUT" "## Risks & Constraints" "body sections present"
pass "save → stamps front-matter and keeps the body sections"

# the markdown code fences from the template must be stripped out
FENCE='```'
grep -qF "$FENCE" "$OUT" && fail 'save should strip the template code fences'
pass "save → strips the template code fences"

# --- save: defaults + no-clobber --------------------------------------------
DEF="$(bash "$SCRIPT" save 'Defaults Only' --out "$ROOT/def.md")"
hasf "$DEF" "status: ideation" "default save keeps status front-matter"
pass "save → works without --audience/--format (placeholders kept)"

rc=0; bash "$SCRIPT" save 'Defaults Only' --out "$ROOT/def.md" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || fail "second save without --force should refuse (rc 1, got $rc)"
pass "save → refuses to clobber existing file (exit 1)"

bash "$SCRIPT" save 'Defaults Only' --out "$ROOT/def.md" --force >/dev/null 2>&1 || fail "--force should overwrite"
pass "save --force → overwrites"

# --- usage / error contract --------------------------------------------------
rc=0; bash "$SCRIPT" save 'Missing destination' >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "save without --out should exit 2 (got $rc)"
pass "save without --out → exit 2"

rc=0; bash "$SCRIPT" save >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "save without name should exit 2 (got $rc)"
pass "save with no name → exit 2"

rc=0; bash "$SCRIPT" bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "unknown subcommand should exit 2 (got $rc)"
pass "unknown subcommand → exit 2"

echo ""
echo "✅ brainstorm smoke PASSED ($PASS checks)"
