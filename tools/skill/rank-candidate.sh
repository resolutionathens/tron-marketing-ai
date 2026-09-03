#!/usr/bin/env bash
# Score one candidate installed-package directory for the version+rank selection
# resolve-skill-dir.sh and git-pr's Step 1c ambient fallback both use to pick the
# newest complete Tron package (MD-3047): a zero-padded semver key, then an
# install-root rank (release store < cache < marketplace on a version tie). A
# future change to either rule — a new install root, a different tie-break —
# only has to be made here.
#
# Usage: rank-candidate.sh <candidate-dir> <claude-cache> <claude-marketplaces> <codex-cache> <codex-marketplaces>
# Prints "<version-key>\t<rank>\t<candidate-dir>" on stdout.
set -euo pipefail

candidate="${1:?usage: rank-candidate.sh <candidate-dir> <claude-cache> <claude-marketplaces> <codex-cache> <codex-marketplaces>}"
claude_cache="${2:?usage: rank-candidate.sh <candidate-dir> <claude-cache> <claude-marketplaces> <codex-cache> <codex-marketplaces>}"
claude_marketplaces="${3:?usage: rank-candidate.sh <candidate-dir> <claude-cache> <claude-marketplaces> <codex-cache> <codex-marketplaces>}"
codex_cache="${4:?usage: rank-candidate.sh <candidate-dir> <claude-cache> <claude-marketplaces> <codex-cache> <codex-marketplaces>}"
codex_marketplaces="${5:?usage: rank-candidate.sh <candidate-dir> <claude-cache> <claude-marketplaces> <codex-cache> <codex-marketplaces>}"

version="$(printf '%s\n' "$candidate" | tr '/' '\n' | sed -nE 's/^v?([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' | tail -1)"
key="$(printf '%s' "${version:-0.0.0}" | awk -F. '{printf "%05d.%05d.%05d", $1, $2, $3}')"
rank=1
if [[ "$candidate" == "$claude_cache/"* || "$candidate" == "$codex_cache/"* ]]; then
  rank=2
fi
if [[ "$candidate" == "$claude_marketplaces/"* || "$candidate" == "$codex_marketplaces/"* ]]; then
  rank=3
fi
printf '%s\t%s\t%s\n' "$key" "$rank" "$candidate"
