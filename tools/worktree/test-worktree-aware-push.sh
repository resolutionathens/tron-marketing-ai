#!/usr/bin/env bash
# Regression test for the documented git-commit/git-pr push snippets. Run with:
#   bash tools/worktree/test-worktree-aware-push.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/worktree-aware-push.XXXXXX")"
PASS=0

pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

for skill in skills/git-commit/SKILL.md skills/git-pr/SKILL.md; do
  grep -F 'WORKTREE="$(git rev-parse --show-toplevel)"' "$REPO_ROOT/$skill" >/dev/null \
    || fail "$skill must resolve the current worktree root"
  grep -F 'BRANCH="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)"' "$REPO_ROOT/$skill" >/dev/null \
    || fail "$skill must resolve its branch from that worktree"
  grep -F 'UPSTREAM="$(git -C "$WORKTREE" rev-parse --abbrev-ref "@{u}" 2>/dev/null || true)"' "$REPO_ROOT/$skill" >/dev/null \
    || fail "$skill must resolve its upstream short name without failing when none exists"
  grep -F 'if [ "${UPSTREAM#*/}" = "$BRANCH" ]; then' "$REPO_ROOT/$skill" >/dev/null \
    || fail "$skill must only use a plain push when its upstream branch name matches"
  grep -F 'git -C "$WORKTREE" push -u origin "$BRANCH"' "$REPO_ROOT/$skill" >/dev/null \
    || fail "$skill must set a same-name upstream when no matching upstream exists"
done
pass "both push snippets use the current worktree root and a matching upstream name"

git init -q "$ROOT/main"
git -C "$ROOT/main" config user.email unit@tron.local
git -C "$ROOT/main" config user.name "tron unit"
touch "$ROOT/main/seed"
git -C "$ROOT/main" add seed
git -C "$ROOT/main" commit -qm seed
git -C "$ROOT/main" branch feature-one
git -C "$ROOT/main" worktree add -q "$ROOT/feature-one" feature-one
git -C "$ROOT/main" branch feature-two
git -C "$ROOT/main" worktree add -q "$ROOT/feature-two" feature-two

for shell in bash zsh; do
  command -v "$shell" >/dev/null 2>&1 || fail "$shell is required for this regression test"
  "$shell" -c '
    set -eu
    cd "$1"
    EXPECTED_WORKTREE="$(pwd -P)"
    WORKTREE="$(git rev-parse --show-toplevel)"
    BRANCH="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)"
    [ "$WORKTREE" = "$EXPECTED_WORKTREE" ]
    [ "$BRANCH" = feature-two ]
  ' "$shell" "$ROOT/feature-two" || fail "$shell must resolve feature-two from its linked worktree"
  pass "$shell resolves feature-two from a linked worktree with another worktree present"
done

# A branch cut from origin/master inherits that upstream. The documented
# comparison must choose -u on its first push so push.default=simple succeeds.
git init --bare -q "$ROOT/origin"
git -C "$ROOT/main" remote add origin "$ROOT/origin"
git -C "$ROOT/main" push -q -u origin master
git clone -q "$ROOT/origin" "$ROOT/inherited"
git -C "$ROOT/inherited" config user.email unit@tron.local
git -C "$ROOT/inherited" config user.name "tron unit"
git -C "$ROOT/inherited" checkout -qb inherited-push origin/master
touch "$ROOT/inherited/change"
git -C "$ROOT/inherited" add change
git -C "$ROOT/inherited" commit -qm change
WORKTREE="$ROOT/inherited"
BRANCH="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)"
UPSTREAM="$(git -C "$WORKTREE" rev-parse --abbrev-ref "@{u}" 2>/dev/null || true)"
if [ "${UPSTREAM#*/}" = "$BRANCH" ]; then
  git -C "$WORKTREE" push -q
else
  git -C "$WORKTREE" push -q -u origin "$BRANCH"
fi
[ "$(git -C "$WORKTREE" rev-parse --abbrev-ref '@{u}')" = "origin/$BRANCH" ] \
  || fail "an inherited differently named upstream must be replaced on first push"
pass "a branch inheriting origin/master pushes and tracks its own remote branch"

echo "worktree-aware push regression: $PASS assertions passed"
