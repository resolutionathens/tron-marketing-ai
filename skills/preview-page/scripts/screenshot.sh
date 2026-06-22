#!/usr/bin/env bash
# preview-page: screenshot a previewed page with a built-in blank-capture guard,
# using the headless `agent-browser` CLI (its own Chromium, independent of the
# user's default browser).
#
# The one failure mode this wrapper handles:
#
#   Blank/loading paint -- the screenshot succeeds but writes a tiny PNG because
#   the page hasn't painted yet (common right after navigate / reload). Fix:
#   reload + wait + retry. agent-browser drives its own headless browser, so the
#   capture never depends on which tab the user happens to be looking at.
#
# Usage:
#   screenshot.sh <out-path> [url]
#
#   url defaults to the last-previewed URL in /tmp/preview-page-url (written by
#   preview.sh). A real marketing-page capture is normally >500KB; anything
#   under MIN_BYTES is treated as a blank/loading frame.
#
# Examples:
#   screenshot.sh /tmp/home.png
#   screenshot.sh /tmp/home.png http://localhost:4001/about-facilitron
#
# For mobile/responsive captures at an arbitrary viewport, prefer the headless
# scripts/responsive-shot.mjs helper instead.

set -euo pipefail

OUT="${1:-}"
if [[ -z "$OUT" ]]; then
  echo "usage: screenshot.sh <out-path> [url]" >&2
  exit 2
fi

URL="${2:-}"
if [[ -z "$URL" ]]; then
  URL=$(cat /tmp/preview-page-url 2>/dev/null || true)
fi
if [[ -z "$URL" ]]; then
  echo "no url given and /tmp/preview-page-url is empty; run preview.sh first" >&2
  exit 2
fi

if ! command -v agent-browser >/dev/null 2>&1; then
  cat >&2 <<EOF
agent-browser not found on PATH. For a headless capture without it, use the
skill's Playwright helper instead:
  (cd "\$(dirname "\$0")/.." && bun scripts/responsive-shot.mjs "$URL" desktop "$OUT" --full)
EOF
  exit 1
fi

MIN_BYTES=${MIN_BYTES:-400000}
MAX_TRIES=${MAX_TRIES:-4}

filesize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0; }

# Navigate once. A failure here (bad URL, crashed/incompatible agent-browser
# backend) is a REAL error, not a blank paint — surface it immediately rather
# than looping into a misleading "still blank" message.
set +e
OPEN_ERR=$(agent-browser open "$URL" 2>&1 >/dev/null); OPEN_RC=$?
set -e
if [[ "$OPEN_RC" -ne 0 ]]; then
  echo "agent-browser could not open $URL (exit $OPEN_RC): ${OPEN_ERR:-no error output}" >&2
  exit 1
fi
agent-browser wait --load networkidle >/dev/null 2>&1 || true

for try in $(seq 1 "$MAX_TRIES"); do
  # Wait for the document to finish loading and have a non-empty, non-loading title.
  for _ in $(seq 1 8); do
    READY=$(agent-browser eval "document.readyState" 2>/dev/null || echo "")
    TITLE=$(agent-browser eval "document.title" 2>/dev/null || echo "")
    if [[ "$READY" == *complete* && -n "$TITLE" && "$TITLE" != Loading* ]]; then
      break
    fi
    sleep 1
  done

  rm -f "$OUT"
  # Distinguish a real capture error (non-zero exit → surface it) from a blank
  # paint (zero exit but a tiny PNG → retry). The old code swallowed both and
  # reported every failure as "blank".
  set +e
  SHOT_ERR=$(agent-browser screenshot "$OUT" 2>&1 >/dev/null); SHOT_RC=$?
  set -e
  if [[ "$SHOT_RC" -ne 0 ]]; then
    echo "agent-browser screenshot failed (exit $SHOT_RC): ${SHOT_ERR:-no error output}" >&2
    exit 1
  fi
  SIZE=$(filesize "$OUT")

  if [[ "$SIZE" -ge "$MIN_BYTES" ]]; then
    echo "$OUT (${SIZE} bytes, try $try)"
    exit 0
  fi

  echo "blank/small capture (${SIZE}B < ${MIN_BYTES}B) on try $try; reloading..." >&2
  agent-browser reload >/dev/null 2>&1 || true
  agent-browser wait --load networkidle >/dev/null 2>&1 || true
  sleep 4
done

echo "still blank after ${MAX_TRIES} tries; last size $(filesize "$OUT")B. Check the dev server / URL $URL." >&2
exit 1
