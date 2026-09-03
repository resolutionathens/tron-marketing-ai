#!/usr/bin/env bash
# Resolve an installed tron skill directory without relying on shell globs.
#
# Usage: resolve-skill-dir.sh <skill-name> <required-relative-path> [also-required-path...]
#
# The first path drives the search and must be a FILE. Any extra paths are
# additional existence requirements a candidate must satisfy to be selected, and
# may be files or directories — for a skill whose install is only valid when
# several pieces are present (prose-lint needs vale-ini.template AND styles/).
# Prints the selected skill directory on stdout. Diagnostics go to stderr.
set -euo pipefail

name="${1:-}"
probe="${2:-}"
if [[ -z "$name" || -z "$probe" ]]; then
  echo "usage: resolve-skill-dir.sh <skill-name> <required-relative-path> [also-required-path...]" >&2
  exit 2
fi
shift 2   # "$@" is now the extra required paths (safe when empty, unlike an array under bash 3.2)

self_dir="$(cd "$(dirname "$0")" && pwd)"
RANK="$self_dir/rank-candidate.sh"

claude_cache="$HOME/.claude/plugins/cache"
claude_marketplaces="$HOME/.claude/plugins/marketplaces"
codex_cache="$HOME/.codex/plugins/cache"
codex_marketplaces="$HOME/.codex/plugins/marketplaces"
release_store="$HOME/Library/Application Support/tron-os/tron-releases/versions"

# has_all <dir> [extra-required-path...] — true when $dir holds $probe and every extra.
has_all() {
  local dir="$1"
  shift
  [[ -e "$dir/$probe" ]] || return 1
  local extra
  for extra in "$@"; do
    [[ -e "$dir/$extra" ]] || return 1
  done
  return 0
}

if [[ -n "${CLAUDE_SKILL_DIR:-}" ]] && has_all "$CLAUDE_SKILL_DIR" "$@"; then
  printf '%s\n' "$CLAUDE_SKILL_DIR"
  exit 0
fi
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && has_all "$CLAUDE_PLUGIN_ROOT/skills/$name" "$@"; then
  printf '%s\n' "$CLAUDE_PLUGIN_ROOT/skills/$name"
  exit 0
fi

candidate="$(
  find "$claude_cache" "$claude_marketplaces" "$codex_cache" "$codex_marketplaces" \
    "$release_store" -maxdepth 7 -type f -path "*/skills/$name/$probe" 2>/dev/null \
    | while IFS= read -r file; do
        skill_dir="${file%"/$probe"}"
        has_all "$skill_dir" "$@" || continue
        # Shared with the ambient fallback in git-pr Step 1c (MD-3047): both score
        # candidates with rank-candidate.sh — that script is the one place a
        # future change to how the newest complete package is picked has to land.
        bash "$RANK" "$skill_dir" "$claude_cache" "$claude_marketplaces" "$codex_cache" "$codex_marketplaces"
      done \
    | LC_ALL=C sort -t $'\t' -k1,1 -k2,2n -k3,3 | tail -1 | cut -f3- || true
)"
if [[ -n "$candidate" ]]; then
  printf '%s\n' "$candidate"
  exit 0
fi

printf 'tron:%s: %s not found; searched CLAUDE_SKILL_DIR, CLAUDE_PLUGIN_ROOT, and roots: %s\n' \
  "$name" "$probe" \
  "$claude_cache, $claude_marketplaces, $codex_cache, $codex_marketplaces, $release_store" >&2
exit 1
