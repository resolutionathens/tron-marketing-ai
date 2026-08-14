#!/usr/bin/env bash
# Regression: /prose-lint must restore shared resources even when .vale.ini exists.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RUNNER="$ROOT/agents/vale-prose-runner.md"

fail() { echo "not ok: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

facilitron_link_line="$(awk '/ln -snf <STYLES>\/Facilitron/{ print NR; exit }' "$RUNNER")"
vocabulary_link_line="$(awk '/ln -snf <STYLES>\/config\/vocabularies/{ print NR; exit }' "$RUNNER")"
config_guard_line="$(awk '/if \[ ! -f \.vale\.ini \]; then/{ print NR; exit }' "$RUNNER")"

[ -n "$facilitron_link_line" ] || fail "runner restores the Facilitron style link"
[ -n "$vocabulary_link_line" ] || fail "runner restores the vocabulary link"
[ -n "$config_guard_line" ] || fail "runner guards only the portable config copy"
[ "$facilitron_link_line" -lt "$config_guard_line" ] || fail "style link precedes config-exists guard"
[ "$vocabulary_link_line" -lt "$config_guard_line" ] || fail "vocabulary link precedes config-exists guard"

pass "shared style and vocabulary links are restored before the config-exists guard"
