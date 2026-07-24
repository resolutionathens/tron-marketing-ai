#!/usr/bin/env bash
# Regression test for the shared SKILL_DIR resolution snippet (MD-2320).
#
# The snippet is embedded verbatim across ~25 SKILL.md / agents / scripts. It
# used to resolve via a `for d in <glob> <glob>; do …; done` loop, which aborts
# under zsh the moment ANY candidate glob matches nothing ("no matches found") —
# and since the release-store provisioning migration removed the tron entry from
# ~/.claude/plugins/marketplaces, the marketplaces glob now always matches
# nothing, so every dispatched worker tripped on the first skill-script use.
#
# This test extracts the REAL resolver line shipped in skills/start-ticket/
# SKILL.md (so it can't silently drift from what ships) and runs it under BOTH
# /bin/bash and /bin/zsh against a fixture that reproduces today's reality:
#   - the Claude and Codex plugin caches have several versions of the skill
#   - the marketplaces root exists but has NO matching skill (the abort trigger)
#   - the release store holds an older copy
# It asserts the snippet resolves without aborting, picks the highest version
# (sort -V semantics, incl. 0.35.10 > 0.35.2), and falls back to the release
# store when the cache is absent.
#
#   bash tools/lint/test-skill-dir-resolver.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SKILL_MD="$ROOT/skills/start-ticket/SKILL.md"
NAME=start-ticket
PROBE="scripts/start-ticket.sh"

PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/skill-dir-resolver.XXXXXX")"
trap 'rm -rf "$FIX"' EXIT

echo "skill-dir-resolver regression: fixture=$FIX"

# --- pull the actual resolver line out of the shipped SKILL.md ---------------
RESOLVER_LINE="$(grep -F '|| SKILL_DIR="$(find' "$SKILL_MD" | head -1)"
[ -n "$RESOLVER_LINE" ] || fail "could not find the find-based resolver line in $SKILL_MD"
# guard: it must be the null-glob-safe find idiom, never the old for/glob loop
case "$RESOLVER_LINE" in
  *"for d in ~/.claude/plugins/cache"*) fail "resolver still uses the zsh-unsafe for/glob loop" ;;
esac
printf '%s' "$RESOLVER_LINE" | grep -qF 'tron-os/tron-releases/versions' \
  || fail "resolver line is missing the release-store candidate root"
printf '%s' "$RESOLVER_LINE" | grep -qF '~/.codex/plugins/cache' \
  || fail "resolver line is missing the Codex cache candidate root"
printf '%s' "$RESOLVER_LINE" | grep -qF '|| true' \
  || fail "resolver line dropped the '|| true' guard — find's non-zero on a missing root will abort under set -e"
pass "extracted the shipped find-based resolver line"

# --- a runner that execs the real snippet with HOME pointed at the fixture ----
# name/SKILL_DIR are what the snippet reads; HOME redirects the ~ globs at $FIX.
# `set -euo pipefail` mirrors the real deterministic scripts (e.g. generate-card.sh)
# that embed this snippet: `find` returns non-zero when a candidate root is absent,
# and under pipefail that must NOT abort the command substitution before the
# friendly "not found" guard — the snippet's trailing `|| true` is what ensures it
# doesn't. Scenario 2 (cache root removed) exercises exactly that case.
make_runner() {
  cat >"$FIX/run.sh" <<EOF
set -euo pipefail
name=$NAME
SKILL_DIR=""
$RESOLVER_LINE
printf 'SKILL_DIR=%s\n' "\$SKILL_DIR"
EOF
}

seed() { # seed <relpath-under-HOME> — plants the probe script for $NAME there
  local f="$FIX/$1/$NAME/$PROBE"
  mkdir -p "$(dirname "$f")"
  printf '#!/usr/bin/env bash\necho hi\n' > "$f"
}

run_in() { # run_in <shell> -> prints resolved SKILL_DIR (relative to $FIX)
  local out
  out="$(HOME="$FIX" "$1" "$FIX/run.sh")" || fail "$1 aborted running the resolver (exit $?)"
  printf '%s' "${out#SKILL_DIR=}"
}

CACHE=".claude/plugins/cache/tron/tron-engineer"
CODEX_CACHE=".codex/plugins/cache/tron/tron-engineer"
MKT=".claude/plugins/marketplaces"
STORE="Library/Application Support/tron-os/tron-releases/versions"

# ── Scenario 1: cache has 3 versions; marketplaces present but NO match;
#    release store holds an older copy. Highest cache version must win. ────────
seed "$CACHE/0.34.0/skills"
seed "$CACHE/0.35.2/skills"
seed "$CACHE/0.35.10/skills"                      # 0.35.10 > 0.35.2 under sort -V
mkdir -p "$FIX/$MKT/cloudflare/skills/other"       # marketplaces root exists, no $NAME
seed "$STORE/0.30.0/claude/tron-engineer-v0.30.0/skills"
make_runner

want="$FIX/$CACHE/0.35.10/skills/$NAME"
for sh in /bin/bash /bin/zsh; do
  [ -x "$sh" ] || { echo "  (skip $sh — not present)"; continue; }
  got="$(run_in "$sh")"
  [ "$got" = "$want" ] || fail "$sh: expected highest cache version $want, got '$got'"
  pass "$sh: no-marketplace-match reality resolves to highest version (sort -V: 0.35.10 wins)"
done

# ── Scenario 2: no cache dir at all — resolver must fall back to the release
#    store, still without aborting under either shell. ─────────────────────────
rm -rf "$FIX/.claude/plugins/cache"
want2="$FIX/$STORE/0.30.0/claude/tron-engineer-v0.30.0/skills/$NAME"
for sh in /bin/bash /bin/zsh; do
  [ -x "$sh" ] || continue
  got="$(run_in "$sh")"
  [ "$got" = "$want2" ] || fail "$sh: expected release-store fallback $want2, got '$got'"
  pass "$sh: falls back to the release store when the cache is absent"
done

# ── Scenario 3: Codex has its own cache path. A dispatched Codex worker may
# have neither CLAUDE_SKILL_DIR nor CLAUDE_PLUGIN_ROOT, so this must work even
# after the Claude cache and release store are unavailable. ───────────────────
rm -rf "$FIX/Library"
seed "$CODEX_CACHE/0.36.1/skills"
want3="$FIX/$CODEX_CACHE/0.36.1/skills/$NAME"
for sh in /bin/bash /bin/zsh; do
  [ -x "$sh" ] || continue
  got="$(run_in "$sh")"
  [ "$got" = "$want3" ] || fail "$sh: expected Codex cache fallback $want3, got '$got'"
  pass "$sh: falls back to the Codex cache when Claude and release-store copies are absent"
done

echo "skill-dir-resolver regression: $PASS passed"
