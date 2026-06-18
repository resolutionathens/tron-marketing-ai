#!/usr/bin/env bash
# Smoke for start-ticket's deterministic spine. The wt/acli/gh I/O can't run in a
# temp sandbox, so this tests the PURE lib (ref detection, slugify, branch names,
# env-file copy) exhaustively + offline, then syntax-checks the orchestration
# script and its tool-absent / ambiguous-ref error paths.
#
#   bash skills/start-ticket/scripts/test-start-ticket.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/start-ticket.sh"
export CLAUDE_PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
source "$CLAUDE_PLUGIN_ROOT/tools/ticket/ticket-lib.sh"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
eq() { [[ "$1" == "$2" ]] || fail "$3 — expected [$2], got [$1]"; }

echo "start-ticket smoke (CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT)"

# ── ref detection ────────────────────────────────────────────────────────────
eq "$(tl_detect_ref 'MD-1234')" "jira MD-1234" "bare Jira key"
eq "$(tl_detect_ref 'CCAL-456')" "jira CCAL-456" "Jira key, other project"
eq "$(tl_detect_ref 'https://facilitron.atlassian.net/browse/MD-1658')" "jira MD-1658" "Jira browse URL"
eq "$(tl_detect_ref '#42')" "gh 42" "current-repo #N"
eq "$(tl_detect_ref 'Facilitron/marketing-pages#185')" "gh 185 Facilitron/marketing-pages" "owner/repo#N"
eq "$(tl_detect_ref 'https://github.com/acme/app/issues/7')" "gh 7 acme/app" "GitHub issue URL"
eq "$(tl_detect_ref '42'; echo "rc=$?")" $'ambiguous\nrc=1' "bare number is ambiguous (rc=1)"
pass "tl_detect_ref classifies every ref shape (jira/gh/url/ambiguous)"

# ── slugify ──────────────────────────────────────────────────────────────────
eq "$(tl_slugify 'Add BAS logo to product')" "add-bas-logo-to-product" "basic slug"
eq "$(tl_slugify '  Fix: panelist  name (typo!) ')" "fix-panelist-name-typo" "punctuation + spaces collapse"
eq "$(tl_slugify 'ALLCAPS Heading')" "allcaps-heading" "lowercased"
LONG="$(tl_slugify 'this is an extremely long ticket summary that should be trimmed on a word boundary not mid word')"
[[ ${#LONG} -le 50 ]] || fail "slug should be ≤50 chars, got ${#LONG}: $LONG"
[[ "$LONG" != *- ]] || fail "slug should not end with a hyphen: $LONG"
pass "tl_slugify lowercases, collapses punctuation, trims on a word boundary"

# ── branch names ─────────────────────────────────────────────────────────────
eq "$(tl_branch_name jira MD-1658 'Add BAS logo')" "MD-1658-add-bas-logo" "jira branch"
eq "$(tl_branch_name gh 185 'Improve better-auth UX')" "issue-185-improve-better-auth-ux" "gh branch is issue-prefixed"
pass "tl_branch_name builds <KEY>-slug / issue-<N>-slug"

# ── env-file carry-over ──────────────────────────────────────────────────────
T="$(mktemp -d "${TMPDIR:-/tmp}/start-ticket-env.XXXXXX")"
mkdir -p "$T/main" "$T/wt"
printf 'x\n' > "$T/main/.env"
printf 'x\n' > "$T/main/.env.local"
printf 'x\n' > "$T/main/.dev.vars"
printf 'x\n' > "$T/main/README.md"          # NOT a secret file — must be skipped
printf 'old\n' > "$T/wt/.env.local"         # already present — must NOT be clobbered
COPIED="$(tl_copy_env_files "$T/main" "$T/wt" | sort | tr '\n' ' ')"
eq "$COPIED" ".dev.vars .env " "copies the secret-file set, skips README + existing"
[[ -f "$T/wt/.env" ]] || fail "env: .env not copied"
[[ -f "$T/wt/.dev.vars" ]] || fail "env: .dev.vars not copied"
[[ ! -f "$T/wt/README.md" ]] || fail "env: README.md should not be copied"
eq "$(cat "$T/wt/.env.local")" "old" "existing .env.local must not be clobbered"
rm -rf "$T"
pass "tl_copy_env_files carries .env*/.dev.vars*, skips non-secrets, never clobbers"

# ── orchestration script: syntax + error paths ──────────────────────────────
bash -n "$SCRIPT" || fail "start-ticket.sh has a syntax error"
pass "start-ticket.sh parses (bash -n)"

OUT="$(bash "$SCRIPT" '42' --summary 'whatever' 2>/dev/null || true)"
grep -q '"error":"ambiguous-ref"' <<<"$OUT" || fail "ambiguous ref should error: $OUT"
pass "ambiguous bare-number ref → ambiguous-ref error (no worktree created)"

# With a real ref but wt absent from PATH, it fails fast and clean (no partial state).
OUT="$(PATH="/usr/bin:/bin" bash "$SCRIPT" 'MD-1' --branch 'MD-1-x' 2>/dev/null || true)"
grep -q '"error":"wt-not-found"' <<<"$OUT" || fail "missing wt should error wt-not-found: $OUT"
pass "missing wt → wt-not-found error (fails fast)"

echo ""
echo "✅ start-ticket smoke PASSED ($PASS checks)"
