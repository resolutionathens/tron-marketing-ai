#!/usr/bin/env bash
# SessionStart hook — notify the user when their installed `tron` plugin is behind the
# published version.
#
# Why this exists: the tron marketplace does not auto-update by default (third-party
# marketplaces are opt-in), so users can silently run stale skills and scripts. This hook
# compares the installed plugin.json "version" against master on GitHub and surfaces a
# one-line "update available" notice.
#
# Design rules:
#   * Fail-silent. Any missing tool, network error, or parse failure exits 0 — the hook
#     must NEVER block or add noise to session startup.
#   * Network-frugal. The remote version is cached and only re-fetched once per day; the
#     local-vs-remote comparison still runs every startup, so the notice keeps showing
#     until the user updates.
#   * User-visible. A notice is written to stderr and the hook exits 2 — that is the only
#     SessionStart channel Claude Code shows directly to the user (stdout goes to the
#     model's context, not the terminal).
#
# Test/override env vars (used by hooks/test-check-update.sh):
#   CLAUDE_PLUGIN_ROOT       plugin root (defaults to this script's parent dir)
#   TRON_UPDATE_REMOTE_URL   where to fetch the published plugin.json (supports file://)
#   TRON_UPDATE_CACHE        cache file path for the last-seen remote version

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOCAL_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
REMOTE_URL="${TRON_UPDATE_REMOTE_URL:-https://raw.githubusercontent.com/resolutionathens/tron-marketing-ai/master/.claude-plugin/plugin.json}"
CACHE="${TRON_UPDATE_CACHE:-${TMPDIR:-/tmp}/tron-plugin-latest-version}"
TTL_MIN=1440  # re-hit the network at most once per day

# Extract the .version string from JSON on stdin. Prefer jq; fall back to sed so the hook
# works on machines without jq.
extract_version() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.version // empty' 2>/dev/null
  else
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -1
  fi
}

[ -f "$LOCAL_MANIFEST" ] || exit 0
LOCAL="$(extract_version < "$LOCAL_MANIFEST")"
[ -n "$LOCAL" ] || exit 0   # can't determine local version — stay quiet

# Resolve the remote version: use a fresh cache if present, else fetch (fast, fail-silent),
# falling back to a stale cache if the fetch fails.
REMOTE=""
if [ -f "$CACHE" ] && [ -z "$(find "$CACHE" -mmin +"$TTL_MIN" 2>/dev/null)" ]; then
  REMOTE="$(cat "$CACHE" 2>/dev/null)"
else
  body="$(curl -fsSL --max-time 4 "$REMOTE_URL" 2>/dev/null)" || body=""
  REMOTE="$(printf '%s' "$body" | extract_version)"
  if [ -n "$REMOTE" ]; then
    printf '%s' "$REMOTE" > "$CACHE" 2>/dev/null || true
  elif [ -f "$CACHE" ]; then
    REMOTE="$(cat "$CACHE" 2>/dev/null)"   # network failed — reuse last known
  fi
fi
[ -n "$REMOTE" ] || exit 0

# Quiet if up to date or somehow ahead of master. Use version sort so 0.10.0 > 0.9.0.
[ "$REMOTE" = "$LOCAL" ] && exit 0
newest="$(printf '%s\n%s\n' "$LOCAL" "$REMOTE" | sort -V 2>/dev/null | tail -1)"
[ "$newest" = "$REMOTE" ] || exit 0

printf '⚠️  tron plugin update available — installed %s, published %s.\n' "$LOCAL" "$REMOTE" >&2
printf '   Update with:  /plugin marketplace update tron  →  /plugin install tron@tron --force  →  /reload-plugins\n' >&2
exit 2
