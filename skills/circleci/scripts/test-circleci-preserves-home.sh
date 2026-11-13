#!/usr/bin/env bash
# Regression (MD-3398): test-circleci.sh once restored HOME and then ran
# `rm -f "$HOME/.env"`, deleting the real ~/.env (the user's tool secrets) on every
# Layer-1 run, and left a dangling .env symlink in the shared TMPDIR. Run it under a
# sentinel HOME and TMPDIR and assert both survive untouched.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/circleci-home-guard.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/home" "$SANDBOX/tmp"
printf 'SENTINEL=keep-me\n' > "$SANDBOX/home/.env"

HOME="$SANDBOX/home" TMPDIR="$SANDBOX/tmp" bash "$HERE/test-circleci.sh" >/dev/null 2>&1 \
  || { echo "FAIL: test-circleci.sh failed under a sentinel HOME" >&2; exit 1; }

[ "$(cat "$SANDBOX/home/.env" 2>/dev/null)" = "SENTINEL=keep-me" ] \
  || { echo "FAIL: test-circleci.sh deleted or changed \$HOME/.env" >&2; exit 1; }
leftover="$(find "$SANDBOX/tmp" -mindepth 1 -maxdepth 1 2>/dev/null)"
[ -z "$leftover" ] || { echo "FAIL: test-circleci.sh left files in TMPDIR: $leftover" >&2; exit 1; }
echo "PASS: test-circleci.sh leaves \$HOME/.env and TMPDIR untouched"
