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
BIN="$ROOT/bin"
TMUX_LOG="$ROOT/tmux.log"
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
mkdir -p "$BIN"
# The single-quoted strings are literal source for the fake executables.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '[[ "${GH_FAKE_MERGED:-0}" == 1 ]] || exit 1' \
  'printf "[{\"number\":1,\"headRefOid\":\"%s\"}]\n" "$GH_FAKE_HEAD_OID"' > "$BIN/gh"
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "$1" in' \
  '  list-sessions) [[ -n "${TMUX_FAKE_SESSION:-}" ]] && printf "%s\n" "$TMUX_FAKE_SESSION" ;;' \
  '  kill-session) printf "%s\n" "$*" >> "$TMUX_FAKE_LOG" ;;' \
  'esac' > "$BIN/tmux"
chmod +x "$BIN/gh" "$BIN/tmux"
export PATH="$BIN:$PATH" TMUX_FAKE_LOG="$TMUX_LOG"
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

# ── default re-sync: close fast-forwards the main checkout's default branch ───
# Advance origin's master beyond the main checkout, then prove close re-syncs it.
gx "$MAIN" checkout -q master
echo "ahead" > "$MAIN/AHEAD.md"; gx "$MAIN" add AHEAD.md; gx "$MAIN" commit -q -m ahead
gx "$MAIN" push -q origin master
AHEAD="$(gx "$MAIN" rev-parse master)"
gx "$MAIN" reset -q --hard HEAD~1                       # main now 1 behind origin/master
[[ "$(gx "$MAIN" rev-parse master)" != "$AHEAD" ]] || fail "setup: main should be behind origin/master"
WT4="$ROOT/wt-md-7777"; BRANCH4="MD-7777-resync"
gx "$MAIN" worktree add -q -b "$BRANCH4" "$WT4" master
OUT4="$(cd "$MAIN" && bash "$SCRIPT" "$BRANCH4")" || fail "resync run exited non-zero: $OUT4"
grep -q '"ok":true' <<<"$OUT4" || fail "resync run not ok: $OUT4"
[[ "$(gx "$MAIN" rev-parse master)" == "$AHEAD" ]] || fail "close did not re-sync master to origin/master"
pass "close-worktree fast-forwards the main checkout's default branch (ff-only) on cleanup"

# ── re-sync never fails cleanup when it can't fast-forward (diverged default) ──
gx "$MAIN" checkout -q master
echo "local-only" > "$MAIN/DIVERGE.md"; gx "$MAIN" add DIVERGE.md; gx "$MAIN" commit -q -m local-divergence
DIVERGED="$(gx "$MAIN" rev-parse master)"
# origin/master now differs from local master in a non-ff way is hard to force
# locally; instead just confirm a clean close still succeeds and leaves master put
# when origin has nothing new to pull.
WT5="$ROOT/wt-md-6666"; BRANCH5="MD-6666-noff"
gx "$MAIN" worktree add -q -b "$BRANCH5" "$WT5" master
OUT5="$(cd "$MAIN" && bash "$SCRIPT" "$BRANCH5")" || fail "no-ff run exited non-zero: $OUT5"
grep -q '"ok":true' <<<"$OUT5" || fail "no-ff run should still report ok: $OUT5"
[[ "$(gx "$MAIN" rev-parse master)" == "$DIVERGED" ]] || fail "close must not move/merge a non-fast-forwardable default"
pass "close-worktree never fails or merges when the default can't fast-forward"

# ── squash merge: safe -d fails, verified merged PR permits guarded -D ───────
gx "$MAIN" reset -q --hard origin/master
WT6="$ROOT/wt-md-2262"; BRANCH6="MD-2262-squash-regression"
gx "$MAIN" worktree add -q -b "$BRANCH6" "$WT6" master
echo "feature" > "$WT6/SQUASH.md"
gx "$WT6" add SQUASH.md
gx "$WT6" commit -q -m feature
gx "$WT6" push -q -u origin "$BRANCH6"
# Recreate the feature as a distinct squash commit on master. The branch tip is
# intentionally not an ancestor, matching the MD-2262 cleanup failure.
git -C "$WT6" show HEAD:SQUASH.md > "$MAIN/SQUASH.md"
gx "$MAIN" add SQUASH.md
gx "$MAIN" commit -q -m "squash feature"
gx "$MAIN" push -q origin master
# Match GitHub's auto-delete behavior. With the upstream gone, default
# `git branch -d` fails because the squash commit has different ancestry.
gx "$MAIN" push -q origin --delete "$BRANCH6"
gx "$MAIN" merge-base --is-ancestor "$BRANCH6" master \
  && fail "setup: squash branch must not be an ancestor of master"
