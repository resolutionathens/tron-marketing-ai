#!/usr/bin/env bash
# Resolve the root of an installed Tron package and validate a skill's shared resources.
#
# Usage: resolve-plugin-root.sh <skill-name> <required-root-relative-path> [...]
set -euo pipefail

name="${1:-}"
first_required="${2:-}"
if [[ -z "$name" || -z "$first_required" ]]; then
  printf 'usage: resolve-plugin-root.sh <skill-name> <required-root-relative-path> [...]\n' >&2
  exit 2
fi
shift 2

self_dir="$(cd "$(dirname "$0")" && pwd)"
self_root="$(cd "$self_dir/../.." && pwd)"
claude_cache="$HOME/.claude/plugins/cache"
claude_marketplaces="$HOME/.claude/plugins/marketplaces"
codex_cache="$HOME/.codex/plugins/cache"
codex_marketplaces="$HOME/.codex/plugins/marketplaces"
opencode_config="$HOME/.config/opencode"
release_store="$HOME/Library/Application Support/tron-os/tron-releases/versions"

has_all() {
  local root="$1"
  shift
  [[ -f "$root/skills/$name/SKILL.md" ]] || return 1
  local required
  for required in "$first_required" "$@"; do
    [[ -e "$root/$required" ]] || return 1
  done
  return 0
}

if [[ -n "${TRON_PLUGIN_ROOT:-}" ]]; then
  if has_all "$TRON_PLUGIN_ROOT" "$@"; then
    printf '%s\n' "$TRON_PLUGIN_ROOT"
    exit 0
  fi
  printf 'tron:%s: TRON_PLUGIN_ROOT is set to an incomplete installation: %s. Install or update the complete Tron package at that root.\n' \
    "$name" "$TRON_PLUGIN_ROOT" >&2
  exit 1
fi

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && has_all "$CLAUDE_PLUGIN_ROOT" "$@"; then
  printf '%s\n' "$CLAUDE_PLUGIN_ROOT"
  exit 0
fi

if [[ -n "${CLAUDE_SKILL_DIR:-}" ]]; then
  skill_parent="$(cd "$CLAUDE_SKILL_DIR/../.." 2>/dev/null && pwd || true)"
  if [[ -n "$skill_parent" ]] && has_all "$skill_parent" "$@"; then
    printf '%s\n' "$skill_parent"
    exit 0
  fi
fi

if has_all "$self_root" "$@"; then
  printf '%s\n' "$self_root"
  exit 0
fi

candidate="$({
  find "$claude_cache" "$claude_marketplaces" "$codex_cache" "$codex_marketplaces" \
    "$opencode_config" "$release_store" -maxdepth 8 -type f \
    -path '*/tools/skill/resolve-plugin-root.sh' 2>/dev/null || true
} | while IFS= read -r resolver; do
  root="${resolver%/tools/skill/resolve-plugin-root.sh}"
  has_all "$root" "$@" || continue
  printf '%s\n' "$root"
done | LC_ALL=C sort | tail -1)"

if [[ -n "$candidate" ]]; then
  printf '%s\n' "$candidate"
  exit 0
fi

missing=""
for required in "$first_required" "$@"; do
  [[ -e "$self_root/$required" ]] || missing="${missing}${missing:+, }$required"
done
[[ -f "$self_root/skills/$name/SKILL.md" ]] || missing="${missing}${missing:+, }skills/$name/SKILL.md"
printf 'tron:%s: incomplete Tron installation; missing %s. Install or update the complete Tron package so the skill and its resourceContract paths share one plugin root (or set TRON_PLUGIN_ROOT to that root).\n' \
  "$name" "${missing:-required shared resources}" >&2
exit 1
