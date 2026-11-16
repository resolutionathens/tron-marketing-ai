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
# fixtures in lockstep — and update test-rubric-lint.sh. rubric-version: 5.
# Since version 5 the pilot types (product, engineering, bug, data, spike) are
# graded against pilot-template.md by the rb_pilot_* functions below.

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
    # A pilot criterion's number (`AC1 CI is green`, `**AC2** npm test passes`) is not
    # part of what it asserts (MD-3405); the criterion is still reported as written.
    lower="$(printf '%s' "$criterion" | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/^[[:space:]]*(\*+[[:space:]]*)?ac[0-9]+(\*+)?[[:space:]]+//')"
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

# --- checkable outcomes (SR-6176) -------------------------------------------
# An acceptance criterion names one thing a person or a browser test can check pass
# or fail (an address, a text, an element's state, a response). A question ("shouldn't
# all staging pages be https?") or a word that checks nothing ("it works", "as
# expected") is not one: agents went round after round of review trying to meet such
# criteria. Quoted copy (“Need help?” or "Need help?") is what a page says, never the criterion asking,
# so it is masked before reading. Baton mirrors these rules in
# lib/ticket-rules/rubric.ts; keep the two in lockstep.
#
# rb_text_kind reads stdin, one criterion or value per line, and echoes per line:
#   question   it asks (ends with "?", or opens the way a question does)
#   vague      its outcome names nothing to check
#   ends-q     (with --ends-question) only whether it ends with a question mark
#   (empty)    a checkable statement
# perl -CSD reads and writes UTF-8 whatever the locale, so curly quotes match on
# macOS bash 3.2 and BSD tools.
rb_text_kind() {
  local mode="${1:-}"
  perl -CSD -ne '
    my $mode = "'"$mode"'";
    chomp;
    my $s = $_;
    $s =~ s/^\s*AC\d+\s+//;
    sub flat {
      my $t = shift;
      $t =~ s/\x{201C}[^\x{201D}]*\x{201D}/\x{201C}\x{2026}\x{201D}/g;
      $t =~ s/"[^"]*"/"\x{2026}"/g;
      $t =~ s/\s+/ /g;
      $t =~ s/^\s+|\s+$//g;
      return $t;
    }
    sub asks {
      my $t = flat(shift);
      $t =~ s/[\x{201D}"\x{2019}\x27)\]]+$//;
      return 1 if $t =~ /\?$/;
      return 1 if $t =~ /^(why|how come|what if|shouldn[\x{2019}\x27]?t|wouldn[\x{2019}\x27]?t|couldn[\x{2019}\x27]?t|isn[\x{2019}\x27]?t it|aren[\x{2019}\x27]?t (they|these|those))\b/i;
      return 1 if $t =~ /^(is|are|was|were|does|do|did|can|could|should|would|will|has|have)\s+(the|this|that|these|those|it|there|we|you|they|all|any|every|our|my)\b/i;
      return 0;
    }
    if ($mode eq "--ends-question") {
      print((flat($s) =~ /\?[\x{201D}"\x{2019}\x27)\]]*$/) ? "ends-q\n" : "\n");
      next;
    }
    my $m = flat($s);
    my $o = index($m, ": ") >= 0 ? substr($m, rindex($m, ": ") + 2) : $m;
    my $vague = qr/^(it |this |that )?(works?|is fixed|gets fixed|is better|is improved|behaves (correctly|as expected)|as expected|looks (good|right|fine)|should work|is correct|n\/?a|tbd|none yet\b.*)[.!]?$/i;
    if (asks($m) || asks($o)) { print "question\n" }
    elsif ($o =~ $vague || $m =~ $vague) { print "vague\n" }
    else { print "\n" }
  '
}

# Does a single value end with a question mark (quoted copy aside)? Returns 0 yes, 1 no.
rb_ends_question() {
  [ "$(printf '%s\n' "$1" | rb_text_kind --ends-question)" = ends-q ]
}

# Echo `question<TAB>criterion` or `vague<TAB>criterion` for each acceptance
# criterion that names nothing to check. A command gate is reported by
# rb_command_gate_criteria instead, never twice.
rb_uncheckable_criteria() {
  local criterion kind gates
  gates="$(rb_command_gate_criteria "$1")"
  while IFS= read -r criterion; do
    [ -n "$criterion" ] || continue
    if [ -n "$gates" ] && printf '%s\n' "$gates" | grep -qxF -- "$criterion"; then continue; fi
    kind="$(printf '%s\n' "$criterion" | rb_text_kind)"
    if [ -n "$kind" ]; then printf '%s\t%s\n' "$kind" "$criterion"; fi
  done < <(rb_acceptance_criteria_lines "$1")
}

# Acceptance criteria are valid when present, none is a command-result gate, and
# each names an outcome someone can check.
rb_acceptance_criteria_valid() {
  rb_list_marker_present "$1" "Acceptance criteria" || return 1
  [ -z "$(rb_command_gate_criteria "$1")" ] || return 1
  [ -z "$(rb_uncheckable_criteria "$1")" ]
}

# `Repo:` names one repository or several, comma-separated (rubric-version 4). Each
# entry must be a repo key (`marketing-pages`) or `owner/repo`, optionally followed by a
# note in parentheses (`marketing-pages (footer only)`). Returns 0 valid, 1 invalid.
rb_repo_valid() {
  local value item key items
  # Held in a variable: rb_missing calls this under `local IFS='|'`, and bash 3.2 then
  # treats an unquoted `|` in an inline regex as a literal character (MD-3268).
  local empty_entry='(^|,)[[:space:]]*(,|$)'
  value="$(rb_marker_value "$1" "Repo")"
  rb_value_is_real "$value" || return 1
  # Notes come out first, so a comma inside one doesn't split an entry.
  value="$(printf '%s' "$value" | sed -E 's/\([^)]*\)//g')"
  # A split on commas drops a trailing empty entry, so empty entries are caught first.
  [[ "$value" =~ $empty_entry ]] && return 1
  # read -ra splits without filename expansion: a `*` in a value is text, not a glob.
  IFS=',' read -ra items <<< "$value"
  for item in "${items[@]}"; do
    key="$(printf '%s' "$item" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    rb_value_is_real "$key" || return 1
    [[ "$key" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$ ]] || return 1
  done
  return 0
}

# Presence check for any rubric marker, dispatching the list-style ones.
rb_present() {
  case "$2" in
    "Acceptance criteria") rb_acceptance_criteria_valid "$1" ;;
    Repo)                  rb_repo_valid "$1" ;;
    # A question is not a finished outcome or an intended one (SR-6176).
    Done|Intent)           rb_marker_present "$1" "$2" && ! rb_ends_question "$(rb_marker_value "$1" "$2")" ;;
    *)                     rb_marker_present "$1" "$2" ;;
  esac
}

