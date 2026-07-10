#!/usr/bin/env bash
# Smoke for start-ticket's deterministic spine. The wt/acli/gh I/O can't run in a
# temp sandbox, so this tests the PURE lib (ref detection, slugify, branch names,
# env-file copy) exhaustively + offline, then syntax-checks the orchestration
# script and its tool-absent / ambiguous-ref error paths.
#
#   bash skills/start-ticket/scripts/test-start-ticket.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/start-ticket.sh"
export CLAUDE_PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
source "$CLAUDE_PLUGIN_ROOT/tools/ticket/ticket-lib.sh"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }
eq() { [[ "$1" == "$2" ]] || fail "$3 — expected [$2], got [$1]"; }

echo "start-ticket smoke (CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT)"

# ── ref detection ────────────────────────────────────────────────────────────
eq "$(tl_detect_ref 'MD-1234')" "jira MD-1234" "bare Jira key"
eq "$(tl_detect_ref 'CCAL-456')" "jira CCAL-456" "Jira key, other project"
eq "$(tl_detect_ref 'https://facilitron.atlassian.net/browse/MD-1658')" "jira MD-1658" "Jira browse URL"
eq "$(tl_detect_ref '#42')" "gh 42" "current-repo #N"
eq "$(tl_detect_ref 'Facilitron/marketing-pages#185')" "gh 185 Facilitron/marketing-pages" "owner/repo#N"
eq "$(tl_detect_ref 'https://github.com/acme/app/issues/7')" "gh 7 acme/app" "GitHub issue URL"
eq "$(tl_detect_ref '42'; echo "rc=$?")" $'ambiguous\nrc=1' "bare number is ambiguous (rc=1)"
pass "tl_detect_ref classifies every ref shape (jira/gh/url/ambiguous)"

