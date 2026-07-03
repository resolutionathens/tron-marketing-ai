#!/usr/bin/env bash
# Direct unit test for git-promote.sh's shared primitives. The full promotion
# FLOW (clean merge / dep-only --ours / non-dep abort) is already covered
# end-to-end by skills/git-dev/scripts/test-git-dev.sh and
# skills/git-pushtoprod/scripts/test-git-pushtoprod.sh, so this file deliberately
# does NOT re-run those scenarios. It pins the lower-level helper contracts those
# suites exercise only implicitly:
#   • gp_is_dep_file's ownership list
#   • gp_main_repo / gp_in_worktree resolving the primary checkout (from a
#     worktree too)
#   • gp_dirty (clean → empty, dirty → porcelain lines)
#   • gp_has_branch (local ref, origin remote ref, absent)
#   • gp_merge_into's error:<stage> path on a bogus target (an error surface the
#     flow suites never hit)
#
#   bash tools/git/test-git-promote.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/git-promote.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-promote-unit.XXXXXX")"
ROOT="$(cd "$ROOT" && pwd -P)"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
gx() { git -C "$1" "${@:2}"; }

echo "git-promote unit test: root=$ROOT"

# shellcheck source=/dev/null
source "$LIB"

# --- gp_is_dep_file (pure list membership) -----------------------------------
for f in package.json package-lock.json bun.lock bun.lockb; do
  gp_is_dep_file "$f" || fail "gp_is_dep_file should own '$f'"
done
for f in app.txt README.md yarn.lock src/package.json package.json.bak; do
  gp_is_dep_file "$f" && fail "gp_is_dep_file should NOT own '$f'"
done
pass "gp_is_dep_file → owns the manifest/lockfile set exactly (path-exact, not substring)"

# --- build a real bare origin + main checkout --------------------------------
ORIGIN="$ROOT/origin.git"; MAIN="$ROOT/main"
git init --bare -q "$ORIGIN"
git clone -q "$ORIGIN" "$MAIN"
gx "$MAIN" config user.email unit@tron.local
gx "$MAIN" config user.name "tron unit"
gx "$MAIN" checkout -q -B master
echo base > "$MAIN/app.txt"
gx "$MAIN" add -A; gx "$MAIN" commit -q -m init; gx "$MAIN" push -q -u origin master
gx "$MAIN" checkout -q -b feat master; gx "$MAIN" push -q -u origin feat
gx "$MAIN" checkout -q master
# remote-only branch: push it, then drop the local head so only origin/<b> remains
gx "$MAIN" checkout -q -b remote-only master; gx "$MAIN" push -q -u origin remote-only
gx "$MAIN" checkout -q master; gx "$MAIN" branch -q -D remote-only

# --- gp_main_repo: primary checkout, from main AND from a linked worktree -----
MR="$(cd "$MAIN" && gp_main_repo)"
[[ "$MR" == "$MAIN" ]] || fail "gp_main_repo from main should be MAIN (got: $MR)"
WT="$ROOT/wt"; gx "$MAIN" worktree add -q "$WT" feat
MR_WT="$(cd "$WT" && gp_main_repo)"
[[ "$MR_WT" == "$MAIN" ]] || fail "gp_main_repo from a worktree should still be MAIN (got: $MR_WT)"
pass "gp_main_repo → resolves the primary checkout from main and from a worktree"

# --- gp_in_worktree ----------------------------------------------------------
if (cd "$MAIN" && gp_in_worktree "$MAIN"); then fail "main checkout should NOT be a worktree"; fi
(cd "$WT" && gp_in_worktree "$MAIN") || fail "linked worktree should be detected as a worktree"
# explicit path form: gp_in_worktree <main> <path>
gp_in_worktree "$MAIN" "$WT" || fail "gp_in_worktree <main> <wt-path> should be true"
gp_in_worktree "$MAIN" "$MAIN" && fail "gp_in_worktree <main> <main> should be false"
pass "gp_in_worktree → true for a linked worktree, false for the primary checkout"

# --- gp_dirty ----------------------------------------------------------------
[[ -z "$(gp_dirty "$MAIN")" ]] || fail "clean tree should yield empty gp_dirty"
echo change >> "$MAIN/app.txt"
[[ -n "$(gp_dirty "$MAIN")" ]] || fail "modified tree should yield porcelain output"
gx "$MAIN" checkout -q -- app.txt   # restore clean
[[ -z "$(gp_dirty "$MAIN")" ]] || fail "tree should be clean again after restore"
pass "gp_dirty → empty when clean, porcelain lines when dirty"

# --- gp_has_branch: local / remote-only / absent -----------------------------
gp_has_branch "$MAIN" master     || fail "gp_has_branch should find local master"
gp_has_branch "$MAIN" feat       || fail "gp_has_branch should find local feat"
gp_has_branch "$MAIN" remote-only || fail "gp_has_branch should find origin/remote-only via remote ref"
gp_has_branch "$MAIN" nope-branch && fail "gp_has_branch should be false for an absent branch"
pass "gp_has_branch → true for local + origin-only refs, false when absent"

# --- gp_merge_into error stage: bogus target → error:checkout-<target>, rc 1 --
rc=0; OUT="$(gp_merge_into "$MAIN" no-such-branch feat)" || rc=$?
[[ "$rc" -eq 1 ]] || fail "gp_merge_into into a missing target should rc 1 (got $rc)"
[[ "$OUT" == "error:checkout-no-such-branch" ]] || fail "expected error:checkout-no-such-branch (got: $OUT)"
# the failed checkout must not have moved the main checkout off master
[[ "$(gx "$MAIN" rev-parse --abbrev-ref HEAD)" == master ]] || fail "main checkout left off master after failed checkout"
pass "gp_merge_into → error:checkout-<target> + rc 1 on a nonexistent target (HEAD unmoved)"

echo ""
echo "✅ git-promote unit test PASSED ($PASS checks)"
