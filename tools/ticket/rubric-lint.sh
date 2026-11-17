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
#   ... [--stage created|ready|kickoff|review | --status "<Jira status>"]
#
# Pilot types (product, engineering, bug, data, spike) are graded against
# pilot-template.md for their stage: from the Jira status with --key (or
# --stage/--status), else created. With --key, the newest <KEY>-engineering.md
# attachment is the brief when there is one (needs ATLASSIAN_EMAIL + JIRA_API_TOKEN;
# read from JIRA_BASE, default https://facilitron.atlassian.net).
#
# Output (stdout): one JSON object —
#   {key, verdict, type, prefix_ok, missing:{spine,section,recommended}, issues, present,
#    template, stage, source}
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

KEY="" FILE="" SUMMARY="" TEXT="" STAGE="" STATUS="" SOURCE=""
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
    --stage)   need_val "$1" "${2:-}"; STAGE="$2"; shift 2
               [ -n "$(rb_stage_index "$STAGE")" ] || { echo "rubric-lint: --stage is one of created, ready, kickoff, review" >&2; exit 2; } ;;
    --status)  need_val "$1" "${2:-}"; STATUS="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
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
  RAW="$(acli jira workitem view "$KEY" --fields summary,description,status,attachment --json 2>/dev/null)" \
    || { echo "rubric-lint: acli view failed for $KEY" >&2; exit 4; }
  SUMMARY="$(printf '%s' "$RAW" | jq -r '.fields.summary // ""')"
  [ -n "$STATUS" ] || STATUS="$(printf '%s' "$RAW" | jq -r '.fields.status.name // ""')"
  # The pilot brief: the newest attachment named exactly <KEY>-engineering.md
  # (pilot-template.md, "Where it lives"). Any other attachment is ignored.
  BRIEF_ID="$(printf '%s' "$RAW" | jq -r --arg name "$KEY-engineering.md" '
    [.fields.attachment[]? | select(.filename == $name and ((.id|tostring) | test("^[0-9]+$")))]
    | sort_by([(.created // ""), ((.id|tostring)|tonumber)]) | last | .id // "" | tostring')"
  if [ -n "$BRIEF_ID" ]; then
    # Download from the Jira site address, not the attachment's .content URL: acli
    # reports that on an atl-paas host that does not connect from every network
    # (MD-3420). Same base as brief-attachment.sh.
    BRIEF_URL="${JIRA_BASE:-https://facilitron.atlassian.net}/rest/api/3/attachment/content/$BRIEF_ID"
    [ -n "${ATLASSIAN_EMAIL:-}" ] && [ -n "${JIRA_API_TOKEN:-}" ] \
      || { echo "rubric-lint: $KEY has a $KEY-engineering.md brief; set ATLASSIAN_EMAIL and JIRA_API_TOKEN to read it" >&2; exit 4; }
    command -v curl >/dev/null || { echo "rubric-lint: curl not on PATH (needed to read the brief)" >&2; exit 3; }
    # Credentials on stdin (-K -), never in curl's arguments (the process list).
    TEXT="$(printf 'user = "%s:%s"\n' "$ATLASSIAN_EMAIL" "$JIRA_API_TOKEN" | curl -fsSL -K - "$BRIEF_URL")" \
      || { echo "rubric-lint: could not download $KEY-engineering.md" >&2; exit 4; }
    SOURCE="attachment:$KEY-engineering.md"
  else
    # Walk the ADF description; each text node becomes its own line so line-anchored
    # markers survive regardless of how paragraphs were grouped.
    TEXT="$(printf '%s' "$RAW" | jq -r '
      [.fields.description? | .. | objects | select(.type=="text") | .text] | join("\n")')"
    SOURCE="description"
    if rb_is_pilot_type "$(rb_type "$TEXT")"; then
      # A pilot ticket needs its shape back (the fenced header, ## sections, table rows),
      # the way Baton's adfToMarkdown reads it.
      TEXT="$(printf '%s' "$RAW" | jq -r '
        def inl: if type != "object" then ""
          elif .type == "hardBreak" then "\n"
          elif (.text | type) == "string" then .text
          else ((.content // []) | map(inl) | join("")) end;
        def blk: if .type == "codeBlock" then "```\n" + inl + "\n```"
          elif .type == "heading" then ([range(.attrs.level // 2)] | map("#") | join("")) + " " + inl
          elif .type == "table" then ((.content // []) | map("| " + ((.content // []) | map(inl | gsub("^\\s+|\\s+$"; "")) | join(" | ")) + " |") | join("\n"))
          elif .type == "bulletList" or .type == "orderedList" then ((.content // []) | map("- " + inl) | join("\n"))
          else inl end;
        [(.fields.description.content // [])[] | blk] | join("\n\n")')"
    fi
  fi
elif [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { echo "rubric-lint: no such file: $FILE" >&2; exit 4; }
  TEXT="$(cat "$FILE")"
  SOURCE="file"
else
  TEXT="$(cat)"
  SOURCE="stdin"
fi

PREFIX_OK=0; [ -n "$SUMMARY" ] && rb_prefix_ok "$SUMMARY" && PREFIX_OK=1

TYPE="$(rb_type "$TEXT")"
TEMPLATE=rubric
if rb_is_pilot_type "$TYPE"; then
  TEMPLATE=pilot
  [ -n "$STAGE" ] || STAGE="$(rb_stage_for_status "$STATUS")"
else
  STAGE=""
fi

VERDICT="$(rb_verdict "$TEXT" "$PREFIX_OK" "${STAGE:-created}")"
MISS="$(rb_missing "$TEXT" "$PREFIX_OK" "${STAGE:-created}")"
# A pilot ticket's criteria live in its header (the fenced block).
AC_TEXT="$TEXT"; [ "$TEMPLATE" = pilot ] && AC_TEXT="$(rb_pilot_header "$TEXT")"
GATES="$(rb_command_gate_criteria "$AC_TEXT")"

spine="$(   printf '%s\n' "$MISS" | sed -n 's/^spine://p')"
section="$( printf '%s\n' "$MISS" | sed -n 's/^section://p')"
rec="$(     printf '%s\n' "$MISS" | sed -n 's/^rec://p')"
issues="$(printf '%s\n' "$GATES" | sed '/^$/d; s/^/Acceptance criterion asserts a command result: /; s/$/. State the verification in the description instead, then describe a reviewable property of the change here./')"
# SR-6176: a criterion that asks, or names nothing to check, and a Done or Intent that asks.
UNCHECKABLE="$(rb_uncheckable_criteria "$AC_TEXT")"
while IFS="$(printf '\t')" read -r kind criterion; do
  [ -n "$kind" ] || continue
  if [ "$kind" = question ]; then
    line="Acceptance criterion is a question, not something to check: $criterion. Keep the question for the reviewer, and state here one outcome a person or a browser test can check pass or fail."
  else
    line="Acceptance criterion names no outcome anyone can check: $criterion. Name one thing a person or a browser test can check pass or fail (an address, a text, an element's state, a response)."
  fi
  issues="$issues"$'\n'"$line"
done <<< "$UNCHECKABLE"
for k in Done Intent; do
  v="$(rb_marker_value "$AC_TEXT" "$k" || true)"
  if rb_value_is_real "$v" && rb_ends_question "$v"; then
    issues="$issues"$'\n'"$k is a question: $v. State the outcome instead, and keep the question for the reviewer."
  fi
done
# Pilot template: the rules a ticket breaks for its stage, then advice.
issues="$issues"$'\n'"$(printf '%s\n' "$MISS" | sed -n 's/^problem://p')"
issues="$issues"$'\n'"$(printf '%s\n' "$MISS" | sed -n 's/^warning:/Warning: /p')"

# Present spine+section markers (for the "what's already good" line).
present=""
if [ "$TEMPLATE" = pilot ]; then
  while IFS= read -r entry; do
    k="${entry%%|*}"
    case "$k" in
      Type) present="${present}Type"$'\n' ;;
      "Acceptance criteria")
         printf '%s\n' "$MISS" | grep -qx "section:$k" \
           || [ -z "$(rb_pilot_header_acs "$TEXT")" ] \
           || present="$present$k"$'\n' ;;
      *) printf '%s\n' "$MISS" | grep -qxE "(spine|section):$k" \
           || ! rb_pilot_value_is_real "$(rb_marker_value "$AC_TEXT" "$k")" \
           || present="$present$k"$'\n' ;;
    esac
  done < <(rb_pilot_fields)
  for n in $(rb_pilot_filled_sections "$TEXT"); do
    present="${present}section $n. $(rb_pilot_section_name "$n")"$'\n'
  done
else
  for k in Done "Deliverable type" Type Context Decision Intent \
           Repo "Acceptance criteria" "Affected paths" \
           Figma Format "Brand refs" Lands Destination "SEO target" Draft; do
    rb_present "$TEXT" "$k" && present="$present$k"$'\n'
  done
fi

jq -n \
  --arg key "$KEY" --arg verdict "$VERDICT" --arg type "$TYPE" \
  --argjson prefix_ok "$PREFIX_OK" \
  --arg spine "$spine" --arg section "$section" --arg rec "$rec" --arg issues "$issues" --arg present "$present" \
  --arg template "$TEMPLATE" --arg stage "$STAGE" --arg source "$SOURCE" \
  '
  def lines: split("\n") | map(select(length > 0));
  {
    key: $key,
    verdict: $verdict,
    type: $type,
    prefix_ok: ($prefix_ok == 1),
    missing: { spine: ($spine|lines), section: ($section|lines), recommended: ($rec|lines) },
    issues: ($issues|lines),
    present: ($present|lines),
    template: $template,
    stage: (if $stage == "" then null else $stage end),
    source: $source
  }'
