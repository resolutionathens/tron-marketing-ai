#!/bin/bash
# Resolve the Jira key from the required <KEY>-<slug> branch convention.
#
# A plugin release branch is the one legitimate exception (MD-3017): a release is
# a version bump plus a generated record, not tracked work, so it has no ticket to
# name. Its trail is the file in releases/ and the immutable tag, not a Jira key.
# Such a branch resolves to an EMPTY key and exit 0, which lets git-pr's
# `JIRA_KEY="$(...)" || exit $?` continue with no key. Every other keyless branch
# still stops, because an ordinary change without a ticket loses its trail.

set -euo pipefail

BRANCH="${1:-$(git branch --show-current)}"
JIRA_KEY="$(printf '%s\n' "$BRANCH" | sed -nE 's/^([A-Z]+-[0-9]+)-.+$/\1/p')"

if [ -z "$JIRA_KEY" ]; then
  # release-v<version> — the plugin-release skill's branch convention.
  case "$BRANCH" in
    release-v[0-9]*)
      printf ''
      exit 0
      ;;
  esac
  echo "tron:git-pr: branch '$BRANCH' has no Jira key; expected <KEY>-<slug>. Stop before opening the PR." >&2
  exit 1
fi

printf '%s\n' "$JIRA_KEY"
