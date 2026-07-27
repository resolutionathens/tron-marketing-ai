#!/usr/bin/env bash
# SessionStart hook — notify the user when their installed `tron` plugin is behind the
# published version.
#
# Why this exists: the tron marketplace does not auto-update by default (third-party
# marketplaces are opt-in), so users can silently run stale skills and scripts. This hook
# compares the installed plugin.json "version" against the newest version available from
# that install's own release channel and surfaces a one-line "update available" notice.
#
# Design rules:
#   * Fail-silent. Any missing tool, network error, or parse failure exits 0 — the hook
#     must NEVER block or add noise to session startup.
#   * Network-frugal. The remote version is cached and only re-fetched once per day; the
#     local-vs-remote comparison still runs every startup, so the notice keeps showing
#     until the user updates.
#   * User-visible. A notice is returned as a SessionStart system message and the hook exits 0,
#     so Claude Code displays it without treating the hook as a startup error.
#
# Test/override env vars (used by hooks/test-check-update.sh):
#   CLAUDE_PLUGIN_ROOT       plugin root (defaults to this script's parent dir)
#   TRON_UPDATE_REMOTE_URL   where to fetch the GitHub-channel plugin.json (supports file://)
#   TRON_UPDATE_CACHE        cache file path for the last-seen remote version
#   TRON_RELEASE_STORE       release-store versions directory (defaults to tron-os's store)

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOCAL_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
REMOTE_URL="${TRON_UPDATE_REMOTE_URL:-https://raw.githubusercontent.com/resolutionathens/tron-marketing-ai/master/.claude-plugin/plugin.json}"
CACHE="${TRON_UPDATE_CACHE:-${TMPDIR:-/tmp}/tron-plugin-latest-version}"
RELEASE_STORE="${TRON_RELEASE_STORE:-$HOME/Library/Application Support/tron-os/tron-releases/versions}"
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
case "$LOCAL" in *[!0-9.]* ) exit 0 ;; esac

REMOTE=""
case "$PLUGIN_ROOT" in
  "$RELEASE_STORE"/*)
    # The release store is a locally reconciled channel. Its version directories are the
    # versions this install can actually receive, so never compare it with GitHub master.
    REMOTE="$(find "$RELEASE_STORE" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
      | sed -nE 's#.*/v?([0-9]+\.[0-9]+\.[0-9]+)$#\1#p' \
      | sort -V 2>/dev/null | tail -1)"
    ;;
  "$HOME/.claude/plugins/cache"/*|"$HOME/.claude/plugins/marketplaces"/*|"$HOME/.codex/plugins/cache"/*|"$HOME/.codex/plugins/marketplaces"/*)
    # GitHub marketplace/cache installs consume the repository channel. Cache its manifest
    # as before so the startup path stays bounded and network-frugal.
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
    ;;
  *)
    # A root outside a known channel could be a checkout, a copied install, or another
    # distributor. Do not make a potentially misleading cross-channel comparison.
    exit 0
    ;;
esac
[ -n "$REMOTE" ] || exit 0
case "$REMOTE" in *[!0-9.]* ) exit 0 ;; esac

# Quiet if up to date or somehow ahead of its channel. Use version sort so 0.10.0 > 0.9.0.
[ "$REMOTE" = "$LOCAL" ] && exit 0
newest="$(printf '%s\n%s\n' "$LOCAL" "$REMOTE" | sort -V 2>/dev/null | tail -1)"
[ "$newest" = "$REMOTE" ] || exit 0

printf '{"systemMessage":"⚠️  tron plugin update available: installed %s, published %s. Update with: claude plugin update tron@tron. For a tron-os release-store install, run: tron-os reconcile-tron-release, then rerun the plugin update."}\n' "$LOCAL" "$REMOTE"
exit 0
