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

# MD-3017: a plugin release branch has no ticket, so it resolves to an EMPTY key
# and exit 0 — Step 1's `JIRA_KEY="$(...)" || exit $?` must continue, not stop.
for release_branch in release-v0.51.0 release-v1.2.3 release-v10.0.0-rc.1; do
  if ! actual="$(bash "$SCRIPT" "$release_branch")"; then
    echo "FAIL: expected release branch '$release_branch' to resolve with exit 0" >&2
    exit 1
  fi
  [ -z "$actual" ] || {
    echo "FAIL: expected release branch '$release_branch' to resolve to an EMPTY key, got: $actual" >&2
    exit 1
  }
done

# The Step 1 assignment must CONTINUE on a release branch (the mirror of the
# keyless-branch case above, which must not continue).
RELEASE_CONTINUED="$ERROR_FILE.release-continued"
bash -c 'JIRA_KEY="$(bash "$1" "$2")" || exit $?; : > "$3"' bash \
  "$SCRIPT" release-v0.51.0 "$RELEASE_CONTINUED" 2>/dev/null || {
  echo "FAIL: Step 1 assignment must exit zero on a release branch" >&2
  exit 1
}
[ -e "$RELEASE_CONTINUED" ] || {
  echo "FAIL: Step 1 stopped on a release branch instead of continuing" >&2
  exit 1
}
rm -f "$RELEASE_CONTINUED"

# The exception is exactly the release convention — near misses still stop, so it
# cannot be used to smuggle an ordinary keyless branch past the gate.
for near_miss in releasey-thing release-vX release- releases-v1.0.0 not-release-v1.0.0; do
  if bash "$SCRIPT" "$near_miss" 2>/dev/null; then
    echo "FAIL: expected near-miss branch '$near_miss' to stop" >&2
    exit 1
  fi
done

# The release exception must not have disturbed an ordinary keyed branch.
actual="$(bash "$SCRIPT" MD-3017-let-git-pr-open-a-ticketless-release-pr)"
[ "$actual" = "MD-3017" ] || {
  echo "FAIL: expected MD-3017 from a keyed branch, got: $actual" >&2
  exit 1
}

# SKILL.md must tell the reader what to do with the empty key, or a worker emits "()".
rg -Fq 'On a plugin release branch `$JIRA_KEY` is empty' "$SKILL" || {
  echo "FAIL: Step 4 must say to omit the suffix when the Jira key is empty" >&2
  exit 1
}

echo "✅ git-pr Jira-key resolver PASSED (14 checks)"