# Is this a research ticket: engineering work with no pull request expected
# (`Deliverable type: research`, rubric-version 4)? Returns 0 yes, 1 no.
rb_is_research() {
  [ "$(rb_type "$1")" = engineering ] || return 1
  [ "$(rb_marker_value "$1" "Deliverable type" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')" = research ]
}

# --- work type ---------------------------------------------------------------

# Echo the normalized Type: value (the pilot types product|engineering|bug|data|spike,
# or the marker-rubric types design|content|campaign-asset|cms), or empty.
rb_type() {
  local v; v="$(rb_marker_value "$1" "Type" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z-].*$//')"
  case "$v" in
    engineering|eng) echo engineering ;;
    product)         echo product ;;
    bug)             echo bug ;;
    data)            echo data ;;
    spike)           echo spike ;;
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
    engineering)    echo "pr|page|bugfix|config|script|research" ;;
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

# --- pilot template (rubric-version 5, MD-3405) ------------------------------
# product, engineering, bug, data and spike tickets are graded against the pilot
# template (pilot-template.md): a fenced metadata header, then numbered sections
# 1 to 7, with the fields each Jira stage requires. Baton's lib/ticket-rules/pilot.ts
# mirrors these rules (SR-6185); keep the two in lockstep.

# Is <type> one of the pilot template's types? Returns 0 yes, 1 no.
rb_is_pilot_type() {
  case "$1" in product|engineering|bug|data|spike) return 0 ;; esac
  return 1
}

