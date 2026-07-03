#!/usr/bin/env bash
# Smoke for circleci.sh. The network subcommands need a real token + CircleCI
# API and aren't asserted here. The PURE surface is fully testable offline:
# slug derivation from a git remote, the marketing-pages deploy-url table, and
# the usage/error contract (exit 2 on bad input). Build throwaway git repos
# carrying each origin remote and assert the JSON + exit codes.
#
#   bash skills/circleci/scripts/test-circleci.sh
set -euo pipefail

# Hermetic git: a global `url.….insteadOf` rewrite (common on CI boxes) would
# change what `git remote get-url origin` returns and silently kill the slug
# checks under set -e.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/circleci.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/circleci-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; rm -rf "$ROOT"; exit 1; }
trap 'rm -rf "$ROOT"' EXIT
has() { grep -q "$2" <<<"$1" || fail "$3 — got: $1"; }

# Build a git repo with the given origin remote URL, return its path.
mkrepo() { # name remote-url
  local d="$ROOT/$1"; mkdir -p "$d"
  git -C "$d" init -q
  [[ -n "${2:-}" ]] && git -C "$d" remote add origin "$2"
  printf '%s' "$d"
}

echo "circleci smoke: root=$ROOT"

# --- slug derivation ---------------------------------------------------------
D="$(mkrepo gh-ssh 'git@github.com:Facilitron/marketing-pages.git')"
O="$(bash "$SCRIPT" slug --repo "$D")"; echo "  → $O"
has "$O" '"ok":true' "ssh github remote derives a slug"
has "$O" '"slug":"gh/Facilitron/marketing-pages"' "ssh remote → gh/Facilitron/marketing-pages"
pass "slug: git@github.com:Org/repo.git → gh/Org/repo"

D="$(mkrepo gh-https 'https://github.com/Facilitron/marketing-pages.git')"
O="$(bash "$SCRIPT" slug --repo "$D" || true)"
has "$O" '"slug":"gh/Facilitron/marketing-pages"' "https remote → gh/Facilitron/marketing-pages"
pass "slug: https://github.com/Org/repo.git → gh/Org/repo"

D="$(mkrepo bb 'git@bitbucket.org:team/thing.git')"
O="$(bash "$SCRIPT" slug --repo "$D" || true)"
has "$O" '"slug":"bb/team/thing"' "bitbucket remote → bb/team/thing"
pass "slug: bitbucket → bb/team/repo"

D="$(mkrepo norem '')"
O="$(bash "$SCRIPT" slug --repo "$D" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"ok":false' "no remote → ok:false"
pass "slug: no origin remote → ok:false"

# --- deploy-url table (marketing-pages) --------------------------------------
MP="$(mkrepo mp 'git@github.com:Facilitron/marketing-pages.git')"
dep() { bash "$SCRIPT" deploy-url "$1" --repo "$MP"; }

O="$(dep dev)"; echo "  → $O"
has "$O" '"ok":true' "dev resolves"
has "$O" 'morning-coast.facilitron.com' "dev → morning-coast alias (not dev.facilitron.com)"
pass "deploy-url dev → morning-coast.facilitron.com"

O="$(dep staging)"
has "$O" 'staging.facilitron.com' "staging → staging.facilitron.com"
pass "deploy-url staging → staging.facilitron.com"

O="$(dep production)"
has "$O" '"url":"https://www.facilitron.com"' "production → www.facilitron.com"
pass "deploy-url production → www.facilitron.com"

O="$(bash "$SCRIPT" deploy-url my-feature --repo "$MP" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"ok":false' "feature branch has no preview"
has "$O" 'merged to dev' "feature branch explains the no-preview reason"
pass "deploy-url <feature> → ok:false (no per-PR preview)"

OTHER="$(mkrepo other 'git@github.com:Facilitron/marketing-dynamic-landing-pages.git')"
O="$(bash "$SCRIPT" deploy-url dev --repo "$OTHER" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"ok":false' "non-marketing-pages repo routes to its README"
has "$O" 'README' "reason points at the repo README"
pass "deploy-url for a sibling repo → ok:false (check README)"

# --- usage / error contract --------------------------------------------------
rc=0; bash "$SCRIPT" deploy-url --repo "$MP" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "deploy-url with no branch should exit 2 (got $rc)"
pass "deploy-url with no branch → exit 2"

rc=0; bash "$SCRIPT" bogus-cmd >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "unknown subcommand should exit 2 (got $rc)"
pass "unknown subcommand → exit 2"

rc=0; bash "$SCRIPT" jobs >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "jobs without --workflow should exit 2 (got $rc)"
pass "jobs without --workflow → exit 2"

# help is exit 0 and mentions the contract
O="$(bash "$SCRIPT" help)"; has "$O" 'circleci.sh <subcommand>' "help prints usage"
pass "help → prints usage (exit 0)"

echo ""
echo "✅ circleci smoke PASSED ($PASS checks)"
