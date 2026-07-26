#!/usr/bin/env bash
# Real-git smoke for git-dev.sh. Builds throwaway repos and asserts the JSON
# contract AND git reality across three cases:
#   A. clean merge from inside a worktree → dev advances, ok:true
#   B. package.json-only conflict → --ours keeps dev's copy, ok:true
#   C. a non-package conflict → merge aborts, dev untouched, ok:false
#   D. bun.lock-only conflict → --ours keeps dev's copy, ok:true
#   E. --worktree <path> resolves branch/dirty from the path, not $PWD
#   F. a repo with no dev branch → friendly no-dev-branch error
#   H. a patch-equivalent commit already on dev is skipped and identified
#   I. a similar but non-equivalent commit is still promoted
#   J. an identical commit already reachable from dev is skipped and identified
#
#   bash skills/git-dev/scripts/test-git-dev.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/git-dev.sh"
export CLAUDE_PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd)"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
gx() { git -C "$1" "${@:2}"; }

# Build bare origin + main checkout on master + a dev branch. Echoes MAIN.
setup() {
  local root main origin
  root="$(mktemp -d "${TMPDIR:-/tmp}/git-dev-smoke.XXXXXX")"
  origin="$root/origin.git"; main="$root/main"
  git init --bare -q "$origin"
  git clone -q "$origin" "$main"
  gx "$main" config user.email smoke@tron.local
  gx "$main" config user.name "tron smoke"
  gx "$main" checkout -q -B master
  echo "1.0.0" > "$main/package.json"; echo "lock" > "$main/package-lock.json"
  echo base > "$main/app.txt"; echo "# r" > "$main/README.md"
  gx "$main" add -A; gx "$main" commit -q -m init; gx "$main" push -q -u origin master
  gx "$main" checkout -q -b dev master; gx "$main" push -q -u origin dev
  gx "$main" checkout -q master
  printf '%s\n' "$main"
}

echo "git-dev smoke (CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT)"

# ── A. clean merge from a worktree ───────────────────────────────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q -b MD-1-feature master
echo hello > "$MAIN/feature.txt"; gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: add feature.txt"
gx "$MAIN" checkout -q master
gx "$MAIN" worktree add -q "$ROOT/wt" MD-1-feature
OUT="$(cd "$ROOT/wt" && bash "$SCRIPT")" || fail "A: script exited non-zero: $OUT"
echo "  → $OUT"
grep -q '"ok":true' <<<"$OUT" || fail "A: not ok: $OUT"
grep -q '"target":"dev"' <<<"$OUT" || fail "A: wrong target: $OUT"
grep -q '"worktree":true' <<<"$OUT" || fail "A: should detect worktree: $OUT"
# Capture-then-grep: `git log | grep -q` would SIGPIPE git and trip pipefail.
grep -q "add feature.txt" <<<"$(gx "$MAIN" log dev --oneline)" || fail "A: dev missing the feature commit"
[[ "$(gx "$MAIN" rev-parse --abbrev-ref HEAD)" == master ]] || fail "A: main checkout not restored to master"
pass "clean merge from a worktree advances dev + restores master"
rm -rf "$ROOT"

# ── B. package.json-only conflict resolves to dev's copy ─────────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q dev; echo "1.0.1-dev" > "$MAIN/package.json"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "chore: dev deps"; gx "$MAIN" push -q
gx "$MAIN" checkout -q -b MD-2-deps master; echo "1.0.2-feat" > "$MAIN/package.json"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "chore: feature deps"
gx "$MAIN" checkout -q master
OUT="$(cd "$MAIN" && bash "$SCRIPT" MD-2-deps)" || fail "B: script exited non-zero: $OUT"
echo "  → $OUT"
grep -q '"ok":true' <<<"$OUT" || fail "B: not ok: $OUT"
grep -q '"depsResolved":\["package.json"\]' <<<"$OUT" || fail "B: package.json not reported resolved: $OUT"
[[ "$(gx "$MAIN" show dev:package.json)" == "1.0.1-dev" ]] || fail "B: dev's package.json was overwritten"
pass "package.json-only conflict resolves --ours (dev keeps its copy)"
rm -rf "$ROOT"

