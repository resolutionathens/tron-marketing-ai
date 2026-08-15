#!/usr/bin/env bash
# rubric-lint.sh — score one ticket against the ticket rubric and emit JSON.
#
# The deterministic backbone of tron:ticket-lint. Reads a ticket description as
# plain text (from --key via acli, --file, or stdin), parses the rubric's
# machine-readable markers with rubric-lib.sh, and reports the verdict Scout
# triage would give plus the concrete gaps. Offline for --file/stdin; --key
# needs acli + jq. Spec: tools/ticket/ticket-rubric.md.
#
# Usage:
#   rubric-lint.sh --key MD-1234                 # fetch + lint a live ticket
#   rubric-lint.sh --file desc.md [--summary S]  # lint a local description
#   echo "<desc>" | rubric-lint.sh [--summary S] # lint stdin
#
# Output (stdout): one JSON object —
#   {key, verdict, type, prefix_ok, missing:{spine,section,recommended}, issues, present}
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/rubric-lib.sh"

# Known summary PREFIX: values (mirror tools/jira/conventions.md). A summary that
# starts with one of these satisfies engineering's Repo requirement on its own.
RB_PREFIXES="TRON-PLUGIN SCOUT PAGES LLLP MABE SUPPORT UI"

rb_prefix_ok() {   # $1 = summary
  local sum="$1" head p
  head="$(printf '%s' "$sum" | sed -E 's/:.*$//')"
  for p in $RB_PREFIXES; do [ "$head" = "$p" ] && return 0; done
  return 1
}

KEY="" FILE="" SUMMARY="" TEXT=""
# Each value-taking flag needs a value that is present and not itself a flag, so a
# missing value fails deterministically instead of tripping `set -u` further down.
need_val() {   # $1 = flag name, $2 = candidate value (may be unset)
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#-}" != "$2" ]; then
    echo "rubric-lint: $1 needs a value" >&2; exit 2
  fi
}
while [ $# -gt 0 ]; do
  case "$1" in
    --key)     need_val "$1" "${2:-}"; KEY="$2"; shift 2 ;;
    --file)    need_val "$1" "${2:-}"; FILE="$2"; shift 2 ;;
    --summary) need_val "$1" "${2:-}"; SUMMARY="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "rubric-lint: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --key and --file are mutually exclusive (they name different sources).
if [ -n "$KEY" ] && [ -n "$FILE" ]; then
  echo "rubric-lint: --key and --file are mutually exclusive" >&2; exit 2
fi

# jq builds the JSON output in every mode, so require it up front (acli is only
# needed for the --key path and is checked there).
command -v jq >/dev/null || { echo "rubric-lint: jq not on PATH (required for JSON output)" >&2; exit 3; }

if [ -n "$KEY" ]; then
  command -v acli >/dev/null || { echo "rubric-lint: acli not on PATH" >&2; exit 3; }
  RAW="$(acli jira workitem view "$KEY" --fields summary,description --json 2>/dev/null)" \
    || { echo "rubric-lint: acli view failed for $KEY" >&2; exit 4; }
  SUMMARY="$(printf '%s' "$RAW" | jq -r '.fields.summary // ""')"
  # Walk the ADF description; each text node becomes its own line so line-anchored
  # markers survive regardless of how paragraphs were grouped.
  TEXT="$(printf '%s' "$RAW" | jq -r '
    [.fields.description? | .. | objects | select(.type=="text") | .text] | join("\n")')"
elif [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { echo "rubric-lint: no such file: $FILE" >&2; exit 4; }
  TEXT="$(cat "$FILE")"
else
  TEXT="$(cat)"
fi

PREFIX_OK=0; [ -n "$SUMMARY" ] && rb_prefix_ok "$SUMMARY" && PREFIX_OK=1

VERDICT="$(rb_verdict "$TEXT" "$PREFIX_OK")"
TYPE="$(rb_type "$TEXT")"
MISS="$(rb_missing "$TEXT" "$PREFIX_OK")"
GATES="$(rb_command_gate_criteria "$TEXT")"

spine="$(   printf '%s\n' "$MISS" | sed -n 's/^spine://p')"
section="$( printf '%s\n' "$MISS" | sed -n 's/^section://p')"
rec="$(     printf '%s\n' "$MISS" | sed -n 's/^rec://p')"
issues="$(printf '%s\n' "$GATES" | sed '/^$/d; s/^/Acceptance criterion asserts a command result: /; s/$/. State the verification in the description instead, then describe a reviewable property of the change here./')"

# Present spine+section markers (for the "what's already good" line).
present=""
for k in Done "Deliverable type" Type Context Decision \
         Repo "Acceptance criteria" "Affected paths" \
         Figma Format "Brand refs" Lands Destination "SEO target" Draft; do
  rb_present "$TEXT" "$k" && present="$present$k"$'\n'
done

jq -n \
  --arg key "$KEY" --arg verdict "$VERDICT" --arg type "$TYPE" \
  --argjson prefix_ok "$PREFIX_OK" \
  --arg spine "$spine" --arg section "$section" --arg rec "$rec" --arg issues "$issues" --arg present "$present" \
  '
  def lines: split("\n") | map(select(length > 0));
  {
    key: $key,
    verdict: $verdict,
    type: $type,
    prefix_ok: ($prefix_ok == 1),
    missing: { spine: ($spine|lines), section: ($section|lines), recommended: ($rec|lines) },
    issues: ($issues|lines),
    present: ($present|lines)
  }'
