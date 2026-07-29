#!/usr/bin/env bash
# Require a `## Contents` list at the top of every long progressively-disclosed
# doc — skills/*/reference/*.md and the shared prose under tools/<area>/*.md —
# and require that list to actually enumerate the doc's `##` sections.
#
# Claude reads a linked doc partially. Without a contents list in the opening
# lines, a partial read looks complete while whole sections stay invisible —
# the failure mode that made an MD-2450 sweep miss two of the files it was
# supposed to cover. A heading with no entries, or one whose entries have
# drifted from the sections they name, is the same failure wearing a hat, so
# coverage is checked and not just presence.
#
# The threshold is 100 lines; the list must appear inside the first 20 so it
# survives the truncation it exists to defend against. Headings inside fenced
# code blocks are not sections — the docs that carry markdown templates would
# otherwise have to index their own examples. Both CommonMark fence characters
# count: a tilde fence hiding template headings would otherwise be read as real
# sections and fail a compliant doc, and a false positive in a lint blocks
# unrelated work.
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

# audit <file> — print one diagnostic per problem found, nothing when compliant.
# Collects `##` headings outside fenced code blocks (CommonMark: a fence closes
# only on a run at least as long as the one that opened it) and the list items
# under `## Contents`, then reports sections no item names.
audit() {
  awk -v head_lines="$HEAD_LINES" '
    # Sets fence_char/fence_run to the leading fence run, or fence_char="" when
    # the line does not open or close one. CommonMark allows both ` and ~.
    function read_fence(line) {
      fence_char = ""
      fence_run = 0
      if (match(line, /^[[:space:]]*`{3,}/) == 0 && match(line, /^[[:space:]]*~{3,}/) == 0) return
      run = substr(line, RSTART, RLENGTH)
      sub(/^[[:space:]]*/, "", run)
      fence_char = substr(run, 1, 1)
      fence_run = length(run)
    }
    {
      read_fence($0)
      if (fence_char != "") {
        # A fence closes only on the same character and a run at least as long,
        # so a ``` inside a ~~~ block (or a shorter run) does not reopen prose.
        if (open_fence == 0) {
          open_fence = fence_run
          open_char = fence_char
        } else if (fence_char == open_char && fence_run >= open_fence) {
          open_fence = 0
          open_char = ""
        }
        next
      }
      if (open_fence > 0) next
      if ($0 ~ /^## /) {
        heading = substr($0, 4)
        if (heading == "Contents") {
          seen_contents = 1
          contents_line = NR
          in_contents = 1
          next
        }
        in_contents = 0
        sections[++section_count] = heading
        next
      }
      if (in_contents && $0 ~ /^[[:space:]]*[-*] /) items[++item_count] = $0
    }
    END {
      if (!seen_contents) {
        print "has no \"## Contents\" list — add one listing its ## sections so a partial read still shows the full scope"
        exit
      }
      if (contents_line > head_lines) {
        printf "puts its \"## Contents\" list on line %d, past the first %d lines where a partial read can still see it\n", contents_line, head_lines
      }
      if (item_count == 0) {
        print "has an empty \"## Contents\" list — it must name each ## section, not just carry the heading"
      }
      for (i = 1; i <= section_count; i++) {
        found = 0
        for (j = 1; j <= item_count; j++) if (index(items[j], sections[i])) found = 1
        if (!found) printf "has a \"## Contents\" list that does not name the section \"%s\"\n", sections[i]
      }
    }
  ' "$1"
}

while IFS= read -r file; do
  [ -n "$file" ] || continue
  scanned=$((scanned + 1))
  lines="$(wc -l <"$file" | tr -d '[:space:]')"
  [ "$lines" -gt "$MIN_LINES" ] || continue
  checked=$((checked + 1))
  problems="$(audit "$file")"
  if [ -n "$problems" ]; then
    while IFS= read -r problem; do
      [ -n "$problem" ] || continue
      echo "FAIL $file: $lines lines and $problem" >&2
      fail=1
    done <<EOF
$problems
EOF
  fi
done < <(find skills tools -name '*.md' -not -path '*/node_modules/*' \
  \( -path 'skills/*/reference/*' -o -path 'tools/*' \) | sort)

if [ "$fail" -ne 0 ]; then
  echo "check-reference-contents: FAILED (reference docs over $MIN_LINES lines must open with a ## Contents list naming every ## section)" >&2
  exit 1
fi

if [ "$scanned" -eq 0 ]; then
  echo "check-reference-contents: FAILED (found no reference docs to scan — wrong repo root?)" >&2
  exit 1
fi

echo "check-reference-contents: OK ($checked of $scanned reference docs over $MIN_LINES lines)"
