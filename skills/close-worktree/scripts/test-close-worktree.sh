#!/usr/bin/env bash
# Real-git smoke for close-worktree.sh. Builds a throwaway bare origin + main
# checkout + a worker worktree (pushed to origin), runs the script, and asserts
# both the JSON result contract AND that the worktree/branch are actually gone
# from git reality — then proves idempotency (a second run is still ok=true).
#
#   bash skills/close-worktree/scripts/test-close-worktree.sh
#
# No tmux/wt needed: the script skips session-close when no matching tmux
# session exists, so this exercises the pure git plumbing.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/close-worktree.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/close-wt-smoke.XXXXXX")"
ORIGIN="$ROOT/origin.git"
MAIN="$ROOT/main"
WT="$ROOT/wt-md-9999"
BRANCH="MD-9999-smoke-badge"
PASS=0

pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; cleanup; exit 1; }
cleanup() { rm -rf "$ROOT" 2>/dev/null || true; }
# Loud setup git (unlike the script's quiet, never-throw reads).
gx() { git -C "$1" "${@:2}"; }

trap cleanup EXIT

echo "close-worktree smoke: root=$ROOT"

# ── setup ────────────────────────────────────────────────────────────────────
git init --bare -q "$ORIGIN"
git clone -q "$ORIGIN" "$MAIN"
gx "$MAIN" config user.email smoke@tron.local
gx "$MAIN" config user.name "tron smoke"
gx "$MAIN" checkout -q -B master
echo "# smoke" > "$MAIN/README.md"
gx "$MAIN" add README.md
gx "$MAIN" commit -q -m init
gx "$MAIN" push -q -u origin master
gx "$MAIN" worktree add -q -b "$BRANCH" "$WT" master
gx "$WT" push -q -u origin "$BRANCH"
[[ -d "$WT" ]] || fail "setup: worktree dir missing"
pass "repo + worktree + remote branch created"

# ── run the script from INSIDE the worktree being removed ────────────────────
# (the hard case: cwd is the worktree; the script must operate from MAIN_REPO).
OUT="$(cd "$WT" && bash "$SCRIPT" "$BRANCH")" || fail "script exited non-zero: $OUT"
echo "  → $OUT"

assert_json() { grep -q "$1" <<<"$OUT" || fail "expected $1 in result, got: $OUT"; }
assert_json '"ok":true'
assert_json '"worktreeRemoved":true'
assert_json '"localBranchDeleted":true'
assert_json '"remoteBranchDeleted":true'
assert_json '"sessionClosed":true'
assert_json '"workspaceClosed":true'
assert_json '"leftovers":\[\]'
pass "result line reports a clean close"

# ── verify reality, not just the JSON ────────────────────────────────────────
[[ -d "$WT" ]] && fail "worktree dir still present after close"
gx "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH" && fail "local branch still present"
[[ -n "$(gx "$MAIN" ls-remote --heads origin "$BRANCH")" ]] && fail "origin branch still present"
pass "worktree + local branch + origin branch all verified gone"

# ── idempotency: a second close of the now-absent branch is still ok ─────────
OUT2="$(cd "$MAIN" && bash "$SCRIPT" "$BRANCH")" || fail "second run exited non-zero: $OUT2"
grep -q '"ok":true' <<<"$OUT2" || fail "second run not ok: $OUT2"
grep -q '"leftovers":\[\]' <<<"$OUT2" || fail "second run reported leftovers: $OUT2"
pass "idempotent — re-closing an already-gone branch is ok, no leftovers"

# ── --keep-remote leaves origin's copy but removes the local worktree+branch ──
WT2="$ROOT/wt-md-8888"; BRANCH2="MD-8888-keep-remote"
gx "$MAIN" worktree add -q -b "$BRANCH2" "$WT2" master
gx "$WT2" push -q -u origin "$BRANCH2"
OUT3="$(cd "$MAIN" && bash "$SCRIPT" "$BRANCH2" --keep-remote)" || fail "keep-remote run failed: $OUT3"
grep -q '"ok":true' <<<"$OUT3" || fail "keep-remote not ok: $OUT3"
[[ -d "$WT2" ]] && fail "keep-remote: worktree should be gone"
[[ -z "$(gx "$MAIN" ls-remote --heads origin "$BRANCH2")" ]] && fail "keep-remote: origin branch should remain"
pass "--keep-remote removes worktree+local branch, preserves origin branch"

echo ""
echo "✅ close-worktree smoke PASSED ($PASS checks)"