# ── C. non-package conflict aborts, dev untouched ────────────────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q dev; echo dev-change > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: dev app change"; gx "$MAIN" push -q
DEV_TIP_BEFORE="$(gx "$MAIN" rev-parse dev)"
gx "$MAIN" checkout -q -b MD-3-clash master; echo feat-change > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: feature app change"
gx "$MAIN" checkout -q master
OUT="$(cd "$MAIN" && bash "$SCRIPT" MD-3-clash)" && fail "C: expected non-zero exit, got ok: $OUT"
echo "  → $OUT"
grep -q '"ok":false' <<<"$OUT" || fail "C: should be not-ok: $OUT"
grep -q '"conflicts":\["app.txt"\]' <<<"$OUT" || fail "C: app.txt not reported as conflict: $OUT"
[[ "$(gx "$MAIN" rev-parse dev)" == "$DEV_TIP_BEFORE" ]] || fail "C: dev advanced despite abort"
[[ -z "$(gx "$MAIN" status --porcelain)" ]] || fail "C: merge not cleanly aborted (dirty tree left)"
pass "non-package conflict aborts cleanly, dev tip unchanged"
rm -rf "$ROOT"

# ── D. bun.lock-only conflict resolves to dev's copy ─────────────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q dev; echo "bun-dev" > "$MAIN/bun.lock"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "chore: dev bun.lock"; gx "$MAIN" push -q
gx "$MAIN" checkout -q -b MD-4-bun master; echo "bun-feat" > "$MAIN/bun.lock"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "chore: feature bun.lock"
gx "$MAIN" checkout -q master
OUT="$(cd "$MAIN" && bash "$SCRIPT" MD-4-bun)" || fail "D: script exited non-zero: $OUT"
echo "  → $OUT"
grep -q '"ok":true' <<<"$OUT" || fail "D: not ok: $OUT"
grep -q '"depsResolved":\["bun.lock"\]' <<<"$OUT" || fail "D: bun.lock not reported resolved: $OUT"
[[ "$(gx "$MAIN" show dev:bun.lock)" == "bun-dev" ]] || fail "D: dev's bun.lock was overwritten"
pass "bun.lock-only conflict resolves --ours (dev keeps its copy)"
rm -rf "$ROOT"

# ── E. --worktree resolves branch/dirty from the path, not $PWD ───────────────
# Run the script from the MAIN checkout (which is on master) but point it at the
# worktree via --worktree — it must promote the worktree's feature branch, not
# master. This is the wt-integrated-shell scenario the flag exists for.
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q -b MD-5-wtflag master
echo wtflag > "$MAIN/wtflag.txt"; gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: wtflag.txt"
gx "$MAIN" checkout -q master
gx "$MAIN" worktree add -q "$ROOT/wt" MD-5-wtflag
# cwd is MAIN (on master); without --worktree this would error on-protected-branch.
OUT="$(cd "$MAIN" && bash "$SCRIPT" --worktree "$ROOT/wt")" || fail "E: script exited non-zero: $OUT"
echo "  → $OUT"
grep -q '"ok":true' <<<"$OUT" || fail "E: not ok: $OUT"
grep -q '"branch":"MD-5-wtflag"' <<<"$OUT" || fail "E: wrong branch resolved (should read worktree, not pwd): $OUT"
grep -q '"worktree":true' <<<"$OUT" || fail "E: should detect worktree from --worktree path: $OUT"
grep -q "wtflag.txt" <<<"$(gx "$MAIN" log dev --oneline)" || fail "E: dev missing the worktree's feature commit"
pass "--worktree resolves branch + dirty-check from the path, not pwd"
rm -rf "$ROOT"

# ── F. a repo with no dev branch → friendly no-dev-branch error ───────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" branch -q -D dev                       # drop local dev
gx "$MAIN" push -q origin --delete dev >/dev/null 2>&1 || true   # and the remote tracking ref
gx "$MAIN" remote prune origin >/dev/null 2>&1 || true
gx "$MAIN" checkout -q -b MD-6-nodev master
echo nodev > "$MAIN/nodev.txt"; gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: nodev.txt"
OUT="$(cd "$MAIN" && bash "$SCRIPT" MD-6-nodev)" && fail "F: expected non-zero exit, got ok: $OUT"
echo "  → $OUT"
grep -q '"error":"no-dev-branch"' <<<"$OUT" || fail "F: should report no-dev-branch: $OUT"
pass "no dev branch → friendly no-dev-branch error (not opaque checkout-dev)"
rm -rf "$ROOT"

