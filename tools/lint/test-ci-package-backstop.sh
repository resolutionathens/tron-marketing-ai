#!/usr/bin/env bash
# Guard the package-validation workflow's role as a scheduled backstop. The
# mandatory local git-pr selector owns pre-PR validation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require() { grep -Fq -- "$1" "$WORKFLOW" || fail "workflow is missing: $1"; }

if grep -Eq '^[[:space:]]{2}pull_request:' "$WORKFLOW"; then
  fail 'package validation must not block pull requests after local parity is complete'
fi

require 'schedule:'
require 'workflow_dispatch:'
require '@openai/codex@latest @anthropic-ai/claude-code@latest'
require 'Local git-pr verification is the primary pre-PR gate.'
require 'issues: write'
require 'Alert maintainers when the backstop fails'
require '[CI] Package-validation backstop is failing'
require 'Close the backstop alert after recovery'

printf 'PASS: package validation is a scheduled/manual backstop with durable failure alerting.\n'
