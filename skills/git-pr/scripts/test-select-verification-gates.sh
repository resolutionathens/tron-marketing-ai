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
FIXTURE_BIN="$ROOT/bin"
TRACE="$ROOT/trace"
mkdir -p "$FIXTURE_BIN"

cat > "$FIXTURE_BIN/mise" <<'MISEEOF'
#!/bin/bash
printf 'mise %s\n' "$*" >> "$TRACE"
[ "${1:-}" = "exec" ] || exit 1
shift
[ "${1:-}" = "--" ] && shift
exec "$@"
MISEEOF
cat > "$FIXTURE_BIN/bun" <<'BUNEOF'
#!/bin/bash
printf 'bun %s\n' "$*" >> "$TRACE"
BUNEOF
chmod +x "$FIXTURE_BIN/mise" "$FIXTURE_BIN/bun"

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

PINNED_REPO="$ROOT/pinned"
mkdir -p "$PINNED_REPO"
: > "$PINNED_REPO/bun.lock"
: > "$PINNED_REPO/.mise.toml"
cat > "$PINNED_REPO/package.json" <<'JSON'
{"scripts":{"test":"bun test"}}
JSON
: > "$TRACE"
pinned_output="$(PATH="$FIXTURE_BIN:$PATH" TRACE="$TRACE" bash "$SCRIPT" --repo-dir "$PINNED_REPO")"
assert_contains "$pinned_output" "selected test gate: mise exec -- bun run test"
assert_contains "$(<"$TRACE")" "mise exec -- bun run test"
assert_contains "$(<"$TRACE")" "bun run test"

UNPINNED_REPO="$ROOT/unpinned"
mkdir -p "$UNPINNED_REPO"
: > "$UNPINNED_REPO/bun.lock"
cat > "$UNPINNED_REPO/package.json" <<'JSON'
{"scripts":{"test":"bun test"}}
JSON
: > "$TRACE"
unpinned_output="$(PATH="$FIXTURE_BIN:$PATH" TRACE="$TRACE" bash "$SCRIPT" --repo-dir "$UNPINNED_REPO")"
assert_contains "$unpinned_output" "selected test gate: bun run test"
case "$(<"$TRACE")" in
  *"mise "*) echo "FAIL: unpinned gates must not invoke mise" >&2; exit 1 ;;
  *"bun run test"*) PASS=$((PASS + 1)) ;;
  *) echo "FAIL: unpinned gate did not run through its original runner" >&2; exit 1 ;;
esac

NO_MISE_REPO="$ROOT/no-mise"
NO_MISE_BIN="$ROOT/no-mise-bin"
mkdir -p "$NO_MISE_REPO"
mkdir -p "$NO_MISE_BIN"
: > "$NO_MISE_REPO/bun.lock"
: > "$NO_MISE_REPO/.tool-versions"
cat > "$NO_MISE_REPO/package.json" <<'JSON'
{"scripts":{"test":"bun test"}}
JSON
ln -s "$(command -v node)" "$NO_MISE_BIN/node"
no_mise_output="$(PATH="$NO_MISE_BIN:/usr/bin:/bin" bash "$SCRIPT" --repo-dir "$NO_MISE_REPO" --dry-run)"
assert_contains "$no_mise_output" "selected test gate: bun run test"

SMOKE_REPO="$ROOT/smoke"
mkdir -p "$SMOKE_REPO"
: > "$SMOKE_REPO/package-lock.json"
cat > "$SMOKE_REPO/package.json" <<'JSON'
{"scripts":{"smoke":"node scripts/smoke.js"}}
JSON
smoke_output="$(bash "$SCRIPT" --repo-dir "$SMOKE_REPO" --dry-run)"
assert_contains "$smoke_output" "selected smoke gate: npm run smoke"

echo "✅ git-pr verification selector PASSED ($PASS checks)"
