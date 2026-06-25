#!/usr/bin/env bash
# Smoke for gh.sh. The four subcommands all hit the live GitHub API and need a
# real authed `gh`, so their happy paths aren't asserted here. What IS testable
# offline is the usage/error contract: missing required flags exit 2, an unknown
# subcommand exits 2, a bad --method is rejected, and help prints the contract.
# That covers the dispatch + flag-parsing surface — the part most likely to
# regress on edits.
#
#   bash skills/gh/scripts/test-gh.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/gh.sh"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
has() { grep -q "$2" <<<"$1" || fail "$3 — got: $1"; }

# Run the script, capture exit code without tripping set -e.
rc_of() { local rc=0; bash "$SCRIPT" "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

if ! command -v gh >/dev/null 2>&1; then
  echo "gh smoke: SKIPPED — the gh CLI is not on PATH (install: brew install gh)"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "gh smoke: SKIPPED — jq is not on PATH; gh.sh hard-requires it (install: brew install jq)"
  exit 0
fi

echo "gh smoke: script=$SCRIPT"

# --- usage / error contract --------------------------------------------------
[[ "$(rc_of bogus-cmd)" == 2 ]] || fail "unknown subcommand should exit 2"
pass "unknown subcommand → exit 2"

[[ "$(rc_of gh-view-pr)" == 2 ]] || fail "gh-view-pr without --number should exit 2"
pass "gh-view-pr without --number → exit 2"

[[ "$(rc_of gh-merge-pr)" == 2 ]] || fail "gh-merge-pr without --number should exit 2"
pass "gh-merge-pr without --number → exit 2"

[[ "$(rc_of gh-merge-pr --number 1 --method bogus)" == 2 ]] || fail "bad --method should exit 2"
pass "gh-merge-pr --method bogus → exit 2"

[[ "$(rc_of gh-comment --number 1)" == 2 ]] || fail "gh-comment without --body should exit 2"
pass "gh-comment without --body → exit 2"

[[ "$(rc_of gh-comment --body hi)" == 2 ]] || fail "gh-comment without --number should exit 2"
pass "gh-comment without --number → exit 2"

[[ "$(rc_of gh-view-pr --bogus-flag x)" == 2 ]] || fail "unknown flag should exit 2"
pass "unknown flag → exit 2"

# --- help --------------------------------------------------------------------
O="$(bash "$SCRIPT" help)"
has "$O" 'gh.sh <subcommand>' "help prints usage"
has "$O" 'gh-view-pr' "help lists gh-view-pr"
has "$O" 'gh-list-issues' "help lists gh-list-issues"
has "$O" 'gh-merge-pr' "help lists gh-merge-pr"
has "$O" 'gh-comment' "help lists gh-comment"
pass "help → prints usage listing all four subcommands (exit 0)"

echo ""
echo "✅ gh smoke PASSED ($PASS checks)"
