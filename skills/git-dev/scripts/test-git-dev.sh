#!/usr/bin/env bash
# Real-git smoke for git-dev.sh. Builds throwaway repos and asserts the JSON
# contract AND git reality across three cases:
#   A. clean merge from inside a worktree → dev advances, ok:true
#   B. package.json-only conflict → --ours keeps dev's copy, ok:true
#   C. a non-package conflict → merge aborts, dev untouched, ok:false
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

echo ""
echo "✅ git-dev smoke PASSED ($PASS checks)"