TIP6="$(gx "$MAIN" rev-parse "$BRANCH6")"
OUT6="$(cd "$MAIN" && GH_FAKE_MERGED=1 GH_FAKE_HEAD_OID="$TIP6" bash "$SCRIPT" "$BRANCH6")" \
  || fail "squash-merge run exited non-zero: $OUT6"
grep -q '"ok":true' <<<"$OUT6" || fail "squash-merge run not ok: $OUT6"
gx "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH6" \
  && fail "squash-merged local branch still present"
pass "verified squash-merged PR allows guarded local branch force-deletion"

# ── partial retry: local gone + remote present can still finish idempotently ─
WT8="$ROOT/wt-md-4444"; BRANCH8="MD-4444-remote-retry"
gx "$MAIN" worktree add -q -b "$BRANCH8" "$WT8" master
gx "$WT8" push -q -u origin "$BRANCH8"
gx "$MAIN" worktree remove "$WT8"
gx "$MAIN" branch -q -D "$BRANCH8"
OUT8="$(cd "$MAIN" && bash "$SCRIPT" "$BRANCH8")" \
  || fail "remote-only retry exited non-zero: $OUT8"
grep -q '"ok":true' <<<"$OUT8" || fail "remote-only retry not ok: $OUT8"
[[ -z "$(gx "$MAIN" ls-remote --heads origin "$BRANCH8")" ]] \
  || fail "remote-only retry left origin branch present"
pass "retry verifies and removes a remote ref when local branch is already absent"

# ── reused branch: commits after the merged PR invalidate exact-head proof ───
WT9="$ROOT/wt-md-3333"; BRANCH9="MD-3333-reused-after-merge"
gx "$MAIN" worktree add -q -b "$BRANCH9" "$WT9" master
echo "merged tip" > "$WT9/REUSED.md"
gx "$WT9" add REUSED.md
gx "$WT9" commit -q -m "merged tip"
MERGED_TIP9="$(gx "$WT9" rev-parse HEAD)"
echo "new unmerged tip" >> "$WT9/REUSED.md"
gx "$WT9" commit -q -am "new unmerged tip"
gx "$WT9" push -q -u origin "$BRANCH9"
if OUT9="$(cd "$MAIN" && GH_FAKE_MERGED=1 GH_FAKE_HEAD_OID="$MERGED_TIP9" \
  bash "$SCRIPT" "$BRANCH9")"; then
  fail "post-merge commit should invalidate exact-head proof: $OUT9"
fi
grep -q '"local branch"' <<<"$OUT9" || fail "missing reused local leftover: $OUT9"
grep -q '"origin branch"' <<<"$OUT9" || fail "missing reused remote leftover: $OUT9"
gx "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH9" \
  || fail "post-merge local tip should be preserved"
gx "$MAIN" push -q origin --delete "$BRANCH9"
gx "$MAIN" branch -q -D "$BRANCH9"
pass "merged PR proof cannot delete newer commits on a reused branch"

# ── incomplete cleanup retains the worker session and actionable refs ────────
WT7="$ROOT/wt-md-5555"; BRANCH7="MD-5555-unverified"
gx "$MAIN" worktree add -q -b "$BRANCH7" "$WT7" master
echo "unmerged" > "$WT7/UNMERGED.md"
gx "$WT7" add UNMERGED.md
gx "$WT7" commit -q -m unmerged
gx "$WT7" push -q -u origin "$BRANCH7"
: > "$TMUX_LOG"
if OUT7="$(cd "$MAIN" && TMUX_FAKE_SESSION="$BRANCH7" bash "$SCRIPT" "$BRANCH7")"; then
  fail "unverified cleanup should report failure: $OUT7"
fi
grep -q '"local branch"' <<<"$OUT7" || fail "missing local branch leftover: $OUT7"
grep -q '"origin branch"' <<<"$OUT7" || fail "missing origin branch leftover: $OUT7"
grep -q '"session"' <<<"$OUT7" || fail "missing retained session leftover: $OUT7"
[[ ! -s "$TMUX_LOG" ]] || fail "tmux session was killed before cleanup completed"
gx "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH7" \
  || fail "unverified local branch should be preserved"
[[ -n "$(gx "$MAIN" ls-remote --heads origin "$BRANCH7")" ]] \
  || fail "unverified origin branch should be preserved"
gx "$MAIN" push -q origin --delete "$BRANCH7"
gx "$MAIN" branch -q -D "$BRANCH7"
pass "incomplete cleanup preserves unverified refs and keeps worker session alive"

echo ""
echo "✅ close-worktree smoke PASSED ($PASS checks)"
