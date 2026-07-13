#!/usr/bin/env bash
# Lints every skills/*/scripts/*.sh (the deterministic script backbones, per
# CLAUDE.md → Deterministic scripts) against the doc that resolves its path at
# runtime — the skill's own SKILL.md, or, for the runner-delegated audit
# skills, the matching agents/*-runner.md — and fails if that doc has lost the
# CLAUDE_SKILL_DIR -> CLAUDE_PLUGIN_ROOT -> cache/marketplace SKILL_DIR
# fallback (see CLAUDE.md -> Path resolution). Silently dropping the
# cache/marketplace fallback is the exact regression MD-1987 exists to catch.
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
  docs+=(agents/*.md)
  for doc in "${docs[@]}"; do
    [ -f "$doc" ] || continue
    grep -qF "scripts/$base" "$doc" || continue
    grep -qE 'plugins/cache/\*/\*/\*/skills/\$name' "$doc" || continue
    grep -qE 'plugins/marketplaces/\*/skills/\$name' "$doc" || continue
    found=1
    break
  done

  if [ "$found" = 1 ]; then
    echo "OK   $skill ($base)"
  else
    echo "FAIL $skill ($base) — no SKILL.md or agents/*.md resolves it with the cache/marketplace SKILL_DIR fallback"
    fail=1
  fi
done

echo
if [ "$fail" = 1 ]; then
  echo "check-fastpath-resolvers: FAILED (checked $checked scripted skills)"
  exit 1
fi
echo "check-fastpath-resolvers: OK (checked $checked scripted skills)"