# Echo the pilot stage for a Jira status: created|ready|kickoff|review. Anything
# unrecognised counts as just created.
rb_stage_for_status() {
  local s; s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  # Held in variables: bash 3.2 reads an inline `|` literally under a caller's IFS='|' (MD-3268).
  local review_re='review|uat|done|released' qa_re='[^a-z]qa[^a-z]' kickoff_re='progress|develop'
  if [[ "$s" =~ $review_re ]] || [[ " $s " =~ $qa_re ]]; then echo review
  elif [[ "$s" =~ ready ]]; then echo ready
  elif [[ "$s" =~ $kickoff_re ]]; then echo kickoff
  else echo created
  fi
}

# Echo a stage's position (0 to 3), or nothing for an unknown stage.
rb_stage_index() {
  case "$1" in created) echo 0 ;; ready) echo 1 ;; kickoff) echo 2 ;; review) echo 3 ;; esac
}

# The header fields in order, each with the first stage that requires it.
rb_pilot_fields() {
  printf '%s\n' "Done|created" "Intent|created" "Type|created" "Deliverable type|created" \
    "Stakeholder|created" "Context|created" "Decision|created" "Engineer|ready" \
    "Acceptance criteria|ready" "Repo|kickoff" "Affected paths|kickoff"
}

# The section names, numbered 1 to 7.
rb_pilot_section_name() {
  case "$1" in
    1) echo "Problem" ;; 2) echo "Scope" ;; 3) echo "Pages & Roles" ;;
    4) echo "Pre-conditions & Test Data" ;; 5) echo "Acceptance Criteria" ;;
    6) echo "Design, Links & Decisions" ;; 7) echo "Change log" ;;
  esac
}

# The sections a type needs from ready on (pilot-template.md, "Sections by type").
rb_pilot_type_sections() {
  case "$1" in
    bug)   echo "1 3 4 5" ;;
    data)  echo "1 2 5" ;;
    spike) echo "1 2 6" ;;
    *)     echo "1 2 3 4 5 6" ;;
  esac
}

# A pilot value is real when the rubric says so and it isn't a [bracketed] stub or
# an Engineer that is still nobody ("not yet assigned"). Returns 0 real, 1 not.
rb_pilot_value_is_real() {
  rb_value_is_real "$1" || return 1
  local low; low="$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]')"
  case "$low" in '['*']'|'?'|'??'|'????'|'not yet assigned'|unassigned) return 1 ;; esac
  return 0
}

# Echo the metadata header: the first fenced block's lines, or the whole text when
# there is no fence (a plain list of markers still grades).
rb_pilot_header() {
  if printf '%s\n' "$1" | grep -qE '^[[:space:]]*```'; then
    printf '%s\n' "$1" | awk '
      /^[[:space:]]*```/ { if (inside) exit; inside = 1; next }
      inside { print }'
  else
    printf '%s\n' "$1"
  fi
}

# Echo the text after the header's closing fence (all of it when there is no fence).
rb_pilot_body() {
  if printf '%s\n' "$1" | grep -qE '^[[:space:]]*```'; then
    printf '%s\n' "$1" | awk '
      done { print; next }
      /^[[:space:]]*```/ { fences++; if (fences == 2) done = 1; next }'
  else
    printf '%s\n' "$1"
  fi
}

# Echo the body of section <n> (the lines under `## <n>. …` up to the next numbered
# heading), trimmed of blank lines at either end.
rb_pilot_section() {
  rb_pilot_body "$1" | awk -v n="$2" '
    /^###?[[:space:]]*[0-9]\./ {
      h = $0; sub(/^#+[[:space:]]*/, "", h); num = substr(h, 1, 1)
      active = (num == n); next
    }
    active { print }' | sed -E '/./,$!d' | awk '{ lines[NR] = $0 } END {
      last = NR; while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i] }'
}

