#!/usr/bin/env bash
# Require a `## Contents` list at the top of every long progressively-disclosed
# doc: skills/*/reference/*.md and the shared prose under tools/<area>/*.md.
#
# Claude reads a linked doc partially. Without a contents list in the opening
# lines, a partial read looks complete while whole sections stay invisible —
# the failure mode that made an MD-2450 sweep miss two of the files it was
# supposed to cover. The threshold is 100 lines; the list must appear inside the
# first 20 so it survives the truncation it exists to defend against.
#
#   bash tools/lint/check-reference-contents.sh [repo-root]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

MIN_LINES=100
HEAD_LINES=20

fail=0
checked=0
scanned=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  scanned=$((scanned + 1))
  lines="$(wc -l <"$file" | tr -d '[:space:]')"
  [ "$lines" -gt "$MIN_LINES" ] || continue
  checked=$((checked + 1))
  if ! head -"$HEAD_LINES" "$file" | grep -q '^## Contents'; then
    echo "FAIL $file: $lines lines and no \"## Contents\" list in the first $HEAD_LINES — add one listing its ## sections so a partial read still shows the full scope" >&2
    fail=1
  fi
done < <(find skills tools -name '*.md' -not -path '*/node_modules/*' \
  \( -path 'skills/*/reference/*' -o -path 'tools/*' \) | sort)

if [ "$fail" -ne 0 ]; then
  echo "check-reference-contents: FAILED (reference docs over $MIN_LINES lines must open with a ## Contents list)" >&2
  exit 1
fi

if [ "$scanned" -eq 0 ]; then
  echo "check-reference-contents: FAILED (found no reference docs to scan — wrong repo root?)" >&2
  exit 1
fi

echo "check-reference-contents: OK ($checked of $scanned reference docs over $MIN_LINES lines)"
