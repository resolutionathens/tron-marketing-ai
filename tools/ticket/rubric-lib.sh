#!/usr/bin/env bash
# rubric-lib.sh — pure, offline-testable primitives for the ticket rubric
# (tools/ticket/ticket-rubric.md). Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/ticket/rubric-lib.sh"
#
# This is the executable form of the rubric spec. It parses the machine-readable
# `Key: value` markers out of a ticket description (plain text) and computes the
# same verdict Scout triage reports, so tron:create-ticket and tron:ticket-lint
# (and, on the SCOUT side, triage) all score a ticket identically. If you change
# a marker key or the verdict ladder here, change ticket-rubric.md and the SCOUT
# fixtures in lockstep — and update test-rubric-lint.sh. rubric-version: 2.

# --- marker presence ---------------------------------------------------------

# Echo the raw value of the first `Key:` marker in <text>. Keys match at line
# start, case-insensitively; the value is everything after the FIRST colon, so
# URL values (https://…) survive intact. Empty output when absent.
rb_marker_value() {
  local text="$1" key="$2"
  printf '%s\n' "$text" \
    | grep -iE "^[[:space:]]*${key}:" \
    | head -1 \
    | sed -E 's/^[[:space:]]*[^:]*:[[:space:]]*//'
}

# Is a value "real" (a genuine answer, not blank or a bare placeholder)?
# Placeholders (TBD, TODO, ???, -, n/a) and <bracketed> stubs count as empty:
# "present but empty" is a gap, not a pass. Returns 0 real, 1 empty/placeholder.
rb_value_is_real() {
  local v; v="$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -n "$v" ] || return 1
  case "$v" in '<'*'>') return 1 ;; esac   # <placeholder>
  local low; low="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
  case "$low" in tbd|todo|'???'|'-'|n/a|na) return 1 ;; esac
  return 0
}

# Is marker <key> present AND filled in <text>? Returns 0 present, 1 missing.
rb_marker_present() {
  rb_value_is_real "$(rb_marker_value "$1" "$2")"
}

# A list-introducing marker (e.g. `Acceptance criteria:`) counts as present when
# it has an inline value OR its header line is followed by a bullet. Returns 0/1.
rb_list_marker_present() {
  local text="$1" key="$2" n first
  rb_marker_present "$text" "$key" && return 0
  n="$(printf '%s\n' "$text" | grep -inE "^[[:space:]]*${key}:[[:space:]]*$" | head -1 | cut -d: -f1)"
  [ -n "$n" ] || return 1
  first="$(printf '%s\n' "$text" | tail -n +"$((n+1))" | grep -vE '^[[:space:]]*$' | head -1)"
  [[ "$first" =~ ^[[:space:]]*[-*][[:space:]] ]]
}

# Echo each acceptance-criteria bullet (or an inline criterion), one per line.
rb_acceptance_criteria_lines() {
  local text="$1"
  printf '%s\n' "$text" | awk '
    BEGIN { active = 0 }
    tolower($0) ~ /^[[:space:]]*acceptance criteria:[[:space:]]*$/ { active = 1; next }
    active && /^[[:space:]]*$/ { next }
    active && /^[[:space:]]*[-*][[:space:]]/ {
      sub(/^[[:space:]]*[-*][[:space:]]*/, "")
      print
      next
    }
    active { exit }
  '
  local inline
  inline="$(rb_marker_value "$text" "Acceptance criteria")"
  [ -n "$inline" ] && printf '%s\n' "$inline"
}

# Echo acceptance criteria that are only process gates, not reviewable outcomes.
# A named command is fine when it describes observable behaviour; only a criterion
# whose whole content says that a command/suite/CI succeeded is rejected.
rb_command_gate_criteria() {
  local criterion lower command_passes
  while IFS= read -r criterion; do
    [ -n "$criterion" ] || continue
    lower="$(printf '%s' "$criterion" | tr '[:upper:]' '[:lower:]')"
    command_passes=1
    case "$lower" in
      bun\ *|npm\ *|pnpm\ *|yarn\ *|npx\ *|node\ *|make\ *|just\ *|cargo\ *|go\ *|pytest\ *|rspec\ *|bundle\ *|gradle\ *|mvn\ *)
        case "$lower" in
          *\ passes|*\ passes.|*\ succeeds|*\ succeeds.) command_passes=0 ;;
        esac ;;
    esac
    if [[ "$lower" =~ ^.+[[:space:]]exits?([[:space:]]+with)?([[:space:]]+(an?[[:space:]]+)?)?(code[[:space:]]*)?0[.!]?$ ]] \
      || [[ "$lower" =~ ^.+[[:space:]]returns?([[:space:]]+with)?([[:space:]]+(an?[[:space:]]+)?)?(code[[:space:]]*)?0[.!]?$ ]] \
      || [[ "$lower" =~ ^(the[[:space:]]+)?(test[[:space:]]+)?suite[[:space:]]+passes[.!]?$ ]] \
      || [[ "$lower" =~ ^(the[[:space:]]+)?(test[[:space:]]+)?suite[[:space:]]+succeeds[.!]?$ ]] \
      || [[ "$lower" =~ ^ci([[:space:]]+build)?[[:space:]]+(is[[:space:]]+)?green[.!]?$ ]] \
      || [[ "$lower" =~ ^ci([[:space:]]+build)?[[:space:]]+(is[[:space:]]+)?passing[.!]?$ ]] \
      || [[ "$lower" =~ ^ci([[:space:]]+build)?[[:space:]]+passes[.!]?$ ]] \
      || [[ "$lower" =~ ^ci([[:space:]]+build)?[[:space:]]+succeeds[.!]?$ ]] \
      || [ "$command_passes" -eq 0 ]; then
      printf '%s\n' "$criterion"
    fi
  done < <(rb_acceptance_criteria_lines "$1")
}