# Echo the numbers of the sections that have content, space-separated, in one pass.
rb_pilot_filled_sections() {
  rb_pilot_body "$1" | awk '
    /^###?[[:space:]]*[0-9]\./ { h = $0; sub(/^#+[[:space:]]*/, "", h); num = substr(h, 1, 1); next }
    num != "" && $0 !~ /^[[:space:]]*$/ { filled[num] = 1 }
    END { for (i = 1; i <= 7; i++) if (filled[i]) printf "%d ", i }'
}

# Echo the AC ids (AC1, AC2…) at the start of each line of stdin, upper-cased.
rb_pilot_ac_ids() {
  sed -nE 's/^[[:space:]]*(\*+[[:space:]]*)?([Aa][Cc][0-9]+)([^0-9A-Za-z_].*)?$/\2/p' | tr '[:lower:]' '[:upper:]'
}

# Echo the header's numbered AC ids, one per line.
rb_pilot_header_acs() {
  rb_acceptance_criteria_lines "$(rb_pilot_header "$1")" | rb_pilot_ac_ids
}

# Echo section 5's numbered AC ids, one per line.
rb_pilot_section_acs() {
  rb_pilot_section "$1" 5 | rb_pilot_ac_ids
}

# Echo `<decision><TAB><owner>` for each row of section 6's table whose status is Open.
rb_pilot_open_decisions() {
  rb_pilot_section "$1" 6 | awk -F'|' '
    /^[[:space:]]*\|/ && $0 !~ /^[[:space:]]*\|[[:space:]]*-/ {
      n = 0
      for (i = 2; i < NF; i++) { c = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); cells[++n] = c }
      if (n >= 4 && tolower(cells[1]) != "date" && tolower(cells[4]) == "open")
        printf "%s\t%s\n", cells[2], cells[3]
    }'
}

# Is <text>'s Deliverable type research? Returns 0 yes, 1 no.
rb_pilot_is_research() {
  [ "$(rb_marker_value "$(rb_pilot_header "$1")" "Deliverable type" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')" = research ]
}

