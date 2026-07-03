#!/usr/bin/env bash
# Real-git smoke for git-pushtoprod.sh. Asserts the JSON contract AND git
# reality across two cases:
#   A. clean → master merges into staging AND production, both pushed, ok:true
#   B. a non-package conflict on staging halts BEFORE production is touched
#
#   bash skills/git-pushtoprod/scripts/test-git-pushtoprod.sh
#
# Always run with --no-jira so the smoke never calls acli against a fake ticket.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/git-pushtoprod.sh"
export CLAUDE_PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd)"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
gx() { git -C "$1" "${@:2}"; }

# Bare origin + main on master + staging + production (all at the same base).
setup() {
  local root main origin
  root="$(mktemp -d "${TMPDIR:-/tmp}/pushtoprod-smoke.XXXXXX")"
  origin="$root/origin.git"; main="$root/main"
  git init --bare -q "$origin"
  git clone -q "$origin" "$main"
  gx "$main" config user.email smoke@tron.local
  gx "$main" config user.name "tron smoke"
  gx "$main" checkout -q -B master
  echo base > "$main/app.txt"; echo "# r" > "$main/README.md"
  gx "$main" add -A; gx "$main" commit -q -m init; gx "$main" push -q -u origin master
  gx "$main" checkout -q -b staging master; gx "$main" push -q -u origin staging
  gx "$main" checkout -q -b production master; gx "$main" push -q -u origin production
  gx "$main" checkout -q master
  printf '%s\n' "$main"
}

echo "git-pushtoprod smoke (CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT)"

# ── A. clean promotion of master into staging + production ───────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
echo "shipped feature" > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: ship it"; gx "$MAIN" push -q
# Stand on a feature-ish branch name so key-parsing has something, but --no-jira.
gx "$MAIN" checkout -q -b MD-7-ship master
OUT="$(cd "$MAIN" && bash "$SCRIPT" --no-jira)" || fail "A: script exited non-zero: $OUT"
echo "  → $OUT"
grep -q '"ok":true' <<<"$OUT" || fail "A: not ok: $OUT"
grep -q '"staging":true' <<<"$OUT" || fail "A: staging not true: $OUT"
grep -q '"production":true' <<<"$OUT" || fail "A: production not true: $OUT"
grep -q '"jira":"MD-7:skipped"' <<<"$OUT" || fail "A: jira should be skipped: $OUT"
# Capture-then-grep: `git log | grep -q` would SIGPIPE git and trip pipefail.
grep -q "ship it" <<<"$(gx "$MAIN" log staging --oneline)" || fail "A: staging missing master's commit"
grep -q "ship it" <<<"$(gx "$MAIN" log production --oneline)" || fail "A: production missing master's commit"
[[ "$(gx "$MAIN" rev-parse --abbrev-ref HEAD)" == MD-7-ship ]] || fail "A: did not restore starting branch"
pass "master promoted into staging + production, both pushed, start branch restored"
rm -rf "$ROOT"

# ── B. a staging conflict halts before production ────────────────────────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
# Diverge staging so a master merge conflicts on app.txt (non-package → abort).
gx "$MAIN" checkout -q staging; echo staging-only > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: staging divergence"; gx "$MAIN" push -q
gx "$MAIN" checkout -q master; echo master-change > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: master change"; gx "$MAIN" push -q
PROD_TIP_BEFORE="$(gx "$MAIN" rev-parse production)"
OUT="$(cd "$MAIN" && bash "$SCRIPT" --no-jira)" && fail "B: expected non-zero exit, got: $OUT"
echo "  → $OUT"
grep -q '"ok":false' <<<"$OUT" || fail "B: should be not-ok: $OUT"
grep -q '"staging":false' <<<"$OUT" || fail "B: staging should be false: $OUT"
grep -q '"production":false' <<<"$OUT" || fail "B: production must not be attempted: $OUT"
grep -q '"error":"staging-conflicts"' <<<"$OUT" || fail "B: wrong error: $OUT"
[[ "$(gx "$MAIN" rev-parse production)" == "$PROD_TIP_BEFORE" ]] || fail "B: production advanced despite staging failure"
[[ -z "$(gx "$MAIN" status --porcelain)" ]] || fail "B: tree left dirty (merge not aborted)"
pass "staging conflict halts before production; production untouched; tree clean"
rm -rf "$ROOT"

