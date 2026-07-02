#!/usr/bin/env bash
# initiative-report: the deterministic fetch behind tron:initiative-report.
# Given a parent key (Initiative/Theme/Epic/Campaign), walks the FULL descendant
# tree breadth-first (parent = X is single-level in JQL, so each level is one
# `parent in (…)` query), pulls status fields for every descendant, and emits
# one pre-digested JSON object so the composing model reads counts + rows, not
# raw per-level JSON.
#
# Usage:
#   initiative-report.sh fetch <PARENT-KEY> [--limit 200]
#     (no subcommand defaults to `fetch`)
#
#   --limit N   per-level search page size (default 200; if any level returns
#               exactly N rows, "truncated":true is set — paginate that level)
#
# Side effect: writes the descendant detail array to
# /tmp/manager/<parent>-descendants.json for follow-up queries.
#
# Output: one JSON object on stdout — {parent, descendants, counts, truncated};
# narration on stderr. Exit 0 success / 1 logical failure (e.g. Jira auth) /
# 2 usage error.
set -euo pipefail

log() { echo "initiative-report: $*" >&2; }
usage_err() { echo "initiative-report.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

# ---- flags ------------------------------------------------------------------
CMD="${1:-}"
case "$CMD" in
  fetch) shift ;;
  ""|help|-h|--help) sed -n '2,21p' "$0"; exit 0 ;;
  *) : ;;                                # bare key/flags → implicit fetch
esac

PARENT=""; LIMIT=200
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="${2:-}"; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) [[ -n "$PARENT" ]] && usage_err "one parent key only (got '$PARENT' and '$1')"; PARENT="$1" ;;
  esac
  shift
done

[[ -n "$PARENT" ]] || usage_err "fetch requires a parent key (e.g. MCR-355)"
[[ "$PARENT" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || usage_err "parent must be a Jira key like MCR-355 (got '$PARENT')"
[[ "$LIMIT" =~ ^[0-9]+$ && "$LIMIT" -ge 1 ]] || usage_err "--limit must be a positive integer (got '$LIMIT')"

command -v acli >/dev/null 2>&1 || { log "acli not found — install the Atlassian CLI and run: acli jira auth"; exit 1; }

mkdir -p /tmp/manager

# csv() squeezes runs of spaces/newlines into single commas and trims the ends,
# so jq's newline-separated key output becomes a valid JQL list (no leading or
# empty element).
csv() { tr -s ' \n' ',' | sed 's/^,//;s/,$//'; }

# ---- 1. the parent itself -----------------------------------------------------
if ! PARENT_JSON="$(acli jira workitem view "$PARENT" --json 2>/dev/null)"; then
  log "could not view $PARENT — check the key and auth (acli jira auth)"
  exit 1
fi

# ---- 2. BFS every level of descendants ----------------------------------------
# `parent = X` is single-level, so walk the frontier until no new children.
frontier="$PARENT"; all=""; TRUNCATED=false; level=0
while [ -n "$frontier" ]; do
  level=$((level + 1))
  list="$(printf '%s' "$frontier" | csv)"
  KIDS_JSON="$(acli jira workitem search --jql "parent in ($list)" --limit "$LIMIT" --json 2>/dev/null)" || {
    log "search failed at level $level — check auth with: acli jira auth"; exit 1; }
  [[ -n "$KIDS_JSON" ]] || KIDS_JSON="[]"
  kids="$(jq -r '.[].key' <<<"$KIDS_JSON")"
  n="$(jq 'length' <<<"$KIDS_JSON")"
  [[ "$n" -ge "$LIMIT" ]] && { TRUNCATED=true; log "level $level returned $n rows (== --limit $LIMIT) — may be truncated, paginate"; }
  [ -z "$kids" ] && break
  all="$all $kids"; frontier="$kids"
  log "level $level: $n children"
done

# ---- 3. statuses for the FULL descendant set ----------------------------------
if [ -n "${all// /}" ]; then
  keys="$(printf '%s' "$all" | csv)"
  DETAIL="$(acli jira workitem search --jql "key in ($keys)" \
    --fields key,summary,status,assignee,duedate,updated --limit 1000 --json 2>/dev/null)" || {
    log "detail search failed — check auth with: acli jira auth"; exit 1; }
  [[ -n "$DETAIL" ]] || DETAIL="[]"
else
  DETAIL="[]"
fi
printf '%s\n' "$DETAIL" > "/tmp/manager/${PARENT}-descendants.json"

# ---- 4. digest ------------------------------------------------------------------
jq -n \
  --argjson parent "$PARENT_JSON" \
  --argjson detail "$DETAIL" \
  --argjson truncated "$TRUNCATED" '
  def brief: {
    key,
    summary: .fields.summary,
    status: (.fields.status.name // null),
    assignee: (.fields.assignee.displayName // null),
    duedate: (.fields.duedate // null),
    updated: ((.fields.updated // "") | .[0:10] | if . == "" then null else . end)
  };
  def isdone: ((.status // "") | ascii_downcase) as $s | ($s=="done" or $s=="closed" or $s=="resolved");

  ($detail | map(brief)) as $d |
  {
    parent: ($parent | {key, summary: .fields.summary, status: (.fields.status.name // null), type: (.fields.issuetype.name // null)}),
    truncated: $truncated,
    counts: {
      total: ($d | length),
      done: ($d | map(select(isdone)) | length),
      in_progress: ($d | map(select(.status == "In Progress")) | length),
      to_do: ($d | map(select((isdone or .status == "In Progress") | not)) | length)
    },
    descendants: $d
  }'

log "parent=$PARENT descendants=$(jq 'length' <<<"$DETAIL") truncated=$TRUNCATED"
