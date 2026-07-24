#!/usr/bin/env bash
# Smoke for check-fastpath-resolvers.sh: confirms it passes on the real repo,
# and — the actual regression test — confirms it FAILS a synthetic skill
# whose SKILL.md is missing the Claude/Codex cache/marketplace SKILL_DIR fallback, and
# passes again once the fallback is restored.
#
#   bash tools/lint/test-check-fastpath-resolvers.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-fastpath-resolvers.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/fastpath-lint-smoke.XXXXXX")"
PASS=0
pass() { echo "  ✓ $*"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $*" >&2; find "$FIXTURE" -depth -delete 2>/dev/null || true; exit 1; }
trap 'find "$FIXTURE" -depth -delete 2>/dev/null || true' EXIT

echo "check-fastpath-resolvers smoke: fixture=$FIXTURE"

# --- real repo passes clean --------------------------------------------------
bash "$SCRIPT" "$REPO_ROOT" >/dev/null || fail "check-fastpath-resolvers.sh should pass on the real repo"
pass "passes clean on the real repo"

# --- synthetic skill missing the fallback fails ------------------------------
mkdir -p "$FIXTURE/skills/widget/scripts" "$FIXTURE/agents"
cat >"$FIXTURE/skills/widget/scripts/widget.sh" <<'EOF'
#!/usr/bin/env bash
echo widget
EOF
cat >"$FIXTURE/skills/widget/SKILL.md" <<'EOF'
# /widget
1. Resolve the script path.
   ```bash
   name=widget
   SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
   bash "$SKILL_DIR/scripts/widget.sh"
   ```
EOF

if bash "$SCRIPT" "$FIXTURE" >/tmp/fastpath-smoke-out.$$ 2>&1; then
  fail "should have failed a skill missing the cache/marketplace fallback"
fi
grep -q "FAIL widget" /tmp/fastpath-smoke-out.$$ || fail "failure output should name the broken skill"
pass "catches a SKILL.md missing the cache/marketplace fallback"

# --- restoring the shared resolver bootstrap makes it pass again -------------
cat >"$FIXTURE/skills/widget/SKILL.md" <<'EOF'
# /widget
1. Resolve the script path.
   ```bash
   name=widget
   RESOLVER="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
   [ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
   SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/widget.sh)"
   bash "$SKILL_DIR/scripts/widget.sh"
   ```
EOF
bash "$SCRIPT" "$FIXTURE" >/dev/null || fail "should pass once the fallback is restored"
pass "passes once the cache/marketplace fallback is restored"

rm -f /tmp/fastpath-smoke-out.$$
echo "check-fastpath-resolvers smoke: $PASS passed"