# ── C. repo with NO staging branch promotes master → production directly ──────
# Build an origin with master + production only (no staging), like a Cloudflare
# Worker app whose deploy lanes are just master and production.
setup_no_staging() {
  local root main origin
  root="$(mktemp -d "${TMPDIR:-/tmp}/pushtoprod-nostaging.XXXXXX")"
  origin="$root/origin.git"; main="$root/main"
  git init --bare -q "$origin"
  git clone -q "$origin" "$main"
  gx "$main" config user.email smoke@tron.local
  gx "$main" config user.name "tron smoke"
  gx "$main" checkout -q -B master
  echo base > "$main/app.txt"; echo "# r" > "$main/README.md"
  gx "$main" add -A; gx "$main" commit -q -m init; gx "$main" push -q -u origin master
  gx "$main" checkout -q -b production master; gx "$main" push -q -u origin production
  gx "$main" checkout -q master
  printf '%s\n' "$main"
}

MAIN="$(setup_no_staging)"; ROOT="$(dirname "$MAIN")"
echo "shipped feature" > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: ship it"; gx "$MAIN" push -q
gx "$MAIN" checkout -q -b MD-9-ship master
OUT="$(cd "$MAIN" && bash "$SCRIPT" --no-jira)" || fail "C: script exited non-zero: $OUT"
echo "  → $OUT"
grep -q '"ok":true' <<<"$OUT" || fail "C: not ok: $OUT"
grep -q '"staging":"skipped"' <<<"$OUT" || fail "C: staging should be skipped: $OUT"
grep -q '"production":true' <<<"$OUT" || fail "C: production not true: $OUT"
grep -q '"leftovers":\[\]' <<<"$OUT" || fail "C: skipped staging must not be a leftover: $OUT"
grep -q "ship it" <<<"$(gx "$MAIN" log production --oneline)" || fail "C: production missing master's commit"
[[ "$(gx "$MAIN" rev-parse --abbrev-ref HEAD)" == MD-9-ship ]] || fail "C: did not restore starting branch"
pass "no-staging repo promotes master → production directly; staging reported skipped"
rm -rf "$ROOT"

# ── D. repo with neither staging nor production reports no-production-branch ──
MAIN="$(setup_no_staging)"; ROOT="$(dirname "$MAIN")"
gx "$MAIN" push -q origin --delete production >/dev/null 2>&1
gx "$MAIN" branch -q -D production >/dev/null 2>&1 || true
gx "$MAIN" checkout -q -b MD-11-ship master
OUT="$(cd "$MAIN" && bash "$SCRIPT" --no-jira)" && fail "D: expected non-zero exit, got: $OUT"
echo "  → $OUT"
grep -q '"error":"no-production-branch"' <<<"$OUT" || fail "D: wrong error: $OUT"
# staging must read "skipped" (no staging branch) even on this failure path, not false.
grep -q '"staging":"skipped"' <<<"$OUT" || fail "D: staging should be skipped, not false: $OUT"
pass "repo with no production branch is rejected cleanly (staging reported skipped)"
rm -rf "$ROOT"

# ── E. --worktree: branch/dirty/Jira-key resolve from the given path ─────────
MAIN="$(setup)"; ROOT="$(dirname "$MAIN")"
echo "wt feature" > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m "feat: wt ship"; gx "$MAIN" push -q
WT="$ROOT/wt-MD-13"
gx "$MAIN" worktree add -q -b MD-13-wt "$WT" master
# E1: a dirty WORKTREE must be caught even when cwd (the main checkout) is clean.
echo dirty > "$WT/scratch.txt"
OUT="$(cd "$MAIN" && bash "$SCRIPT" --no-jira --worktree "$WT")" && fail "E1: expected non-zero exit, got: $OUT"
echo "  → $OUT"
grep -q '"error":"dirty-working-tree"' <<<"$OUT" || fail "E1: dirty worktree not detected via --worktree: $OUT"
pass "--worktree: dirty worktree detected while \$PWD (main) is clean"
# E2: clean run — Jira key parses from the WORKTREE's branch, main parked on master.
rm "$WT/scratch.txt"
OUT="$(cd "$MAIN" && bash "$SCRIPT" --no-jira --worktree "$WT")" || fail "E2: script exited non-zero: $OUT"
echo "  → $OUT"
grep -q '"ok":true' <<<"$OUT" || fail "E2: not ok: $OUT"
grep -q '"jira":"MD-13:skipped"' <<<"$OUT" || fail "E2: Jira key should come from the worktree branch: $OUT"
grep -q "wt ship" <<<"$(gx "$MAIN" log production --oneline)" || fail "E2: production missing master's commit"
[[ "$(gx "$MAIN" rev-parse --abbrev-ref HEAD)" == master ]] || fail "E2: main checkout should be parked on master after a worktree run"
[[ "$(gx "$WT" rev-parse --abbrev-ref HEAD)" == MD-13-wt ]] || fail "E2: worktree should still be on its branch"
pass "--worktree: START_BRANCH + Jira key from the worktree; promotion works; main parked on master"
rm -rf "$ROOT"

echo ""
echo "✅ git-pushtoprod smoke PASSED ($PASS checks)"
