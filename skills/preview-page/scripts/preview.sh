#!/usr/bin/env bash
# preview-page: open a Nuxt route in the user's default browser.
#
# Resolves <route-or-file> to http://localhost:4001/<route>, starts
# `bun dev` if port 4001 is free, waits until the port accepts connections,
# then opens the URL in the default browser (`open` on macOS, `xdg-open` on
# Linux). The URL is also saved to /tmp/preview-page-url so screenshot.sh and
# agent-browser self-checks can reuse it without re-deriving the route.
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
# Persist the last-previewed URL so screenshot.sh / agent-browser self-checks
# can reuse it without re-deriving the route.
URL_FILE=/tmp/preview-page-url

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
  # Find the repo root from the CALLER's cwd, not the script's location: the
  # skill now ships inside the tron plugin cache, so script-relative path math
  # would point at the plugin dir (which has no `dev` script). Walk up from cwd
  # to the marketing-pages app (identified by its package.json name).
  REPO_ROOT="${PWD}"
  while [[ "$REPO_ROOT" != "/" ]] && ! grep -q '"facilitron-marketing-pages"' "$REPO_ROOT/package.json" 2>/dev/null; do
    REPO_ROOT="$(dirname "$REPO_ROOT")"
  done
  if [[ "$REPO_ROOT" == "/" ]]; then
    echo "preview.sh: not inside the marketing-pages repo (cwd=$PWD)" >&2
    exit 1
  fi
  (
    cd "$REPO_ROOT"
    # shellcheck disable=SC1091
    [[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh" && nvm use >/dev/null 2>&1 || true
    nohup bun dev >"$LOG" 2>&1 &
    disown
  )

  # Wait until the port actually accepts connections, or bail if errors show up.
  # A network probe is robust to changes in the Nuxt/Bun ready banner; curl exits
  # non-zero (connection refused) until the server is listening, then succeeds on
  # any HTTP response (-f is intentionally omitted so a 404 still counts as "up").
  server_up() { curl -s -o /dev/null --max-time 2 "http://localhost:${PORT}/"; }
  for _ in $(seq 1 60); do
    if server_up; then
      break
    fi
    if grep -Eq "^(Error|error|Failed)" "$LOG" 2>/dev/null; then
      echo "dev server failed to start; see $LOG" >&2
      tail -20 "$LOG" >&2
      exit 1
    fi
    sleep 1
  done

  if ! server_up; then
    echo "dev server didn't start listening on :$PORT within 60s; see $LOG" >&2
    exit 1
  fi
fi

# ---- 3. Open the URL in the user's default browser --------------------------
# Save the URL first so screenshot.sh / agent-browser self-checks can reuse it.
printf '%s\n' "$URL" > "$URL_FILE"

if command -v open >/dev/null 2>&1; then
  open "$URL"                       # macOS
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" >/dev/null 2>&1 & # Linux
else
  echo "no 'open'/'xdg-open' on PATH — open this URL manually:" >&2
fi

echo "$URL"
