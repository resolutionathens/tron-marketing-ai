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
URL_FILE=/tmp/preview-page-url

# ---- resolve dev-server.sh --------------------------------------------------
_DS="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/tools/content/dev-server.sh}"
[[ -z "$_DS" || ! -f "$_DS" ]] && _DS="$(cd "$(dirname "$0")/../../../tools/content" && pwd)/dev-server.sh"

# ---- 1. Resolve URL ---------------------------------------------------------
if [[ "$INPUT" =~ ^https?:// ]]; then
  URL="$INPUT"
  PORT="$(printf '%s' "$URL" | grep -oE ':[0-9]+' | head -1 | tr -d ':' || true)"
  PORT="${PORT:-4001}"
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

  # ---- 2. Ensure dev server is running ------------------------------------
  PORT="$(bash "$_DS" start --route "$ROUTE")"
  URL="http://localhost:${PORT}${ROUTE}"
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
