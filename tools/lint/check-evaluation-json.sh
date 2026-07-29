#!/usr/bin/env bash
# Parse every evaluation scenario and co-located golden run as JSON.
#
# The evaluate harness validates JSON as it loads, but nothing runs the harness
# in CI, so a malformed scenario stays invisible until someone runs the
# evaluations by hand. This parses them all in one node process instead.
#
#   bash tools/lint/check-evaluation-json.sh [repo-root]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

command -v node >/dev/null 2>&1 || {
  echo "check-evaluation-json: FAILED (node is required)" >&2
  exit 1
}

files="$(find evaluations skills -name '*.json' -not -path '*/node_modules/*' \
  \( -path 'evaluations/*' -o -path 'skills/*/example/*' \) 2>/dev/null | sort || true)"

if [ -z "$files" ]; then
  echo "check-evaluation-json: FAILED (found no evaluation JSON to scan — wrong repo root?)" >&2
  exit 1
fi

if ! printf '%s\n' "$files" | node -e '
const fs = require("fs");
let input = "";
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const files = input.split("\n").filter(Boolean);
  let bad = 0;
  for (const file of files) {
    try {
      JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (err) {
      console.error(`FAIL ${file}: ${err.message}`);
      bad += 1;
    }
  }
  if (bad > 0) process.exit(1);
});
'; then
  echo "check-evaluation-json: FAILED (every evaluation scenario and golden run must be valid JSON)" >&2
  exit 1
fi

echo "check-evaluation-json: OK ($(printf '%s\n' "$files" | wc -l | tr -d '[:space:]') evaluation JSON files parsed)"
