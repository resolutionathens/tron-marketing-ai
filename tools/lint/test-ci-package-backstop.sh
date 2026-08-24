#!/usr/bin/env bash
# Guard the package-validation workflow's role as a scheduled backstop while
# retaining a lightweight pull-request check that lets Scout observe the gate.
# The mandatory local git-pr selector still owns pre-PR validation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require() { grep -Fq -- "$1" "$WORKFLOW" || fail "workflow is missing: $1"; }

require 'pull_request:'
require 'schedule:'
require 'workflow_dispatch:'
require 'pr-gate:'
require "if: github.event_name == 'pull_request'"
require 'Local verification completed before PR creation'
require "if: github.event_name != 'pull_request'"
require '@openai/codex@latest @anthropic-ai/claude-code@latest'
require 'Local git-pr verification is the primary pre-PR gate.'
require 'issues: write'
require 'Alert maintainers when the backstop fails'
require '[CI] Package-validation backstop is failing'
require 'Close the backstop alert after recovery'

printf 'PASS: Scout receives a lightweight PR gate while package validation remains a scheduled/manual backstop.\n'
