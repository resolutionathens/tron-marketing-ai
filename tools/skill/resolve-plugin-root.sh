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

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  if has_all "$CLAUDE_PLUGIN_ROOT" "$@"; then
    printf '%s\n' "$CLAUDE_PLUGIN_ROOT"
    exit 0
  fi
  printf 'tron:%s: CLAUDE_PLUGIN_ROOT is set to an incomplete installation: %s. Install or update the complete Tron package at that root.\n' \
    "$name" "$CLAUDE_PLUGIN_ROOT" >&2
  exit 1
fi

if [[ -n "${CLAUDE_SKILL_DIR:-}" ]]; then
  skill_parent="$(cd "$CLAUDE_SKILL_DIR/../.." 2>/dev/null && pwd || true)"
  if [[ -n "$skill_parent" ]] && has_all "$skill_parent" "$@"; then
    printf '%s\n' "$skill_parent"
    exit 0
  fi
  printf 'tron:%s: CLAUDE_SKILL_DIR does not belong to a complete installation: %s. Install or update that complete Tron package.\n' \
    "$name" "$CLAUDE_SKILL_DIR" >&2
  exit 1
fi

if has_all "$self_root" "$@"; then
  printf '%s\n' "$self_root"
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
