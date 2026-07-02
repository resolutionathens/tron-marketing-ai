#!/usr/bin/env bash
# board-triage: the deterministic fetch behind tron:board-triage. Pulls the
# board's non-Done items via acli, enriches each key with `view` (search can't
# return updated/duedate/parent — acli rejects those --fields), and emits
# pre-digested JSON buckets so the triaging model reads structured lenses, not
# raw per-ticket JSON.
#
# Buckets (one JSON object on stdout):
#   unassigned        To Do / In Progress with no assignee
#   stale             In Progress not updated in --stale-days, or To Do overdue
#   missing_metadata  no priority, no due date, or no parent (orphaned)
#   blocked           labelled/flagged blocked, or due within 7 days
#   wip_load          per-assignee In Progress counts
#
# Usage:
#   board-triage.sh fetch [--project MCR] [--limit 500] [--stale-days 14]
#                         [--now YYYY-MM-DD]
#     (no subcommand defaults to `fetch`)
#
#   --project KEY    board/project to triage (default MCR)
#   --limit N        search page size (default 500 — MCR has >200 non-Done
#                    items and a low limit silently truncates; if the result
#                    count hits the limit, "truncated":true is set — paginate)
#   --stale-days N   In Progress staleness threshold in days (default 14)
#   --now DATE       override "today" for stale/overdue math (tests)
#
# Side effect: writes the candidate keys and the raw enriched array to
# /tmp/manager/ (triage-keys.txt, triage-enriched.json) for follow-up queries.
#
# Output: one JSON object on stdout; narration on stderr. Exit 0 success /
# 1 logical failure (e.g. Jira auth) / 2 usage error.
set -euo pipefail

log() { echo "board-triage: $*" >&2; }
usage_err() { echo "board-triage.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"

# ---- flags ------------------------------------------------------------------
CMD="${1:-fetch}"
case "$CMD" in
  fetch) shift ;;
  ""|help|-h|--help) sed -n '2,31p' "$0"; exit 0 ;;
  -*) CMD=fetch ;;                       # bare flags → implicit fetch
  *) usage_err "unknown subcommand '$CMD' (try: fetch, help)" ;;
esac

PROJECT="MCR"; LIMIT=500; STALE_DAYS=14; NOW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift ;;
    --limit) LIMIT="${2:-}"; shift ;;
    --stale-days) STALE_DAYS="${2:-}"; shift ;;
    --now) NOW="${2:-}"; shift ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) usage_err "unknown flag '$1'" ;;
  esac
  shift
done

[[ "$PROJECT" =~ ^[A-Z][A-Z0-9]+$ ]] || usage_err "--project must be a Jira project key (got '$PROJECT')"
[[ "$LIMIT" =~ ^[0-9]+$ && "$LIMIT" -ge 1 ]] || usage_err "--limit must be a positive integer (got '$LIMIT')"
[[ "$STALE_DAYS" =~ ^[0-9]+$ && "$STALE_DAYS" -ge 1 ]] || usage_err "--stale-days must be a positive integer (got '$STALE_DAYS')"
if [[ -n "$NOW" ]]; then
  [[ "$NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage_err "--now must be YYYY-MM-DD (got '$NOW')"
else
  NOW="$(date +%Y-%m-%d)"
fi

command -v acli >/dev/null 2>&1 || { log "acli not found — install the Atlassian CLI and run: acli jira auth"; exit 1; }

mkdir -p /tmp/manager

# ---- 1. candidate set (keys only — search's field set is fixed) -------------
JQL="project = $PROJECT AND statusCategory != Done ORDER BY updated ASC"
if ! SEARCH="$(acli jira workitem search --jql "$JQL" --limit "$LIMIT" --json 2>/dev/null)"; then
  log "Jira query failed — check auth with: acli jira auth"
  exit 1
fi
[[ -n "$SEARCH" ]] || SEARCH="[]"

jq -r '.[].key' <<<"$SEARCH" > /tmp/manager/triage-keys.txt
COUNT="$(jq 'length' <<<"$SEARCH")"
TRUNCATED=false
[[ "$COUNT" -ge "$LIMIT" ]] && { TRUNCATED=true; log "result count hit --limit $LIMIT — board may be larger, paginate"; }
log "candidates: $COUNT non-Done items on $PROJECT"

# ---- 2. enrich: updated/duedate/parent only exist on the full item view -----
ENRICHED="$(
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    acli jira workitem view "$k" --fields '*all' --json 2>/dev/null || true
  done < /tmp/manager/triage-keys.txt | jq -s '.'
)"
printf '%s\n' "$ENRICHED" > /tmp/manager/triage-enriched.json

# ---- 3. digest into buckets ---------------------------------------------------
STALE_CUTOFF="$(jq -rn --arg now "$NOW" --argjson d "$STALE_DAYS" \
  '($now+"T00:00:00Z") | fromdate - ($d*86400) | todate | .[0:10]')"
DUE_SOON="$(jq -rn --arg now "$NOW" \
  '($now+"T00:00:00Z") | fromdate + (7*86400) | todate | .[0:10]')"

jq -n \
  --arg project "$PROJECT" \
  --arg now "$NOW" \
  --arg stale_cutoff "$STALE_CUTOFF" \
  --arg due_soon "$DUE_SOON" \
  --argjson stale_days "$STALE_DAYS" \
  --argjson truncated "$TRUNCATED" \
  --argjson items "$ENRICHED" '
  def brief: {
    key,
    summary: .fields.summary,
    type: (.fields.issuetype.name // null),
    status: (.fields.status.name // null),
    assignee: (.fields.assignee.displayName // null),
    priority: (.fields.priority.name // null),
    duedate: (.fields.duedate // null),
    updated: ((.fields.updated // "") | .[0:10] | if . == "" then null else . end),
    parent: (.fields.parent.key // null),
    parent_summary: (.fields.parent.fields.summary // null),
    labels: (.fields.labels // [])
  };
  def actionable: (.status // "") as $s | ($s == "To Do" or $s == "In Progress");

  ($items | map(brief)) as $b |
  {
    project: $project,
    now: $now,
    stale_days: $stale_days,
    total: ($b | length),
    truncated: $truncated,
    unassigned: [ $b[] | select(actionable and .assignee == null) ],
    stale: [ $b[] | select(
      (.status == "In Progress" and .updated != null and .updated < $stale_cutoff)
      or (.status == "To Do" and .duedate != null and .duedate < $now)
    ) ],
    missing_metadata: [ $b[] | select(actionable and
      (.priority == null or .priority == "None" or .duedate == null or .parent == null)) ],
    blocked: [ $b[] | select(actionable and (
      ((.labels | map(ascii_downcase) | any(test("block")))
       or (.duedate != null and .duedate <= $due_soon))
    )) ],
    wip_load: ($b | map(select(.status == "In Progress"))
      | group_by(.assignee)
      | map({assignee: (.[0].assignee // "(unassigned)"), in_progress: length, keys: map(.key)})
      | sort_by(-.in_progress))
  }'

log "project=$PROJECT now=$NOW stale_days=$STALE_DAYS items=$COUNT truncated=$TRUNCATED"