# Acceptance criteria are valid when present and none is a command-result gate.
rb_acceptance_criteria_valid() {
  rb_list_marker_present "$1" "Acceptance criteria" || return 1
  [ -z "$(rb_command_gate_criteria "$1")" ]
}

# Presence check for any rubric marker, dispatching the list-style ones.
rb_present() {
  case "$2" in
    "Acceptance criteria") rb_acceptance_criteria_valid "$1" ;;
    *)                     rb_marker_present "$1" "$2" ;;
  esac
}

# --- work type ---------------------------------------------------------------

# Echo the normalized Type: value
# (engineering|design|content|campaign-asset|cms), or empty.
rb_type() {
  local v; v="$(rb_marker_value "$1" "Type" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z-].*$//')"
  case "$v" in
    engineering|eng) echo engineering ;;
    design)          echo design ;;
    content)         echo content ;;
    campaign-asset)  echo campaign-asset ;;
    cms)             echo cms ;;
    *)               echo "" ;;
  esac
}

# Echo the pipe-delimited allowed Deliverable type values for a Type.
rb_deliverable_types() {
  case "$1" in
    engineering)    echo "pr|page|bugfix|config|script" ;;
    design)         echo "figma|image|pdf|brand-asset" ;;
    content)        echo "news|guide|toolkit|case-study|pdf" ;;
    campaign-asset) echo "image|pdf|print|merch|collateral" ;;
    cms)            echo "page-edit|bugfix|content-update" ;;
    *)              echo "" ;;
  esac
}

# Does Deliverable type contain an allowed value for the normalized Type?
# Matching is case-insensitive but otherwise exact. Returns 0 valid, 1 invalid.
rb_deliverable_type_valid() {
  local text="$1" type="$2" value allowed item
  value="$(rb_marker_value "$text" "Deliverable type" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  rb_value_is_real "$value" || return 1
  allowed="$(rb_deliverable_types "$type")"
  [ -n "$allowed" ] || return 1
  local IFS='|'
  for item in $allowed; do
    [ "$value" = "$item" ] && return 0
  done
  return 1
}

# Echo the pipe-delimited required section markers for a Type. Empty for none.
# Keep in lockstep with the work-type tables in ticket-rubric.md.
rb_section_markers() {
  case "$1" in
    engineering) echo "Repo|Acceptance criteria|Affected paths" ;;
    design)      echo "Figma|Format|Brand refs|Lands" ;;
    content)     echo "Destination|Format|SEO target|Draft" ;;
    campaign-asset) echo "Campaign|Asset|Format|Lands" ;;
    cms)         echo "CMS|Edit URL|Verify URL" ;;
    *)           echo "" ;;
  esac
}

# Echo markers whose values resolve to openable work or verification targets.
# Downstream locatability fail-safes may consume this set.
rb_resolvable_locator_markers() {
  echo "Figma|Draft|Edit URL|Verify URL"
}

# Echo placement-only context. These markers route work but do not guarantee
# anything openable, so they must not clear a locatability fail-safe.
rb_placement_context_markers() {
  echo "Campaign|Lands|Destination"
}

# --- assessment --------------------------------------------------------------

# Echo the missing markers, one per line, tagged by class:
#   spine:<Key>     a required spine marker is absent
#   section:<Key>   a required work-type section marker is absent
#   rec:<Key>       a recommended marker (Decision) is absent
# Args: <text> [<prefix_ok>]  — prefix_ok=1 means the summary carries a valid
# PREFIX:, which satisfies engineering's Repo requirement on its own.
rb_missing() {
  local text="$1" prefix_ok="${2:-0}" type
  rb_present "$text" Done || printf 'spine:Done\n'
  rb_present "$text" Context || printf 'spine:Context\n'
  type="$(rb_type "$text")"
  if rb_present "$text" Type && [ -n "$type" ]; then
    rb_deliverable_type_valid "$text" "$type" || printf 'spine:Deliverable type\n'
  else
    printf 'spine:Type\n'
    rb_present "$text" "Deliverable type" || printf 'spine:Deliverable type\n'
  fi
  rb_present "$text" Decision || printf 'rec:%s\n' Decision
  if [ -n "$type" ]; then
    local IFS='|' ms m
    read -ra ms <<< "$(rb_section_markers "$type")"
    for m in "${ms[@]}"; do
      [ "$m" = Repo ] && [ "$prefix_ok" = 1 ] && continue
      rb_present "$text" "$m" || printf 'section:%s\n' "$m"
    done
  fi
}

# Echo the canonical verdict string for <text> [<prefix_ok>]. This ladder mirrors
# Scout triage exactly (ticket-rubric.md → "The verdict mapping").
rb_verdict() {
  local miss; miss="$(rb_missing "$1" "${2:-0}")"
  if grep -qxE 'spine:(Done|Deliverable type)' <<< "$miss"; then
    echo "none: needs human direction"; return
  fi
  grep -q '^spine:'   <<< "$miss" && { echo "low: needs enrichment"; return; }
  grep -q '^section:' <<< "$miss" && { echo "medium: routable but thin"; return; }
  echo "high: actionable"
}
