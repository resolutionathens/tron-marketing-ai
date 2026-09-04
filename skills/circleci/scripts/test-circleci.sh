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
# Run under both bash and zsh — MD-2811: the old `[[ =~ ]]`/BASH_REMATCH
# construct silently produced an empty slug under zsh (zsh populates regex
# capture groups differently than bash), the same failure mode MD-2661 fixed
# in skills/git-pr/scripts/resolve-origin-slug.sh. derive_slug now uses the
# same POSIX case/parameter-expansion approach, so it must behave identically
# under both shells.
for SHELL_BIN in bash zsh; do
  command -v "$SHELL_BIN" >/dev/null 2>&1 || { echo "skip: $SHELL_BIN not installed" >&2; continue; }

  D="$(mkrepo "gh-ssh-$SHELL_BIN" 'git@github.com:Facilitron/marketing-pages.git')"
  O="$("$SHELL_BIN" "$SCRIPT" slug --repo "$D")"; echo "  → ($SHELL_BIN) $O"
  has "$O" '"ok":true' "($SHELL_BIN) ssh github remote derives a slug"
  has "$O" '"slug":"gh/Facilitron/marketing-pages"' "($SHELL_BIN) ssh remote → gh/Facilitron/marketing-pages"
  pass "($SHELL_BIN) slug: git@github.com:Org/repo.git → gh/Org/repo"

  D="$(mkrepo "gh-https-$SHELL_BIN" 'https://github.com/Facilitron/marketing-pages.git')"
  O="$("$SHELL_BIN" "$SCRIPT" slug --repo "$D" || true)"
  has "$O" '"slug":"gh/Facilitron/marketing-pages"' "($SHELL_BIN) https remote → gh/Facilitron/marketing-pages"
  pass "($SHELL_BIN) slug: https://github.com/Org/repo.git → gh/Org/repo"

  D="$(mkrepo "bb-$SHELL_BIN" 'git@bitbucket.org:team/thing.git')"
  O="$("$SHELL_BIN" "$SCRIPT" slug --repo "$D" || true)"
  has "$O" '"slug":"bb/team/thing"' "($SHELL_BIN) bitbucket remote → bb/team/thing"
  pass "($SHELL_BIN) slug: bitbucket → bb/team/repo"

  D="$(mkrepo "nested-$SHELL_BIN" 'https://github.com/Facilitron/nested/marketing-pages.git')"
  O="$("$SHELL_BIN" "$SCRIPT" slug --repo "$D" 2>/dev/null || true)"; echo "  → ($SHELL_BIN) $O"
  has "$O" '"ok":false' "($SHELL_BIN) nested path → ok:false"
  pass "($SHELL_BIN) slug: extra path segment → ok:false"

  D="$(mkrepo "norem-$SHELL_BIN" '')"
  O="$("$SHELL_BIN" "$SCRIPT" slug --repo "$D" 2>/dev/null || true)"; echo "  → ($SHELL_BIN) $O"
  has "$O" '"ok":false' "($SHELL_BIN) no remote → ok:false"
  pass "($SHELL_BIN) slug: no origin remote → ok:false"

  # need_slug (not just cmd_slug) must resolve a slug correctly under zsh too —
  # `pipelines` calls need_slug before any network access, so its offline
  # failure path on a repo with no origin remote exercises need_slug itself.
  # need_slug's error JSON is produced inside a `slug="$(need_slug)"` command
  # substitution, so it is captured into that variable rather than printed —
  # only the exit code (2, via `set -e` on the failing assignment) is
  # observable from outside, which is what this asserts.
  D="$(mkrepo "need-slug-norem-$SHELL_BIN" '')"
  rc=0; "$SHELL_BIN" "$SCRIPT" pipelines --repo "$D" >/dev/null 2>&1 || rc=$?
  echo "  → ($SHELL_BIN) rc=$rc"
  [[ "$rc" == 2 ]] || fail "($SHELL_BIN) pipelines with no origin remote should exit 2 via need_slug (got $rc)"
  pass "($SHELL_BIN) pipelines (need_slug consumer) with no origin remote → exit 2"
done

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

has "$O" '"source":"builtin-fallback"' "the built-in table labels itself as the fallback"
pass "deploy-url without a declared table → answers from the labelled built-in"

