#!/bin/bash
# Hermetic coverage for repository-aware git-pr verification selection.
#
# Run:
#   bash skills/git-pr/scripts/test-select-verification-gates.sh

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/select-verification-gates.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-pr-verification.XXXXXX")"
trap 'command -v trash >/dev/null 2>&1 && trash "$ROOT"' EXIT

PASS=0

assert_contains() {
  haystack="$1"
  needle="$2"
  case "$haystack" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *) echo "FAIL: expected output to contain: $needle" >&2; echo "$haystack" >&2; exit 1 ;;
  esac
}

PLUGIN_REPO="$ROOT/plugin"
mkdir -p "$PLUGIN_REPO/tools/lint"
: > "$PLUGIN_REPO/tools/lint/run-layer1-tests.sh"
plugin_output="$(bash "$SCRIPT" --repo-dir "$PLUGIN_REPO" --dry-run)"
assert_contains "$plugin_output" "source=plugin-layer1"
assert_contains "$plugin_output" "selected Layer-1 gate: bash tools/lint/run-layer1-tests.sh"

CONSUMER_REPO="$ROOT/consumer"
mkdir -p "$CONSUMER_REPO"
: > "$CONSUMER_REPO/bun.lock"
cat > "$CONSUMER_REPO/package.json" <<'JSON'
{
  "scripts": {
    "test": "bun test",
    "typecheck": "tsc --noEmit",
    "smoke:tmux": "bun run scripts/tmux-smoke.ts"
  }
}
JSON
consumer_output="$(bash "$SCRIPT" --repo-dir "$CONSUMER_REPO" --dry-run)"
assert_contains "$consumer_output" "source=repository-package-scripts"
assert_contains "$consumer_output" "selected test gate: bun run test"
assert_contains "$consumer_output" "selected typecheck gate: bun run typecheck"
case "$consumer_output" in
  *"smoke:tmux"*) echo "FAIL: scoped smoke scripts must not be selected implicitly" >&2; exit 1 ;;
  *) PASS=$((PASS + 1)) ;;
esac
case "$consumer_output" in
  *"run-layer1-tests.sh"*) echo "FAIL: consumer fallback referenced plugin Layer 1" >&2; exit 1 ;;
  *) PASS=$((PASS + 1)) ;;
esac

SMOKE_REPO="$ROOT/smoke"
mkdir -p "$SMOKE_REPO"
: > "$SMOKE_REPO/package-lock.json"
cat > "$SMOKE_REPO/package.json" <<'JSON'
{"scripts":{"smoke":"node scripts/smoke.js"}}
JSON
smoke_output="$(bash "$SCRIPT" --repo-dir "$SMOKE_REPO" --dry-run)"
assert_contains "$smoke_output" "selected smoke gate: npm run smoke"

echo "✅ git-pr verification selector PASSED ($PASS checks)"
