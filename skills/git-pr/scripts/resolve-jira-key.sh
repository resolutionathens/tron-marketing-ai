#!/bin/bash
# Resolve the Jira key from the required <KEY>-<slug> branch convention.

set -euo pipefail

BRANCH="${1:-$(git branch --show-current)}"
JIRA_KEY="$(printf '%s\n' "$BRANCH" | sed -nE 's/^([A-Z]+-[0-9]+)-.+$/\1/p')"

if [ -z "$JIRA_KEY" ]; then
  echo "tron:git-pr: branch '$BRANCH' has no Jira key; expected <KEY>-<slug>. Stop before opening the PR." >&2
  exit 1
fi

printf '%s\n' "$JIRA_KEY"
