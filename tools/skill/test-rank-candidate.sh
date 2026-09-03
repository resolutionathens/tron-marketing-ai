#!/usr/bin/env bash
# Regression coverage for rank-candidate.sh (MD-3047): the single implementation
# of "score one candidate by version, then install-root rank" that
# resolve-skill-dir.sh and git-pr's Step 1c ambient fallback both call, so a
# future change to how the newest complete Tron package is picked (a new
# install root, a different tie-break) only has to be made here.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
RANK="$ROOT/tools/skill/rank-candidate.sh"
DOC="$ROOT/skills/git-pr/SKILL.md"
RESOLVER_SRC="$ROOT/tools/skill/resolve-skill-dir.sh"

PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

CLAUDE_CACHE="/home/x/.claude/plugins/cache"
CLAUDE_MARKETPLACES="/home/x/.claude/plugins/marketplaces"
CODEX_CACHE="/home/x/.codex/plugins/cache"
CODEX_MARKETPLACES="/home/x/.codex/plugins/marketplaces"

score() {
  bash "$RANK" "$1" "$CLAUDE_CACHE" "$CLAUDE_MARKETPLACES" "$CODEX_CACHE" "$CODEX_MARKETPLACES"
}

got="$(score "$CLAUDE_CACHE/tron-engineer/0.35.10")"
[ "$got" = "$(printf '%s\t%s\t%s' 00000.00035.00010 2 "$CLAUDE_CACHE/tron-engineer/0.35.10")" ] \
  || fail "cache candidate scored '$got'"
pass "a Claude cache candidate gets rank 2 and a zero-padded version key"

got="$(score "$CLAUDE_MARKETPLACES/tron/0.35.10")"
[ "$got" = "$(printf '%s\t%s\t%s' 00000.00035.00010 3 "$CLAUDE_MARKETPLACES/tron/0.35.10")" ] \
  || fail "marketplace candidate scored '$got'"
pass "a Claude marketplace candidate gets rank 3 (outranks cache on a version tie)"

got="$(score "/home/x/Library/Application Support/tron-os/tron-releases/versions/0.30.0")"
[ "$got" = "$(printf '%s\t%s\t%s' 00000.00030.00000 1 "/home/x/Library/Application Support/tron-os/tron-releases/versions/0.30.0")" ] \
  || fail "release-store candidate scored '$got'"
pass "a release-store candidate gets rank 1 (loses to cache and marketplace)"

got="$(score "$CLAUDE_CACHE/tron-engineer/not-a-version")"
[ "$got" = "$(printf '%s\t%s\t%s' 00000.00000.00000 2 "$CLAUDE_CACHE/tron-engineer/not-a-version")" ] \
  || fail "unversioned candidate scored '$got'"
pass "a candidate with no parsable version defaults to 0.0.0"

set +e
bash "$RANK" 2>/dev/null
status=$?
set -e
[ "$status" -ne 0 ] || fail "missing arguments unexpectedly succeeded"
pass "missing arguments fail loudly"

# --- both callers use this one script, not their own copy of the logic ----
grep -qF 'rank-candidate.sh' "$RESOLVER_SRC" \
  || fail "resolve-skill-dir.sh no longer calls the shared rank-candidate.sh"
grep -qF 'tools/skill/rank-candidate.sh' "$DOC" \
  || fail "git-pr/SKILL.md Step 1c no longer calls the shared rank-candidate.sh"
grep -qE 'awk -F\.|sed -nE .s/\^v\?' "$RESOLVER_SRC" \
  && fail "resolve-skill-dir.sh still reimplements version scoring inline instead of delegating"
grep -qE 'awk -F\.|sed -nE .s/\^v\?' "$DOC" \
  && fail "git-pr/SKILL.md Step 1c still reimplements version scoring inline instead of delegating"
pass "resolve-skill-dir.sh and git-pr Step 1c both delegate scoring to rank-candidate.sh"

echo "rank-candidate regression: $PASS passed"
