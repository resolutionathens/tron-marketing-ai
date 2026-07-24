#!/usr/bin/env bash
# Resolve an installed tron skill directory without relying on shell globs.
#
# Usage: resolve-skill-dir.sh <skill-name> <required-relative-path>
# Prints the selected skill directory on stdout. Diagnostics go to stderr.
set -euo pipefail

name="${1:-}"
probe="${2:-}"
if [[ -z "$name" || -z "$probe" ]]; then
  echo "usage: resolve-skill-dir.sh <skill-name> <required-relative-path>" >&2
  exit 2
fi

claude_cache="$HOME/.claude/plugins/cache"
claude_marketplaces="$HOME/.claude/plugins/marketplaces"
codex_cache="$HOME/.codex/plugins/cache"
codex_marketplaces="$HOME/.codex/plugins/marketplaces"
release_store="$HOME/Library/Application Support/tron-os/tron-releases/versions"

if [[ -n "${CLAUDE_SKILL_DIR:-}" && -e "$CLAUDE_SKILL_DIR/$probe" ]]; then
  printf '%s\n' "$CLAUDE_SKILL_DIR"
  exit 0
fi
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -e "$CLAUDE_PLUGIN_ROOT/skills/$name/$probe" ]]; then
  printf '%s\n' "$CLAUDE_PLUGIN_ROOT/skills/$name"
  exit 0
fi

candidate="$(
  find "$claude_cache" "$claude_marketplaces" "$codex_cache" "$codex_marketplaces" \
    "$release_store" -maxdepth 7 -type f -path "*/skills/$name/$probe" 2>/dev/null \
    | sed "s#/$probe\$##" | sort -V | tail -1 || true
)"
if [[ -n "$candidate" ]]; then
  printf '%s\n' "$candidate"
  exit 0
fi

printf 'tron:%s: %s not found; searched CLAUDE_SKILL_DIR, CLAUDE_PLUGIN_ROOT, and roots: %s\n' \
  "$name" "$probe" \
  "$claude_cache, $claude_marketplaces, $codex_cache, $codex_marketplaces, $release_store" >&2
exit 1
