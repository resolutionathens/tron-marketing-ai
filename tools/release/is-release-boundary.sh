#!/usr/bin/env bash
# Classify HEAD for the publish workflow. Three outcomes, because collapsing them is
# how a broken release goes silent (MD-2913):
#
#   0  a dedicated release boundary — publish.
#   1  an ordinary commit that touches no version or record — nothing to do, no-op.
#   2  it LOOKS like a release and is malformed — fail loudly. A bump merged without
#      its record, a record whose filename disagrees with the manifest, or a manifest
#      that will not parse must never read as "nothing to publish".
set -euo pipefail

ROOT="${TRON_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLAUDE=.claude-plugin/plugin.json
CODEX=.codex-plugin/plugin.json

# A merge commit's default diff-tree output is EMPTY, which would silently read as
# "ordinary" and make the documented workflow_dispatch retry publish nothing at all.
# --first-parent -m diffs against the branch being merged into, which is what a
# release landing via a merge commit actually changed.
if [ "$(git -C "$ROOT" rev-list --parents -n 1 HEAD | awk '{print NF - 1}')" -gt 1 ]; then
  HEAD_FILES="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r -m --first-parent HEAD | sort -u)"
else
  HEAD_FILES="$(git -C "$ROOT" diff-tree --no-commit-id --name-only -r HEAD | sort -u)"
fi

# The MANIFESTS are what declare a version, so they alone decide whether this commit
# was TRYING to release. A record-only change is not an attempt: an ordinary PR may
# legitimately delete a record for a version that was never tagged, and that must not
# raise a malformed-release alarm.
if ! printf '%s\n' "$HEAD_FILES" | grep -qxF "$CLAUDE" && ! printf '%s\n' "$HEAD_FILES" | grep -qxF "$CODEX"; then
  echo "not a release boundary: HEAD changes no plugin manifest, nothing to publish"
  exit 1
fi

VERSION="$(node -p "require('$ROOT/$CLAUDE').version" 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
  echo "MALFORMED RELEASE: $CLAUDE has no readable version" >&2
  exit 2
fi
EXPECTED_FILES="$(printf '%s\n%s\nreleases/v%s.md\n' "$CLAUDE" "$CODEX" "$VERSION" | sort)"
if [ "$HEAD_FILES" = "$EXPECTED_FILES" ]; then
  echo "release boundary: v$VERSION"
  exit 0
fi

LATEST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 HEAD 2>/dev/null || true)"
if [ -n "$LATEST_TAG" ] && [ "v$VERSION" = "$LATEST_TAG" ]; then
  echo "not a release boundary: manifests already point at published $LATEST_TAG, nothing to publish"
  exit 1
fi

echo "MALFORMED RELEASE: HEAD moves the manifests to $VERSION but is not a dedicated boundary commit." >&2
echo "expected exactly:" >&2
while IFS= read -r f; do [ -n "$f" ] || continue; printf '  %s\n' "$f" >&2; done <<EOF
$EXPECTED_FILES
EOF
echo "got:" >&2
while IFS= read -r f; do [ -n "$f" ] || continue; printf '  %s\n' "$f" >&2; done <<EOF
$HEAD_FILES
EOF
exit 2