# ── G. --worktree with no value → clean JSON error, no shift-count crash ──────
OUT="$(bash "$SCRIPT" --worktree 2>/dev/null)" && fail "G: expected non-zero exit: $OUT"
echo "  → $OUT"
grep -q '"error":"missing-worktree-value"' <<<"$OUT" || fail "G: should report missing-worktree-value: $OUT"
pass "--worktree with no value errors cleanly (no set -e shift-count crash)"

# ── H. patch-equivalent commit already on dev is skipped ─────────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q dev
echo equivalent > "$MAIN/equivalent.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "fix: already applied on dev"; gx "$MAIN" push -q
gx "$MAIN" checkout -q -b MD-8-equivalent master
echo equivalent > "$MAIN/equivalent.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "fix: incoming equivalent patch"
INCOMING_SHA="$(gx "$MAIN" rev-parse HEAD)"
DEV_TIP_BEFORE="$(gx "$MAIN" rev-parse dev)"
gx "$MAIN" checkout -q master
OUT="$(cd "$MAIN" && bash "$SCRIPT" MD-8-equivalent)" || fail "H: script exited non-zero: $OUT"
echo "  → $OUT"
rg -q '"ok":true' <<<"$OUT" || fail "H: not ok: $OUT"
rg -q '"skippedSupersededCommits":\[' <<<"$OUT" || fail "H: skipped commits not reported: $OUT"
rg -q "\"$INCOMING_SHA\"" <<<"$OUT" || fail "H: incoming equivalent SHA not identified: $OUT"
[[ "$(gx "$MAIN" rev-parse dev)" == "$DEV_TIP_BEFORE" ]] || fail "H: dev advanced for an already-present patch"
pass "patch-equivalent incoming commit is skipped and identified"
rm -rf "$ROOT"

# ── I. non-equivalent incoming commit is not skipped ─────────────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q dev
echo dev-version > "$MAIN/similar.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "fix: dev version"; gx "$MAIN" push -q
gx "$MAIN" checkout -q -b MD-9-non-equivalent master
echo incoming-version > "$MAIN/different.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "fix: distinct incoming patch"
INCOMING_SHA="$(gx "$MAIN" rev-parse HEAD)"
gx "$MAIN" checkout -q master
OUT="$(cd "$MAIN" && bash "$SCRIPT" MD-9-non-equivalent)" || fail "I: script exited non-zero: $OUT"
echo "  → $OUT"
rg -q '"ok":true' <<<"$OUT" || fail "I: not ok: $OUT"
rg -q '"skippedSupersededCommits":\[\]' <<<"$OUT" || fail "I: non-equivalent commit reported skipped: $OUT"
gx "$MAIN" merge-base --is-ancestor "$INCOMING_SHA" dev || fail "I: non-equivalent incoming commit was not promoted"
pass "non-equivalent incoming commit is promoted normally"
rm -rf "$ROOT"

# ── J. identical commit already reachable from dev is skipped ────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" checkout -q -b MD-10-identical master
echo identical > "$MAIN/identical.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "fix: identical incoming commit"
INCOMING_SHA="$(gx "$MAIN" rev-parse HEAD)"
gx "$MAIN" checkout -q dev
gx "$MAIN" merge -q --no-edit MD-10-identical
gx "$MAIN" push -q
DEV_TIP_BEFORE="$(gx "$MAIN" rev-parse dev)"
gx "$MAIN" checkout -q master
OUT="$(cd "$MAIN" && bash "$SCRIPT" MD-10-identical)" || fail "J: script exited non-zero: $OUT"
echo "  → $OUT"
rg -q '"ok":true' <<<"$OUT" || fail "J: not ok: $OUT"
rg -q "\"$INCOMING_SHA\"" <<<"$OUT" || fail "J: reachable incoming SHA not identified as skipped: $OUT"
[[ "$(gx "$MAIN" rev-parse dev)" == "$DEV_TIP_BEFORE" ]] || fail "J: dev advanced for an already-reachable commit"
pass "identical incoming commit already reachable from dev is skipped and identified"
rm -rf "$ROOT"

echo ""
echo "✅ git-dev smoke PASSED ($PASS checks)"
