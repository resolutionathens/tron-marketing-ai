#!/bin/bash
# Hermetic regression coverage for git-pr Jira-key resolution.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/resolve-jira-key.sh"
SKILL="$HERE/../SKILL.md"

actual="$(bash "$SCRIPT" MD-9999-example-change)"
[ "$actual" = "MD-9999" ] || {
  echo "FAIL: expected exact Jira key MD-9999, got: $actual" >&2
  exit 1
}

ERROR_FILE="$(mktemp "${TMPDIR:-/tmp}/git-pr-jira-key.XXXXXX")"
trap 'rm -f "$ERROR_FILE"' EXIT
if bash "$SCRIPT" tron-os/example-change 2>"$ERROR_FILE"; then
  echo "FAIL: expected a keyless branch to stop" >&2
  exit 1
fi

actual="$(cat "$ERROR_FILE")"
expected="tron:git-pr: branch 'tron-os/example-change' has no Jira key; expected <KEY>-<slug>. Stop before opening the PR."
[ "$actual" = "$expected" ] || {
  echo "FAIL: expected exact keyless-branch error" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
}

TERMINAL_ASSIGNMENT='JIRA_KEY="$(bash "$SKILL_DIR/scripts/resolve-jira-key.sh" "$BRANCH")" || exit $?'
rg -Fqx "$TERMINAL_ASSIGNMENT" "$SKILL" || {
  echo "FAIL: Step 1 must stop when Jira-key resolution fails" >&2
  exit 1
}

CONTINUED="$ERROR_FILE.continued"
if bash -c 'JIRA_KEY="$(bash "$1" "$2")" || exit $?; : > "$3"' bash \
  "$SCRIPT" tron-os/example-change "$CONTINUED" 2>/dev/null; then
  echo "FAIL: expected the Step 1 assignment to exit nonzero" >&2
  exit 1
fi
[ ! -e "$CONTINUED" ] || {
  echo "FAIL: Step 1 continued after Jira-key resolution failed" >&2
  exit 1
}

echo "✅ git-pr Jira-key resolver PASSED (4 checks)"
