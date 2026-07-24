#!/usr/bin/env bash
# Regression coverage for the shared lifecycle SKILL_DIR resolver (MD-2351).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
RESOLVER="$ROOT/tools/skill/resolve-skill-dir.sh"
NAME=start-ticket
PROBE=scripts/start-ticket.sh

PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; exit 1; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/skill-dir-resolver.XXXXXX")"
trap 'find "$FIX" -depth -delete 2>/dev/null || true' EXIT

seed() {
  local base="$1"
  local file="$FIX/$base/$NAME/$PROBE"
  mkdir -p "$(dirname "$file")"
  printf '#!/usr/bin/env bash\n' >"$file"
}

run_in() {
  local shell="$1"
  HOME="$FIX" "$shell" "$RESOLVER" "$NAME" "$PROBE"
}

CACHE=".claude/plugins/cache/tron/tron-engineer"
CODEX_CACHE=".codex/plugins/cache/tron/tron-engineer"
MARKETPLACE=".claude/plugins/marketplaces/tron"
CODEX_MARKETPLACE=".codex/plugins/marketplaces/tron"
STORE="Library/Application Support/tron-os/tron-releases/versions"

seed "$CACHE/0.35.2/skills"
seed "$CACHE/0.35.10/skills"
mkdir -p "$FIX/.claude/plugins/marketplaces/cloudflare/skills/other"
seed "$STORE/0.30.0/claude/tron-engineer-v0.30.0/skills"

for shell in /bin/bash /bin/zsh; do
  [[ -x "$shell" ]] || continue
  got="$(run_in "$shell")"
  want="$FIX/$CACHE/0.35.10/skills/$NAME"
  [[ "$got" == "$want" ]] || fail "$shell cache: expected $want, got $got"
  pass "$shell resolves the newest cache with an unmatched marketplace"
done

find "$FIX/.claude/plugins/cache" -depth -delete
seed "$MARKETPLACE/0.36.0/skills"
for shell in /bin/bash /bin/zsh; do
  [[ -x "$shell" ]] || continue
  got="$(run_in "$shell")"
  want="$FIX/$MARKETPLACE/0.36.0/skills/$NAME"
  [[ "$got" == "$want" ]] || fail "$shell marketplace: expected $want, got $got"
  pass "$shell resolves a Claude marketplace install"
done

find "$FIX/.claude/plugins/marketplaces" -depth -delete
find "$FIX/Library" -depth -delete
seed "$CODEX_CACHE/0.36.1/skills"
seed "$CODEX_MARKETPLACE/0.36.2/skills"
for shell in /bin/bash /bin/zsh; do
  [[ -x "$shell" ]] || continue
  got="$(run_in "$shell")"
  want="$FIX/$CODEX_MARKETPLACE/0.36.2/skills/$NAME"
  [[ "$got" == "$want" ]] || fail "$shell Codex: expected $want, got $got"
  pass "$shell resolves the newest Codex install"
done

find "$FIX/.codex" -depth -delete
seed "$STORE/0.30.0/claude/tron-engineer-v0.30.0/skills"
for shell in /bin/bash /bin/zsh; do
  [[ -x "$shell" ]] || continue
  got="$(run_in "$shell")"
  want="$FIX/$STORE/0.30.0/claude/tron-engineer-v0.30.0/skills/$NAME"
  [[ "$got" == "$want" ]] || fail "$shell release: expected $want, got $got"
  pass "$shell resolves a release-store install"
done

find "$FIX/Library" -depth -delete
err="$FIX/missing.err"
if HOME="$FIX" /bin/bash "$RESOLVER" "$NAME" "$PROBE" 2>"$err"; then
  fail "missing skill unexpectedly resolved"
fi
rg -q "tron:$NAME: $PROBE not found" "$err" || fail "diagnostic does not name the skill and probe"
rg -q "$FIX/.claude/plugins/cache" "$err" || fail "diagnostic does not name searched roots"
pass "missing skill reports a non-empty diagnostic with the skill and searched roots"

for doc in skills/start-ticket/SKILL.md skills/git-dev/SKILL.md skills/git-pr/SKILL.md; do
  rg -q 'tools/skill/resolve-skill-dir.sh' "$ROOT/$doc" || fail "$doc does not use the shared resolver"
done
rg -q 'tools/skill/resolve-skill-dir.sh' "$ROOT/tools/image/generate-card.sh" \
  || fail "generate-card does not use the shared resolver"
pass "all four launch paths use the shared resolver"

echo "skill-dir-resolver regression: $PASS passed"