# ── slugify ──────────────────────────────────────────────────────────────────
eq "$(tl_slugify 'Add BAS logo to product')" "add-bas-logo-to-product" "basic slug"
eq "$(tl_slugify '  Fix: panelist  name (typo!) ')" "fix-panelist-name-typo" "punctuation + spaces collapse"
eq "$(tl_slugify 'ALLCAPS Heading')" "allcaps-heading" "lowercased"
LONG="$(tl_slugify 'this is an extremely long ticket summary that should be trimmed on a word boundary not mid word')"
[[ ${#LONG} -le 50 ]] || fail "slug should be ≤50 chars, got ${#LONG}: $LONG"
[[ "$LONG" != *- ]] || fail "slug should not end with a hyphen: $LONG"
pass "tl_slugify lowercases, collapses punctuation, trims on a word boundary"

# ── branch names ─────────────────────────────────────────────────────────────
eq "$(tl_branch_name jira MD-1658 'Add BAS logo')" "MD-1658-add-bas-logo" "jira branch"
eq "$(tl_branch_name gh 185 'Improve better-auth UX')" "issue-185-improve-better-auth-ux" "gh branch is issue-prefixed"
pass "tl_branch_name builds <KEY>-slug / issue-<N>-slug"

# ── env-file carry-over ──────────────────────────────────────────────────────
T="$(mktemp -d "${TMPDIR:-/tmp}/start-ticket-env.XXXXXX")"
mkdir -p "$T/main" "$T/wt"
printf 'x\n' > "$T/main/.env"
printf 'x\n' > "$T/main/.env.local"
printf 'x\n' > "$T/main/.dev.vars"
printf 'x\n' > "$T/main/README.md"          # NOT a secret file — must be skipped
printf 'old\n' > "$T/wt/.env.local"         # already present — must NOT be clobbered
COPIED="$(tl_copy_env_files "$T/main" "$T/wt" | sort | tr '\n' ' ')"
eq "$COPIED" ".dev.vars .env " "copies the secret-file set, skips README + existing"
[[ -f "$T/wt/.env" ]] || fail "env: .env not copied"
[[ -f "$T/wt/.dev.vars" ]] || fail "env: .dev.vars not copied"
[[ ! -f "$T/wt/README.md" ]] || fail "env: README.md should not be copied"
eq "$(cat "$T/wt/.env.local")" "old" "existing .env.local must not be clobbered"
rm -rf "$T"
pass "tl_copy_env_files carries .env*/.dev.vars*, skips non-secrets, never clobbers"

# ── node_modules symlinks (root + nested workspaces) ─────────────────────────
N="$(mktemp -d "${TMPDIR:-/tmp}/start-ticket-nm.XXXXXX")"
mkdir -p "$N/main/node_modules/dep"                       # root deps
mkdir -p "$N/main/control-plane/web/node_modules/pkg"     # nested workspace deps
mkdir -p "$N/main/node_modules/.bin"
mkdir -p "$N/main/deep/a/b/node_modules"                  # depth 4 — out of bounds, must be skipped
mkdir -p "$N/wt/control-plane/web"                        # mirror dir tree (no deps yet)
mkdir -p "$N/wt/already/node_modules"                     # pre-existing — must NOT be clobbered
LINKED="$(tl_link_node_modules "$N/main" "$N/wt" | sort | tr '\n' ' ')"
eq "$LINKED" "control-plane/web/node_modules node_modules " "links root + nested, skips too-deep"
[[ -L "$N/wt/node_modules" ]] || fail "nm: root node_modules not symlinked"
[[ -d "$N/wt/node_modules/dep" ]] || fail "nm: root symlink doesn't resolve to deps"
[[ -L "$N/wt/control-plane/web/node_modules" ]] || fail "nm: nested node_modules not symlinked"
[[ -d "$N/wt/control-plane/web/node_modules/pkg" ]] || fail "nm: nested symlink doesn't resolve"
[[ ! -L "$N/wt/already/node_modules" ]] || fail "nm: pre-existing node_modules must not be clobbered"
rm -rf "$N"
pass "tl_link_node_modules symlinks root + nested node_modules, skips too-deep + existing"

# ── node_modules symlinks must be invisible to git (MD-2028) ────────────────
# A directory-only ignore pattern ("node_modules/") does not match a symlink
# named node_modules, so git add -A would stage it. Prove the repo's actual
# .gitignore (no trailing slash) covers the symlinks tl_link_node_modules creates.
G2="$(mktemp -d "${TMPDIR:-/tmp}/start-ticket-gi.XXXXXX")"
mkdir -p "$G2/main/tools/imagekit/node_modules/dep"
git init -q "$G2/wt"
cp "$CLAUDE_PLUGIN_ROOT/.gitignore" "$G2/wt/.gitignore"
git -C "$G2/wt" add .gitignore
git -C "$G2/wt" -c user.email=s@t.local -c user.name=t commit -q -m "gitignore"
mkdir -p "$G2/wt/tools/imagekit"
tl_link_node_modules "$G2/main" "$G2/wt" >/dev/null
[[ -L "$G2/wt/tools/imagekit/node_modules" ]] || fail "gi: symlink not created"
git -C "$G2/wt" add -A
STAGED="$(git -C "$G2/wt" status --porcelain)"
[[ -z "$STAGED" ]] || fail "gi: .gitignore should hide node_modules symlinks from git add -A, got: $STAGED"
rm -rf "$G2"
pass "repo .gitignore matches node_modules symlinks, not just real directories"

# ── default-branch detection + ff-only base freshening (real git) ────────────
# Builds a throwaway bare origin + clone, pushes the default, advances origin
# beyond the clone, then proves tl_freshen_default fast-forwards the local
# default to origin's HEAD — the merge-base the next worktree must branch from.
gitq() { git -C "$1" "${@:2}"; }
for DEF in master main; do
  G="$(mktemp -d "${TMPDIR:-/tmp}/start-ticket-ff-$DEF.XXXXXX")"
  gitq "$G" init --bare -q "origin.git"
  git clone -q "$G/origin.git" "$G/main" 2>/dev/null
  gitq "$G/main" config user.email smoke@tron.local
  gitq "$G/main" config user.name "tron smoke"
  gitq "$G/main" checkout -q -B "$DEF"
  printf 'x\n' > "$G/main/f"; gitq "$G/main" add f; gitq "$G/main" commit -q -m init
  gitq "$G/main" push -q -u origin "$DEF"
  # origin/HEAD so detection resolves the default without touching the network
  gitq "$G/main" remote set-head origin "$DEF" >/dev/null 2>&1 || true
  eq "$(tl_default_branch "$G/main")" "$DEF" "tl_default_branch resolves $DEF"
  # advance origin one commit, then rewind the local default so it's behind
  printf 'y\n' >> "$G/main/f"; gitq "$G/main" commit -q -am ahead
  gitq "$G/main" push -q origin "$DEF"
  AHEAD="$(gitq "$G/main" rev-parse HEAD)"
  gitq "$G/main" reset -q --hard HEAD~1
  [[ "$(gitq "$G/main" rev-parse "$DEF")" != "$AHEAD" ]] || fail "$DEF: setup should leave local behind origin"
  OUTDEF="$(tl_freshen_default "$G/main")" || fail "$DEF: tl_freshen_default returned non-zero on a fast-forwardable base"
  eq "$OUTDEF" "$DEF" "tl_freshen_default echoes the default branch name ($DEF)"
  eq "$(gitq "$G/main" rev-parse "$DEF")" "$AHEAD" "tl_freshen_default fast-forwarded local $DEF to origin/$DEF"
  rm -rf "$G"
done
pass "tl_default_branch + tl_freshen_default freshen the base for main AND master repos"

# offline / no-origin: must NOT fail, must still report the default name
O="$(mktemp -d "${TMPDIR:-/tmp}/start-ticket-noorigin.XXXXXX")"
git init -q "$O"; gitq "$O" config user.email s@t.local; gitq "$O" config user.name t
gitq "$O" checkout -q -B master; printf 'x\n' > "$O/f"; gitq "$O" add f; gitq "$O" commit -q -m init
RC=0; OUTNO="$(tl_freshen_default "$O" 2>/dev/null)" || RC=$?
eq "$OUTNO" "master" "tl_freshen_default still reports the default with no origin"
[[ "$RC" -ne 0 ]] || fail "tl_freshen_default should return non-zero when there's no origin to fetch"
rm -rf "$O"
pass "tl_freshen_default degrades gracefully with no origin (non-fatal, names the default)"

# ── orchestration script: syntax + error paths ──────────────────────────────
bash -n "$SCRIPT" || fail "start-ticket.sh has a syntax error"
pass "start-ticket.sh parses (bash -n)"

OUT="$(bash "$SCRIPT" '42' --summary 'whatever' 2>/dev/null || true)"
grep -q '"error":"ambiguous-ref"' <<<"$OUT" || fail "ambiguous ref should error: $OUT"
pass "ambiguous bare-number ref → ambiguous-ref error (no worktree created)"

# With a real ref but wt absent from PATH, it fails fast and clean (no partial state).
OUT="$(PATH="/usr/bin:/bin" bash "$SCRIPT" 'MD-1' --branch 'MD-1-x' 2>/dev/null || true)"
grep -q '"error":"wt-not-found"' <<<"$OUT" || fail "missing wt should error wt-not-found: $OUT"
pass "missing wt → wt-not-found error (fails fast)"

echo ""
echo "✅ start-ticket smoke PASSED ($PASS checks)"
