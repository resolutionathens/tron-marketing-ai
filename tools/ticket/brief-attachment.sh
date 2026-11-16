#!/usr/bin/env bash
# brief-attachment.sh — attach a pilot ticket's engineering brief to Jira.
#
# An engineering ticket's brief is the attachment <KEY>-engineering.md
# (pilot-template.md, "Where it lives"); rubric-lint.sh --key grades the newest
# one. acli has no attachment upload, so this posts to Jira's REST API with
# ATLASSIAN_EMAIL + JIRA_API_TOKEN. The file is always sent under the exact
# brief name, whatever the local file is called.
#
# Usage:
#   brief-attachment.sh upload <KEY> <file>   # prints {key, id, filename}
#
# Env: ATLASSIAN_EMAIL, JIRA_API_TOKEN (required); JIRA_BASE (default
# https://facilitron.atlassian.net).
set -euo pipefail

usage() { sed -n '2,14p' "$0" >&2; exit 2; }
[ "${1:-}" = upload ] || usage
KEY="${2:-}" FILE="${3:-}"
[[ "$KEY" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || { echo "brief-attachment: a Jira key is required (got: ${KEY:-nothing})" >&2; exit 2; }
[ -f "$FILE" ] || { echo "brief-attachment: no such file: ${FILE:-nothing}" >&2; exit 2; }
[ -s "$FILE" ] || { echo "brief-attachment: $FILE is empty" >&2; exit 2; }
[ -n "${ATLASSIAN_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ] \
  || { echo "brief-attachment: set ATLASSIAN_EMAIL and JIRA_API_TOKEN" >&2; exit 3; }
command -v curl >/dev/null || { echo "brief-attachment: curl not on PATH" >&2; exit 3; }
command -v jq >/dev/null || { echo "brief-attachment: jq not on PATH" >&2; exit 3; }

BASE="${JIRA_BASE:-https://facilitron.atlassian.net}"
NAME="$KEY-engineering.md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tron-brief.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$FILE" "$WORK/$NAME"

# The credentials go to curl on stdin (-K -), never in its arguments, so they stay
# out of the process list.
RESP="$(cd "$WORK" && printf 'user = "%s:%s"\n' "$ATLASSIAN_EMAIL" "$JIRA_API_TOKEN" | curl -fsS -K - \
  -H 'X-Atlassian-Token: no-check' -H 'Accept: application/json' \
  -F "file=@$NAME;type=text/markdown" \
  "$BASE/rest/api/3/issue/$KEY/attachments")" \
  || { echo "brief-attachment: upload to $KEY failed" >&2; exit 4; }

printf '%s' "$RESP" | jq -e --arg key "$KEY" --arg name "$NAME" '
  [.[]? | select(.filename == $name)] | last
  | if . == null then error("Jira returned no \($name)") else {key: $key, id: (.id|tostring), filename} end' \
  || { echo "brief-attachment: Jira's reply names no $NAME" >&2; exit 4; }
