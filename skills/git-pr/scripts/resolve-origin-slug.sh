#!/bin/bash
# resolve-origin-slug: extract owner/repo from the git `origin` remote (MD-2661).
#
# Deliberately POSIX case/parameter-expansion, not `[[ =~ ]]`/BASH_REMATCH — zsh
# populates regex capture groups differently than bash, so the old bash-only
# construct silently produced an empty slug when git-pr's Step 6 ran directly in
# a zsh default shell. This script behaves identically under bash and zsh (see
# test-resolve-origin-slug.sh, which runs it under both).
#
# Usage:
#   bash resolve-origin-slug.sh [origin-url]
#     origin-url  Optional. Defaults to `git remote get-url origin`. Passing it
#                 explicitly is what makes this script testable without a git
#                 fixture.
#
# Prints the resolved "owner/repo" slug on stdout and exits 0 on success.
# On failure, prints an actionable error to stderr and exits 1.

set -eu

ORIGIN_URL="${1:-}"
if [ -z "$ORIGIN_URL" ]; then
  ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
fi
[ -n "$ORIGIN_URL" ] || { echo "error: no origin remote configured" >&2; exit 1; }

ORIGIN_URL="${ORIGIN_URL%.git}"

case "$ORIGIN_URL" in
  *github.com[:/]*)
    SLUG="${ORIGIN_URL#*github.com?}"
    ;;
  *)
    echo "error: origin remote is not a github.com URL: $ORIGIN_URL" >&2
    exit 1
    ;;
esac

case "$SLUG" in
  */*) : ;;
  *)
    echo "error: could not extract owner/repo from origin URL: $ORIGIN_URL" >&2
    exit 1
    ;;
esac

case "$SLUG" in
  */*/*)
    echo "error: could not extract owner/repo from origin URL: $ORIGIN_URL" >&2
    exit 1
    ;;
esac

echo "$SLUG"
