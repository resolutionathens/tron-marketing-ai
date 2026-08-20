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
done
pass "both push snippets use the current worktree root"

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
    WORKTREE="$(git rev-parse --show-toplevel)"
    BRANCH="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)"
    [ "$WORKTREE" = "$1" ]
    [ "$BRANCH" = feature-two ]
  ' "$shell" "$ROOT/feature-two" || fail "$shell must resolve feature-two from its linked worktree"
  pass "$shell resolves feature-two from a linked worktree with another worktree present"
done

echo "worktree-aware push regression: $PASS assertions passed"
