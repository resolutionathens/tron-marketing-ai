#!/usr/bin/env bash
# Reject mktemp templates whose X run has a suffix. BSD mktemp replaces only
# trailing X characters, so e.g. /tmp/body.XXXXXX.md is a fixed filename.
#
#   bash tools/lint/check-portable-mktemp.sh [repo-root]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

fail=0
checked=0
suffix_pattern="XXXX+[^X[:space:]\"')]"
mktemp_pattern='mktemp[[:space:](]'

while IFS= read -r -d '' file; do
  # The plugin includes binary assets such as fonts and images alongside its
  # bundled scripts. Scan every text file regardless of extension so Python
  # and future script types are covered without attempting to parse binaries.
  [ ! -s "$file" ] || rg -I -q '' "$file" || continue
  checked=$((checked + 1))
  # Match an X run followed immediately by a non-X, non-whitespace character
  # inside a line that invokes mktemp. Quotes end a valid template, so exclude
  # them, plus a command-substitution closing parenthesis, from the suffix
  # character class.
  line_no=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    if [[ "$line" =~ $mktemp_pattern && "$line" =~ $suffix_pattern ]]; then
      printf '%s:%s:%s\n' "$file" "$line_no" "$line" >&2
      fail=1
    fi
  done <"$file"
done < <(find skills tools hooks -type f -not -path '*/node_modules/*' -print0)

if [ "$fail" -ne 0 ]; then
  echo "check-portable-mktemp: FAILED (mktemp templates must end in X characters)" >&2
  exit 1
fi

echo "check-portable-mktemp: OK (checked $checked files)"
