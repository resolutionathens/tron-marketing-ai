#!/usr/bin/env bash
# Forbid a skills/*/reference/*.md doc from linking another reference doc.
#
# CLAUDE.md keeps reference docs one level deep from SKILL.md because Claude
# reads a linked doc partially and follows a chain of them less reliably still:
# a doc reachable only through a second reference doc is a doc that may never be
# opened. The two chains this lint was written for had both already rotted —
# jira-ticket-enricher's description-template.md pointed at a sibling filename
# that lives in a different skill (a broken link), and toolkit-playbook.md, the
# other end of the pair, was an orphan nothing linked at all.
#
# Linking *out* of the reference/ layer is not chaining and is deliberately
# allowed: shared prose under tools/<area>/<name>.md and root-level repo docs
# (WORKER_CONTRACT.md, README.md) are single-source leaves that CLAUDE.md tells
# skills to link rather than restate. Forbidding those would put this rule in
# conflict with that one, which is how the absolute form drifted to ten
# violations without anyone noticing.
#
# Links inside fenced code blocks are examples, not links — tools/voice/
# facilitron-voice.md carries the copy-me snippet for its own path — so fences
# are skipped, both CommonMark fence characters and their run lengths honoured.
#
#   bash tools/lint/check-reference-chaining.sh [repo-root]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

fail=0
scanned=0
links=0

# links_in <file> — print "<line> <target>" for every inline markdown link to a
# relative .md path outside fenced code blocks. Absolute URLs, mailto:, and
# bare #anchors are not paths and are skipped.
links_in() {
  awk '
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
      rest = $0
      while (match(rest, /\]\([^)]*\)/) > 0) {
        target = substr(rest, RSTART + 2, RLENGTH - 3)
        rest = substr(rest, RSTART + RLENGTH)
        sub(/#.*$/, "", target)
        if (target == "") continue
        if (target ~ /^[a-zA-Z][a-zA-Z0-9+.-]*:/) continue
        if (target !~ /\.md$/) continue
        print NR " " target
      }
    }
  ' "$1"
}

# normalize <path> — collapse . and .. segments without touching the filesystem,
# so a link to a file that does not exist still resolves to the path it names.
# Prints "ESCAPED" when .. walks above the repo root.
normalize() {
  local path="$1" part out="" oldIFS="$IFS"
  IFS=/
  for part in $path; do
    case "$part" in
      '' | .) ;;
      ..)
        if [ -z "$out" ]; then
          IFS="$oldIFS"
          printf 'ESCAPED\n'
          return
        elif [ "$out" = "${out%/*}" ]; then
          out=""
        else
          out="${out%/*}"
        fi
        ;;
      *) out="${out:+$out/}$part" ;;
    esac
  done
  IFS="$oldIFS"
  printf '%s\n' "$out"
}

while IFS= read -r file; do
  [ -n "$file" ] || continue
  scanned=$((scanned + 1))
  dir="$(dirname "$file")"
  while read -r line target; do
    [ -n "${target:-}" ] || continue
    links=$((links + 1))
    resolved="$(normalize "$dir/$target")"
    case "$resolved" in
      ESCAPED)
        echo "FAIL $file:$line links \`$target\`, which walks above the repo root" >&2
        fail=1
        ;;
      skills/*/reference/*)
        echo "FAIL $file:$line chains to the reference doc \`$resolved\` — link it from SKILL.md instead" >&2
        fail=1
        ;;
      tools/*/*.md) ;;
      *.md)
        # A root-level repo doc has no directory component left once resolved.
        case "$resolved" in
          */*)
            echo "FAIL $file:$line links \`$resolved\`, which is neither shared prose under tools/ nor a root-level repo doc" >&2
            fail=1
            ;;
        esac
        ;;
    esac
  done <<EOF
$(links_in "$file")
EOF
done < <(find skills -path 'skills/*/reference/*.md' -not -path '*/node_modules/*' | sort)

if [ "$fail" -ne 0 ]; then
  echo "check-reference-chaining: FAILED (a reference doc may link shared tools/ prose or a root-level repo doc, never another reference doc)" >&2
  exit 1
fi

if [ "$scanned" -eq 0 ]; then
  echo "check-reference-chaining: FAILED (found no reference docs to scan — wrong repo root?)" >&2
  exit 1
fi

echo "check-reference-chaining: OK ($links markdown links across $scanned reference docs)"
