#!/usr/bin/env bash
# jira-link.sh — create, delete, and replace Jira dependency links from a plain
# statement, and verify what Jira actually stored (MD-3397).
#
#   bash jira-link.sh create  "MD-3396 blocks MD-3268"
#   bash jira-link.sh delete  <link-id> "MD-3268 is blocked by MD-3396"
#   bash jira-link.sh replace <link-id> "MD-3396 blocks MD-3268"
#   bash jira-link.sh show    MD-3268
#
# Statements: "<A> blocks <B>", "<A> is blocked by <B>", "<A> relates to <B>".
#
# Why a helper: `acli jira workitem link create --out A --in B --type Blocks`
# stores "B blocks A" (A is blocked by B), and then prints "(A Blocks B)". Its
# help calls --out the "outward work item", so an agent reading either one
# believes it made the reverse of what Jira holds. Verified live Nov 13 2026:
# --out MD-3397 --in MD-3082 printed "MD-3397 Blocks MD-3082" and stored
# "MD-3397 is blocked by MD-3082". This helper owns that mapping, so no agent
# has to reason about --out/--in.
#
# Readback: `acli jira workitem view <A> --fields issuelinks --json`. On issue
# A, an entry with outwardIssue X reads "A <type.outward> X" and one with
# inwardIssue X reads "A <type.inward> X" (same words the changelog shows:
# "This work item is blocked by X"). `acli ... link list --json` is not used:
# it omits the other issue's key, so it cannot tell two Blocks links apart.
#
# Delete and replace take a link id AND the issues it must connect. The helper
# refuses unless that id is the named link, so a correction cannot remove an
# unrelated link on the same issue (MD-3268 lost "is blocked by MD-3262" to a
# link id picked off an ambiguous list).
#
# Exit codes: 0 ok · 1 Jira/acli error or readback mismatch · 2 usage
#             3 stored direction reversed · 4 refused (id is not the named link)
set -uo pipefail

KEY_RE='[A-Za-z][A-Za-z0-9]*-[0-9]+'

die()   { echo "jira-link: $*" >&2; exit 1; }
usage() { echo "jira-link: $*" >&2; sed -n '5,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq is required"

# parse_statement "<A> <verb> <B>" → sets ST_A ST_B ST_VERB ST_TYPE ST_REVERSE
parse_statement() {
  local s verb
  s="$(printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//')"
  if ! printf '%s\n' "$s" | grep -Eiq "^$KEY_RE (blocks|is blocked by|relates to) $KEY_RE\$"; then
    usage "cannot read statement '$1' (want '<A> blocks <B>', '<A> is blocked by <B>' or '<A> relates to <B>')"
  fi
  ST_A="$(printf '%s' "$s" | awk '{print toupper($1)}')"
  ST_B="$(printf '%s' "$s" | awk '{print toupper($NF)}')"
  verb="$(printf '%s' "$s" | awk '{ $1=""; $NF=""; print tolower($0) }' | sed -E 's/^ +//; s/ +$//')"
  [ "$ST_A" != "$ST_B" ] || usage "a link needs two different issues (got $ST_A twice)"
  ST_VERB="$verb"
  case "$verb" in
    blocks)          ST_TYPE=Blocks;  ST_REVERSE="is blocked by" ;;
    "is blocked by") ST_TYPE=Blocks;  ST_REVERSE="blocks" ;;
    "relates to")    ST_TYPE=Relates; ST_REVERSE="relates to" ;;
  esac
}

# acli outward/inward for the statement. acli stores --out X --in Y --type
# Blocks as "Y blocks X", so "A blocks B" needs --out B --in A.
acli_out() { if [ "$ST_VERB" = blocks ]; then echo "$ST_B"; else echo "$ST_A"; fi; }
acli_in()  { if [ "$ST_VERB" = blocks ]; then echo "$ST_A"; else echo "$ST_B"; fi; }

# not_in <ids> : stdin rows whose id is not in the newline list <ids>
not_in() {
  local row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    printf '%s\n' "$1" | grep -qxF "${row%%$'\t'*}" || printf '%s\n' "$row"
  done
}

