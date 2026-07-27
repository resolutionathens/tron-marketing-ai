#!/usr/bin/env bash
# Lints every skills/*/scripts/*.sh (the deterministic script backbones, per
# CLAUDE.md → Deterministic scripts) against the doc that resolves its path at
# runtime — the skill's own SKILL.md, one of its reference/*.md files, or,
# for the runner-delegated audit skills, the matching agents/*-runner.md —
# and fails if that doc has lost the
# CLAUDE_SKILL_DIR -> CLAUDE_PLUGIN_ROOT -> Claude/Codex cache/marketplace/release-store
# SKILL_DIR fallback (see CLAUDE.md -> Path resolution). Silently dropping the
# fallback is the exact regression MD-1987 exists to catch.
#
# It must use the shared resolver (MD-2351). The legacy null-glob-safe find
# idiom (MD-2320), which locates the skill dir directly, is no longer accepted:
# permitting both variants is what let 17 of 20 skills drift onto a bootstrap
# that never calls the resolver, and so never applied its version-then-rank
# precedence across cache/marketplace/release-store copies (MD-2450).
#
#   bash tools/lint/check-fastpath-resolvers.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

fail=0
checked=0

shopt -s nullglob
for script in skills/*/scripts/*.sh; do
  base="$(basename "$script")"
  [[ "$base" == test-* ]] && continue
  skill="$(basename "$(dirname "$(dirname "$script")")")"
  checked=$((checked + 1))

  found=0
  docs=("skills/$skill/SKILL.md")
  # A skill may push the resolver into one of its own reference/ files when
  # SKILL.md gets long (CLAUDE.md -> Reference files & progressive disclosure).
  docs+=("skills/$skill"/reference/*.md)
  docs+=(agents/*-runner.md)
  for doc in "${docs[@]}"; do
    [ -f "$doc" ] || continue
    grep -qF "scripts/$base" "$doc" || continue
    grep -qE 'find ~/\.claude/plugins/cache ~/\.claude/plugins/marketplaces ~/\.codex/plugins/cache ~/\.codex/plugins/marketplaces' "$doc" || continue
    grep -qF 'tron-os/tron-releases/versions' "$doc" || continue
    grep -qF 'tools/skill/resolve-skill-dir.sh' "$doc" || continue
    grep -qF 'CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..' "$doc" || continue
    grep -qF 'bash "$RESOLVER" "$name"' "$doc" || continue
    found=1
    break
  done

  if [ "$found" = 1 ]; then
    echo "OK   $skill ($base)"
  else
    echo "FAIL $skill ($base) — no SKILL.md, reference/*.md, or agents/*-runner.md resolves it through tools/skill/resolve-skill-dir.sh with the Claude/Codex cache/marketplace/release-store fallback; a hand-rolled find for */skills/\$name no longer counts (MD-2450)"
    fail=1
  fi
done

echo
if [ "$fail" = 1 ]; then
  echo "check-fastpath-resolvers: FAILED (checked $checked scripted skills)"
  exit 1
fi
echo "check-fastpath-resolvers: OK (checked $checked scripted skills)"