OTHER="$(mkrepo other 'git@github.com:Facilitron/marketing-dynamic-landing-pages.git')"
O="$(bash "$SCRIPT" deploy-url dev --repo "$OTHER" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"ok":false' "a repo with neither a declared table nor a built-in one fails"
has "$O" 'README' "reason points at the repo README"
pass "deploy-url for a sibling repo → ok:false (check README)"

# --- deploy-url from the repo's own profile ----------------------------------
# The branch→URL map is the consuming repo's fact. When it declares one, that
# table wins over the plugin's built-in — including for marketing-pages itself,
# so the built-in can be deleted once the repo declares the block.
DECL="$(mkrepo declared 'git@github.com:Facilitron/marketing-pages.git')"
mkdir -p "$DECL/.tron"
cat > "$DECL/.tron/content-profile.json" <<'JSON'
{
  "version": 1,
  "deploy": {
    "branches": {
      "dev": { "environment": "Development", "url": "https://declared-dev.example.com" },
      "production": { "environment": "Production", "url": "https://declared-prod.example.com" }
    }
  }
}
JSON
O="$(bash "$SCRIPT" deploy-url dev --repo "$DECL")"; echo "  → $O"
has "$O" '"source":"repo-profile"' "a declared table is labelled as the repo's"
has "$O" 'declared-dev.example.com' "the declared URL wins over the built-in marketing-pages table"
pass "deploy-url → the repo's declared deploy.branches overrides the built-in"

O="$(bash "$SCRIPT" deploy-url staging --repo "$DECL" 2>/dev/null || true)"; echo "  → $O"
has "$O" '"ok":false' "a branch the repo does not declare has no URL"
has "$O" '"declared":\["dev","production"\]' "failure lists what the repo does declare"
pass "deploy-url <undeclared branch> → ok:false listing the declared ones"

# A profile that exists but does not read is NOT the same as no profile: falling
# back to the built-in would hand a marketing-pages checkout the plugin's table
# while the repo was actively trying to override it.
printf 'not json\n' > "$DECL/.tron/content-profile.json"
rc=0; O="$(bash "$SCRIPT" deploy-url dev --repo "$DECL" 2>/dev/null)" || rc=$?
echo "  → $O"
[[ "$rc" == 1 ]] || fail "an unreadable profile should exit 1, not fall back (got $rc)"
has "$O" 'does not read as a version-1 profile' "the refusal names why it refused"
pass "malformed profile → exit 1 rather than a silent fall back to the built-in"

# --- help output must not spill past the header comment ----------------------
# Both help paths slice this file's own header. A line-numbered range silently
# drifts every time the header grows; assert the boundary instead.
O="$(bash "$SCRIPT" --help)"
has "$O" 'deploy-url <branch>' "help lists the deploy-url subcommand"
has "$O" '2 usage error' "help includes the LAST header line"
grep -q 'set -euo pipefail' <<<"$O" && fail "help spilled past the header into the script body"
pass "--help prints the whole header comment and nothing after it"

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

# --- fallback path: missing token error & graceful handling -----------------
# Test that resolve_circleci_token does not abort under set -euo pipefail
# when CIRCLECI_TOKEN is missing from ~/.env.
TMPENV="$(mktemp)"
trap 'rm -f "$TMPENV"' EXIT
# Create a .env without CIRCLECI_TOKEN
echo "OTHER_VAR=value" > "$TMPENV"
HOME_BACKUP="$HOME"
export HOME="$(dirname "$TMPENV")"
ln -s "$TMPENV" "$HOME/.env" 2>/dev/null || true
O="$(bash -c "source $SCRIPT 2>/dev/null; resolve_circleci_token" || echo 'exit_1')"
[[ "$O" == "exit_1" || -z "$O" ]] || fail "resolve_circleci_token should handle missing CIRCLECI_TOKEN gracefully (got: $O)"
pass "resolve_circleci_token handles missing key gracefully under set -euo pipefail"
export HOME="$HOME_BACKUP"
rm -f "$HOME/.env" 2>/dev/null || true

echo ""
echo "✅ circleci smoke PASSED ($PASS checks)"
