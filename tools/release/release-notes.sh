#!/usr/bin/env bash
# Generate a release record from the commits since the previous tag.
#
# Hand-writing this list is how MD-2912 became unpublishable: the notes were authored
# inside the PR and named its BRANCH commits, which stopped existing the moment the PR
# was squashed. The validator matches each subject literally, so the record described
# commits that were gone while missing the squash subject that had replaced them. A
# subject is only final after the squash, so derive it, never type it.
#
#   bash tools/release/release-notes.sh <version> [ref] > releases/v<version>.md
set -euo pipefail

ROOT="${TRON_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
VERSION="${1:-}"
# Default to HEAD, not origin/master: the record must describe the range that will
# exist AFTER this branch squash-merges, and a stale origin/master describes a
# different one.
REF="${2:-HEAD}"
[ -n "$VERSION" ] || { echo "usage: release-notes.sh <version> [ref]" >&2; exit 1; }

# The validator walks PREVIOUS..HEAD at publish time, after the squash. If master has
# moved on since this branch forked, the record generated now will be missing whatever
# landed in between — the same stranding this tool exists to prevent. Say so.
if git -C "$ROOT" rev-parse --verify -q origin/master >/dev/null 2>&1; then
  if ! git -C "$ROOT" merge-base --is-ancestor origin/master "$REF" 2>/dev/null; then
    echo "WARNING: origin/master has commits this record will not name. Rebase on origin/master and regenerate before merging, or publication will reject it." >&2
  fi
fi

PREVIOUS="$(git -C "$ROOT" describe --tags --abbrev=0 "$REF")"
printf '# Tron v%s\n\nPrevious release: %s\n\n## Changes\n\n' "$VERSION" "$PREVIOUS"
while IFS= read -r commit; do
  [ -n "$commit" ] || continue
  parent_count="$(git -C "$ROOT" rev-list --parents -n 1 "$commit" | awk '{print NF - 1}')"
  [ "$parent_count" -le 1 ] || continue
  files="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r "$commit")"
  # A commit that only moves versions or records is release bookkeeping, not a change.
  printf '%s\n' "$files" | grep -qvE '^(\.claude-plugin/plugin\.json|\.codex-plugin/plugin\.json|releases/v[0-9.]+\.md)$' || continue
  printf -- '- %s\n' "$(git -C "$ROOT" log -1 --format=%s "$commit")"
done < <(git -C "$ROOT" rev-list --reverse "$PREVIOUS..$REF")