# links_of <KEY> → TSV lines: id, type name, phrase as read from KEY, other key
links_of() {
  local json
  json="$(acli jira workitem view "$1" --fields issuelinks --json 2>&1)" \
    || die "could not read links of $1: $json"
  printf '%s' "$json" | jq -r '
    (.fields.issuelinks // [])[]
    | if .outwardIssue then [.id, .type.name, (.type.outward | ascii_downcase), .outwardIssue.key]
      else [.id, .type.name, (.type.inward | ascii_downcase), .inwardIssue.key] end
    | @tsv' 2>/dev/null || die "unexpected issuelinks JSON for $1"
}

link_row() { printf '%s\n' "$2" | awk -F'\t' -v id="$1" '$1 == id'; }
say_row()  { printf '%s' "$2" | awk -F'\t' -v k="$1" '{ printf "%s %s %s (link %s, %s)", k, $3, $4, $1, $2 }'; }

cmd_show() {
  [ $# -eq 1 ] || usage "show takes one issue key"
  local key rows
  key="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  rows="$(links_of "$key")" || exit 1
  [ -n "$rows" ] || { echo "$key has no links"; return 0; }
  printf '%s\n' "$rows" | awk -F'\t' -v k="$key" '{ printf "%s\t%s %s %s\t(%s)\n", $1, k, $3, $4, $2 }'
}

# create_verified: assumes ST_* set. Creates, reads back, judges direction.
create_verified() {
  local before after out rc new match rev
  before="$(links_of "$ST_A")" || exit 1
  out="$(acli jira workitem link create --out "$(acli_out)" --in "$(acli_in)" --type "$ST_TYPE" --yes 2>&1)"; rc=$?
  after="$(links_of "$ST_A")" || exit 1

  new="$(printf '%s\n' "$after" | not_in "$(printf '%s\n' "$before" | cut -f1)" \
    | awk -F'\t' -v t="$ST_TYPE" -v o="$ST_B" '$2 == t && $4 == o')"
  match="$(printf '%s\n' "$new" | awk -F'\t' -v v="$ST_VERB" '$3 == v' | head -1)"
  rev="$(printf '%s\n' "$new" | awk -F'\t' -v v="$ST_REVERSE" '$3 == v' | head -1)"

  if [ -n "$match" ]; then
    echo "OK: $(say_row "$ST_A" "$match") — verified on Jira"
    return 0
  fi
  if [ -n "$rev" ]; then
    echo "jira-link: REVERSED: asked for \"$ST_A $ST_VERB $ST_B\" but Jira stored \"$(say_row "$ST_A" "$rev")\"." >&2
    echo "jira-link: remove it with: jira-link.sh delete $(printf '%s' "$rev" | cut -f1) \"$ST_A $ST_REVERSE $ST_B\"" >&2
    exit 3
  fi
  match="$(printf '%s\n' "$after" | awk -F'\t' -v t="$ST_TYPE" -v o="$ST_B" -v v="$ST_VERB" '$2 == t && $4 == o && $3 == v' | head -1)"
  if [ -n "$match" ]; then
    echo "OK: already present: $(say_row "$ST_A" "$match")"
    return 0
  fi
  [ "$rc" -eq 0 ] || die "acli link create failed for \"$ST_A $ST_VERB $ST_B\": $out"
  die "acli reported success but Jira shows no new $ST_TYPE link between $ST_A and $ST_B (acli said: $out)"
}

# delete_verified <id> <rows-of-ST_A>: deletes one id, checks nothing else went.
delete_verified() {
  local id="$1" before="$2" after out missing
  out="$(acli jira workitem link delete --id "$id" --yes 2>&1)" || die "acli link delete $id failed: $out"
  after="$(links_of "$ST_A")" || exit 1
  if [ -n "$(link_row "$id" "$after")" ]; then die "link $id is still on $ST_A after delete"; fi
  missing="$(printf '%s\n' "$before" | not_in "$(printf '%s\n' "$after" | cut -f1)" \
    | awk -F'\t' -v id="$id" '$1 != id { print $1 }')"
  [ -z "$missing" ] || die "deleting $id also removed other link(s) from $ST_A: $(printf '%s' "$missing" | tr '\n' ' ')"
  echo "OK: deleted link $id; other links on $ST_A unchanged"
}

need_id() { printf '%s' "$1" | grep -Eq '^[0-9]+$' || usage "link id must be numeric (got '$1'); find it with: jira-link.sh show <KEY>"; }

refuse() {
  echo "jira-link: REFUSED: $1" >&2
  echo "jira-link: links on $ST_A:" >&2
  printf '%s\n' "$2" | awk -F'\t' -v k="$ST_A" 'NF { printf "  %s\t%s %s %s\t(%s)\n", $1, k, $3, $4, $2 }' >&2
  exit 4
}

cmd_delete() {
  [ $# -ge 2 ] || usage "delete takes <link-id> \"<statement as Jira stores it>\""
  local id="$1" rows row; shift
  need_id "$id"; parse_statement "$*"
  rows="$(links_of "$ST_A")" || exit 1
  row="$(link_row "$id" "$rows")"
  [ -n "$row" ] || refuse "link $id is not on $ST_A" "$rows"
  [ "$(printf '%s' "$row" | cut -f4)" = "$ST_B" ] && [ "$(printf '%s' "$row" | cut -f2)" = "$ST_TYPE" ] \
    && [ "$(printf '%s' "$row" | cut -f3)" = "$ST_VERB" ] \
    || refuse "link $id is \"$(say_row "$ST_A" "$row")\", not \"$ST_A $ST_VERB $ST_B\"" "$rows"
  delete_verified "$id" "$rows"
}

cmd_replace() {
  [ $# -ge 2 ] || usage "replace takes <link-id> \"<intended statement>\""
  local id="$1" rows row; shift
  need_id "$id"; parse_statement "$*"
  rows="$(links_of "$ST_A")" || exit 1
  row="$(link_row "$id" "$rows")"
  [ -n "$row" ] || refuse "link $id is not on $ST_A" "$rows"
  [ "$(printf '%s' "$row" | cut -f4)" = "$ST_B" ] \
    || refuse "link $id is \"$(say_row "$ST_A" "$row")\", which does not connect $ST_A and $ST_B" "$rows"
  echo "replacing: $(say_row "$ST_A" "$row")"
  delete_verified "$id" "$rows"
  create_verified
}

sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  create)  [ $# -ge 1 ] || usage "create takes \"<statement>\""; parse_statement "$*"; create_verified ;;
  delete)  cmd_delete "$@" ;;
  replace) cmd_replace "$@" ;;
  show)    cmd_show "$@" ;;
  *)       usage "unknown subcommand '${sub}'" ;;
esac
