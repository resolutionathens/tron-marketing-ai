#!/usr/bin/env bash
# preview-page: open a Nuxt route in the cmux browser pane.
#
# Resolves <route-or-file> to http://localhost:4001/<route>, starts
# `bun dev` if port 4001 is free, waits for the "Local:" log line,
# then opens a new browser surface in the existing browser pane.
#
# Usage:
#   preview.sh <route|file|url>
#
# Examples:
#   preview.sh /resources/toolkit/foo
#   preview.sh pages/resources/toolkit/foo.vue
#   preview.sh http://localhost:4001/resources/toolkit/foo

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: preview.sh <route|file|url>" >&2
  exit 2
fi

INPUT="$1"
PORT=4001
LOG=/tmp/preview-page-dev.log
# Persist the last-opened surface so subsequent previews can reuse the tab
# instead of stacking new ones. Read on next run, written at end.
SURFACE_FILE=/tmp/preview-page-surface

# ---- 1. Resolve URL ---------------------------------------------------------
if [[ "$INPUT" =~ ^https?:// ]]; then
  URL="$INPUT"
else
  ROUTE="$INPUT"
  # Strip pages/ prefix and .vue suffix if a file path was given.
  ROUTE="${ROUTE#pages/}"
  ROUTE="${ROUTE%.vue}"
  # Collapse /index to the parent directory.
  ROUTE="${ROUTE%/index}"
  [[ "$ROUTE" == "index" ]] && ROUTE=""
  # Ensure leading slash.
  [[ "$ROUTE" != /* ]] && ROUTE="/$ROUTE"
  URL="http://localhost:${PORT}${ROUTE}"
fi

# ---- 2. Start dev server if not already up ----------------------------------
if ! lsof -ti:"$PORT" >/dev/null 2>&1; then
  echo "starting bun dev on :$PORT..." >&2
  # Run from the repo root (two levels up from this script's directory).
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
  (
    cd "$REPO_ROOT"
    # shellcheck disable=SC1091
    [[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh" && nvm use >/dev/null 2>&1 || true
    nohup bun dev >"$LOG" 2>&1 &
    disown
  )

  # Wait for "Local:" line, or bail if errors show up.
  for _ in $(seq 1 60); do
    if grep -q "Local:" "$LOG" 2>/dev/null; then
      break
    fi
    if grep -Eq "^(Error|error|Failed)" "$LOG" 2>/dev/null; then
      echo "dev server failed to start; see $LOG" >&2
      tail -20 "$LOG" >&2
      exit 1
    fi
    sleep 1
  done

  if ! grep -q "Local:" "$LOG" 2>/dev/null; then
    echo "dev server didn't print 'Local:' within 60s; see $LOG" >&2
    exit 1
  fi
fi

# ---- 3a. Try to reuse the previous surface ----------------------------------
# If we previewed something last time and that surface still exists, navigate
# it instead of opening a new tab. This keeps the browser pane tidy across a
# session of edit → preview → edit → preview.
#
# A backgrounded/closed surface still answers `url`/`eval`, so that alone is NOT
# a reliable liveness check -- the surface must still be listed (selected) in a
# pane to be navigable AND screenshot-able. Confirm it shows up in a pane's
# surface list before reusing, otherwise we'd hand back a dead ref that fails to
# capture later.
surface_in_a_pane() {
  local want="$1" pane
  for pane in $(cmux list-panes 2>/dev/null | grep -oE 'pane:[0-9]+'); do
    if cmux list-pane-surfaces --pane "$pane" 2>/dev/null | grep -qE "(^|[^0-9])${want}([^0-9]|$)"; then
      return 0
    fi
  done
  return 1
}

if [[ -f "$SURFACE_FILE" ]]; then
  PREV_SURFACE=$(cat "$SURFACE_FILE" 2>/dev/null || true)
  if [[ -n "${PREV_SURFACE:-}" ]] && surface_in_a_pane "$PREV_SURFACE" \
       && cmux browser --surface "$PREV_SURFACE" url >/dev/null 2>&1; then
    cmux browser --surface "$PREV_SURFACE" goto "$URL" >/dev/null
    # Wait for load so callers can immediately query the page.
    cmux browser --surface "$PREV_SURFACE" wait --load-state complete --timeout-ms 20000 >/dev/null 2>&1 || true
    echo "$PREV_SURFACE"
    echo "$URL"
    exit 0
  fi
fi

# ---- 3b. Find the browser pane ----------------------------------------------
# Heuristic: a browser surface title contains a " - " separator and ends with
# a product/host name (JIRA, GitHub, Confluence, localhost, a .com, etc.).
# Shell and agent surfaces don't match that shape.
BROWSER_PANE=""
PANES=$(cmux list-panes | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^\*?pane:[0-9]+$/) print $i }' | sed 's/^\*//')

while IFS= read -r pane; do
  [[ -z "$pane" ]] && continue
  if cmux list-pane-surfaces --pane "$pane" 2>/dev/null \
     | grep -Eq ' - (JIRA|GitHub|Confluence|YouTube|Google|localhost|[A-Za-z0-9-]+\.(com|io|dev|net|org|app))( |$|\[)'; then
    BROWSER_PANE="$pane"
    break
  fi
done <<< "$PANES"

# ---- 4. Open the URL --------------------------------------------------------
# Capture the surface ref so downstream `cmux browser --surface ...` calls
# (errors list, get text, screenshot, etc.) can target the right tab.
if [[ -n "$BROWSER_PANE" ]]; then
  OPEN_OUT=$(cmux new-surface --type browser --pane "$BROWSER_PANE" --url "$URL" --focus false)
else
  echo "no browser pane found; splitting a new one" >&2
  OPEN_OUT=$(cmux new-pane --type browser --direction right --url "$URL" --focus false)
fi

# cmux new-surface/new-pane prints e.g. "OK surface:20 pane:13 workspace:5".
SURFACE=$(printf '%s\n' "$OPEN_OUT" | grep -oE 'surface:[0-9]+' | head -1)
if [[ -n "$SURFACE" ]]; then
  printf '%s\n' "$SURFACE" > "$SURFACE_FILE"
  # Wait for load so callers can immediately query the page.
  cmux browser --surface "$SURFACE" wait --load-state complete --timeout-ms 20000 >/dev/null 2>&1 || true
  echo "$SURFACE"
fi
echo "$URL"
