#!/usr/bin/env bash
# Smoke for open-worktree.sh + worktree-lib.sh. The cmux/wt I/O isn't exercised
# (no GUI in the sandbox), but the deterministic spine is fully testable with a
# plain `git worktree add`: path resolution, env-file carry-over, the empty
# node_modules flag, and the usage/error contract.
#
#   bash skills/open-worktree/scripts/test-open-worktree.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/open-worktree.sh"
LIB="$(cd "$HERE/../../../tools/worktree" && pwd)/worktree-lib.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/open-worktree-smoke.XXXXXX")"
ROOT="$(cd "$ROOT" && pwd -P)"   # canonicalize: macOS /var → /private/var, matching git's output
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -qF "$2" <<<"$1" || fail "$3 — got: $1"; }

# Build a primary checkout with one commit, plus a worktree on a feature branch.
MAIN="$ROOT/main"
mkdir -p "$MAIN"; git -C "$MAIN" init -q
git -C "$MAIN" config user.email t@t.t; git -C "$MAIN" config user.name t
echo hi > "$MAIN/README.md"; git -C "$MAIN" add .; git -C "$MAIN" commit -qm init
# gitignored secrets that must follow the worktree
printf 'X=1\n' > "$MAIN/.env.local"; printf 'Y=2\n' > "$MAIN/.dev.vars"
WT="$ROOT/wt-feature"
git -C "$MAIN" worktree add -q -b feature "$WT" >/dev/null 2>&1

echo "open-worktree smoke: root=$ROOT"

# --- worktree-lib pure helpers ----------------------------------------------
# shellcheck source=/dev/null
source "$LIB"
P="$(wl_worktree_path_for_branch feature "$MAIN")"
[[ "$P" == "$WT" ]] || fail "wl_worktree_path_for_branch should find the feature worktree (got: $P)"
pass "wl_worktree_path_for_branch feature → the worktree path"

wl_worktree_path_for_branch nonesuch "$MAIN" >/dev/null 2>&1 && fail "missing branch should return non-zero"
pass "wl_worktree_path_for_branch <missing> → non-zero"

M="$(wl_main_checkout "$WT")"
[[ "$M" == "$MAIN" ]] || fail "wl_main_checkout should resolve the primary checkout (got: $M)"
pass "wl_main_checkout → primary checkout (from inside a worktree)"

# --- full script: resolve + carry env + node_modules flag --------------------
O="$(bash "$SCRIPT" --branch feature --repo "$MAIN" --no-switch)"; echo "  → $O"
has "$O" '"ok":true' "resolves the existing worktree"
has "$O" "\"worktreePath\":\"$WT\"" "reports the worktree path"
has "$O" '".env.local"' "carries .env.local into the worktree"
has "$O" '".dev.vars"' "carries .dev.vars into the worktree"
has "$O" '"nodeModulesEmpty":true' "flags the empty node_modules"
[[ -f "$WT/.env.local" ]] || fail ".env.local should now exist in the worktree"
pass "open-worktree --branch feature → resolves, carries env, flags node_modules"

# second run is idempotent: env already present, nothing re-reported as copied
O="$(bash "$SCRIPT" --branch feature --repo "$MAIN" --no-switch)"
has "$O" '"envCopied":[]' "second run doesn't re-copy existing env files"
pass "open-worktree is idempotent on env carry-over"

# node_modules present → flag flips false
mkdir -p "$WT/node_modules/pkg"; echo '{}' > "$WT/node_modules/pkg/package.json"
O="$(bash "$SCRIPT" --branch feature --repo "$MAIN" --no-switch)"
has "$O" '"nodeModulesEmpty":false' "populated node_modules → false"
pass "node_modules populated → nodeModulesEmpty:false"

# --- error / usage contract --------------------------------------------------
O="$(bash "$SCRIPT" --branch ghost --repo "$MAIN" --no-switch 2>/dev/null || true)"; echo "  → $O"
has "$O" '"ok":false' "unknown branch → ok:false"
has "$O" 'worktree-not-found' "unknown branch reports worktree-not-found"
pass "open-worktree --branch <missing> → ok:false (worktree-not-found)"

rc=0; bash "$SCRIPT" --bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown flag should exit 2 (got $rc)"
pass "unknown flag → exit 2"

echo ""
echo "✅ open-worktree smoke PASSED ($PASS checks)"
