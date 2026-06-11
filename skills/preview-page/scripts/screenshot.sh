#!/usr/bin/env bash
# preview-page: screenshot the current cmux browser surface with a built-in
# blank-capture guard.
#
# Two distinct failure modes this wrapper handles, because they are NOT the same:
#
#   1. Blank/loading paint -- the screenshot command succeeds but writes a tiny
#      PNG because the page hasn't painted yet (common right after navigate /
#      reload). Fix: reload + wait + retry.
#
#   2. Backgrounded surface -- cmux can only snapshot the *selected* tab of a
#      pane. A surface that was closed or pushed to the background still answers
#      `eval`/`url` (so it looks alive) but `screenshot` errors with
#      "Failed to capture snapshot". Reloading will NEVER fix this. The surface
#      has to be foregrounded (re-run preview.sh, which opens/selects it), or
#      use the headless responsive-shot.mjs path, which doesn't depend on pane
#      visibility at all and is the more reliable choice for self-verification.
#
# Usage:
#   screenshot.sh <out-path> [surface]
#
#   surface defaults to the ref in /tmp/preview-page-surface (written by
#   preview.sh). A real marketing-page capture is normally >500KB; anything
#   under MIN_BYTES is treated as a blank/loading frame.
#
# Examples:
#   screenshot.sh /tmp/home.png
#   screenshot.sh /tmp/home.png surface:23

set -euo pipefail

OUT="${1:-}"
if [[ -z "$OUT" ]]; then
  echo "usage: screenshot.sh <out-path> [surface]" >&2
  exit 2
fi

SURFACE="${2:-}"
if [[ -z "$SURFACE" ]]; then
  SURFACE=$(cat /tmp/preview-page-surface 2>/dev/null || true)
fi
if [[ -z "$SURFACE" ]]; then
  echo "no surface given and /tmp/preview-page-surface is empty; run preview.sh first" >&2
  exit 2
fi

MIN_BYTES=${MIN_BYTES:-400000}
MAX_TRIES=${MAX_TRIES:-4}

filesize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0; }

backgrounded_hint() {
  cat >&2 <<EOF
surface $SURFACE can't be captured -- it's backgrounded or closed (cmux only
snapshots the selected tab). Two ways forward:
  - re-run preview.sh to (re)open and select it in the browser pane, then retry, or
  - for headless self-verification that ignores pane visibility:
      (cd "\$(dirname "\$0")/.." && bun scripts/responsive-shot.mjs <url> desktop $OUT)
EOF
}

for try in $(seq 1 "$MAX_TRIES"); do
  # Wait for the document to finish loading and have a non-empty, non-loading title.
  for _ in $(seq 1 8); do
    READY=$(cmux browser --surface "$SURFACE" eval "document.readyState" 2>/dev/null || echo "")
    TITLE=$(cmux browser --surface "$SURFACE" eval "document.title" 2>/dev/null || echo "")
    if [[ "$READY" == "complete" && -n "$TITLE" && "$TITLE" != "Loading"* ]]; then
      break
    fi
    sleep 1
  done

  rm -f "$OUT"
  SHOT_ERR=$(cmux browser --surface "$SURFACE" screenshot --out "$OUT" 2>&1 >/dev/null || true)
  SIZE=$(filesize "$OUT")

  if [[ "$SIZE" -ge "$MIN_BYTES" ]]; then
    echo "$OUT (${SIZE} bytes, try $try)"
    exit 0
  fi

  # Distinguish "can't snapshot this surface" (unrecoverable here) from a blank paint.
  if [[ "$SHOT_ERR" == *"Failed to capture snapshot"* || "$SHOT_ERR" == *"not_found"* ]]; then
    backgrounded_hint
    exit 1
  fi

  echo "blank/small capture (${SIZE}B < ${MIN_BYTES}B) on try $try; reloading..." >&2
  cmux browser --surface "$SURFACE" reload >/dev/null 2>&1 || true
  sleep 4
done

echo "still blank after ${MAX_TRIES} tries; last size $(filesize "$OUT")B. Check the dev server / surface $SURFACE." >&2
exit 1