# Echo what a pilot ticket lacks for <stage>, one per line, tagged:
#   spine:<Field>      Done, Deliverable type (none) or Context, Stakeholder (low)
#   section:<Field>    another field or section the stage requires (medium)
#   problem:<text>     a rule the ticket breaks (medium)
#   warning:<text>     advice that doesn't change the verdict
# Args: <text> <stage> [<prefix_ok>]. A valid summary PREFIX stands in for a
# missing Repo, as in the marker rubric.
rb_pilot_missing() {
  local text="$1" stage="${2:-created}" prefix_ok="${3:-0}"
  local header type at entry field from value n need has_acs acs h s
  header="$(rb_pilot_header "$text")"
  type="$(rb_type "$text")"
  at="$(rb_stage_index "$stage")"; [ -n "$at" ] || at=0
  has_acs=0; case " $(rb_pilot_type_sections "$type") " in *" 5 "*) has_acs=1 ;; esac
  acs="$(rb_pilot_header_acs "$text")"
  while IFS= read -r entry; do
    field="${entry%%|*}"; from="${entry#*|}"
    value="$(rb_marker_value "$header" "$field")"
    case "$field" in
      Done)
        # A Done that asks is no Done, at every stage (SR-6176).
        if ! rb_pilot_value_is_real "$value" || rb_ends_question "$value"; then printf 'spine:Done\n'; fi
        continue ;;
      "Deliverable type"|Context|Stakeholder)
        rb_pilot_value_is_real "$value" || printf 'spine:%s\n' "$field"
        continue ;;
      Type) continue ;;   # a pilot type is already known
      "Acceptance criteria")
        # Questions, uncheckable criteria and command gates hold any stage below high (#130).
        if [ -n "$(rb_acceptance_criteria_lines "$header")" ] \
          && { [ -n "$(rb_command_gate_criteria "$header")" ] || [ -n "$(rb_uncheckable_criteria "$header")" ]; }; then
          printf 'section:Acceptance criteria\n'
        elif [ "$at" -ge "$(rb_stage_index "$from")" ] && [ "$has_acs" = 1 ] \
          && [ "$(printf '%s\n' "$acs" | sed '/^$/d' | wc -l | tr -d ' ')" -lt 2 ]; then
          printf 'section:Acceptance criteria\n'
        fi
        continue ;;
    esac
    [ "$at" -ge "$(rb_stage_index "$from")" ] || continue
    case "$field" in
      Intent)
        if ! rb_pilot_value_is_real "$value" || rb_ends_question "$value"; then printf 'section:Intent\n'; fi ;;
      Repo)
        if ! rb_pilot_value_is_real "$value"; then
          [ "$prefix_ok" = 1 ] || printf 'section:Repo\n'
        else
          rb_repo_valid "$header" || printf 'section:Repo\n'
        fi ;;
      "Affected paths")
        # Research produces no change to the code, so there are no paths to name.
        rb_pilot_is_research "$text" && continue
        rb_pilot_value_is_real "$value" || printf 'section:Affected paths\n' ;;
      *)
        rb_pilot_value_is_real "$value" || printf 'section:%s\n' "$field" ;;
    esac
  done < <(rb_pilot_fields)

  # Sections: section 1 from creation, the type's sections from ready on, and the
  # change log (section 7) once development starts, except for a spike
  # (pilot-template.md, "Sections by type").
  need=1; [ "$at" -ge 1 ] && need="$(rb_pilot_type_sections "$type")"
  [ "$at" -ge 2 ] && [ "$type" != spike ] && need="$need 7"
  local filled; filled=" $(rb_pilot_filled_sections "$text")"
  for n in $need; do
    case "$filled" in *" $n "*) ;; *) printf 'section:section %s. %s\n' "$n" "$(rb_pilot_section_name "$n")" ;; esac
  done

  if [ "$at" -ge 1 ]; then
    while IFS="$(printf '\t')" read -r h s; do
      [ -n "$h" ] || continue
      printf 'problem:Open decision at %s: "%s" (owner: %s). From ready on, an unknown is a decision with an owner, never Open.\n' \
        "$stage" "$h" "${s:-none}"
    done < <(rb_pilot_open_decisions "$text")
    if [ "$has_acs" = 1 ] && [ -n "$acs" ]; then
      h="$(printf '%s\n' "$acs" | sed '/^$/d' | paste -sd, -)"
      s="$(rb_pilot_section_acs "$text" | sed '/^$/d' | paste -sd, -)"
      [ "$h" = "$s" ] || printf "problem:Header ACs (%s) don't match section 5 (%s). Give both the same numbers.\n" "${h:-none}" "${s:-none}"
    fi
  fi

  # A product ticket says what and why, never how, until an engineer takes it.
  if [ "$type" = product ] && [ "$at" -lt 2 ]; then
    for field in Repo "Affected paths"; do
      rb_value_is_real "$(rb_marker_value "$header" "$field")" \
        && printf "problem:%s is the engineer's to fill at kickoff, not in a product ticket.\n" "$field"
    done
    local code_re='[A-Za-z0-9_./-]+\.(ts|tsx|js|jsx|mjs|cjs|vue|py|sql|php|rb|go|java|kt|swift|cs|scss|css|sh|ya?ml|graphql)([^A-Za-z0-9_]|$)|[A-Za-z0-9_]+\(\)'
    for n in 1 2 3 4 5 6 7; do
      value="$(rb_pilot_section "$text" "$n" | grep -oE "$code_re" | head -1 | sed -E 's/[^A-Za-z0-9_)]$//')"
      [ -n "$value" ] && printf 'warning:section %s names code ("%s"): leave how to build it to the engineer.\n' "$n" "$value"
    done
  fi
  return 0
}

# Echo the verdict for a pilot ticket at <stage>, on the same four-step ladder.
rb_pilot_verdict() {
  local miss; miss="$(rb_pilot_missing "$1" "${2:-created}" "${3:-0}")"
  if grep -qxE 'spine:(Done|Deliverable type)' <<< "$miss"; then echo "none: needs human direction"; return; fi
  grep -q '^spine:' <<< "$miss" && { echo "low: needs enrichment"; return; }
  grep -qE '^(section|problem):' <<< "$miss" && { echo "medium: routable but thin"; return; }
  echo "high: actionable"
}

# --- assessment --------------------------------------------------------------

# Echo the missing markers, one per line, tagged by class:
#   spine:<Key>     a required spine marker is absent
#   section:<Key>   a required work-type section marker is absent
#   rec:<Key>       a recommended marker (Decision or Intent) is absent
# Args: <text> [<prefix_ok>]  — prefix_ok=1 means the summary carries a valid
# PREFIX:, which satisfies engineering's Repo requirement on its own.
# Args: <text> [<prefix_ok>] [<stage>] — a pilot type (product, engineering, bug,
# data, spike) is graded by rb_pilot_missing for <stage> (default created) instead,
# which adds problem: and warning: lines.
rb_missing() {
  local text="$1" prefix_ok="${2:-0}" type
  type="$(rb_type "$text")"
  if rb_is_pilot_type "$type"; then rb_pilot_missing "$text" "${3:-created}" "$prefix_ok"; return; fi
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
  rb_present "$text" Intent || printf 'rec:%s\n' Intent
  if [ -n "$type" ]; then
    local IFS='|' ms m
    read -ra ms <<< "$(rb_section_markers "$type")"
    for m in "${ms[@]}"; do
      # A PREFIX stands in for a missing Repo, but an explicit Repo is still validated.
      [ "$m" = Repo ] && [ "$prefix_ok" = 1 ] && ! rb_marker_present "$text" Repo && continue
      # Research produces no change to the code, so there are no paths to name.
      [ "$m" = "Affected paths" ] && rb_is_research "$text" && continue
      rb_present "$text" "$m" || printf 'section:%s\n' "$m"
    done
  fi
}

# Echo the canonical verdict string for <text> [<prefix_ok>] [<stage>]. This ladder
# mirrors Scout triage exactly (ticket-rubric.md → "The verdict mapping"); a pilot
# type is graded for <stage> (default created) by rb_pilot_verdict.
rb_verdict() {
  if rb_is_pilot_type "$(rb_type "$1")"; then
    rb_pilot_verdict "$1" "${3:-created}" "${2:-0}"; return
  fi
  local miss; miss="$(rb_missing "$1" "${2:-0}")"
  if grep -qxE 'spine:(Done|Deliverable type)' <<< "$miss"; then
    echo "none: needs human direction"; return
  fi
  grep -q '^spine:'   <<< "$miss" && { echo "low: needs enrichment"; return; }
  grep -q '^section:' <<< "$miss" && { echo "medium: routable but thin"; return; }
  # SR-6176: an Intent that asks is reported as recommended-missing, and still keeps
  # an otherwise complete ticket below high.
  local intent; intent="$(rb_marker_value "$1" Intent || true)"
  if rb_value_is_real "$intent" && rb_ends_question "$intent"; then
    echo "medium: routable but thin"; return
  fi
  echo "high: actionable"
}
