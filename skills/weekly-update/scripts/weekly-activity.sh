#!/usr/bin/env bash
# weekly-activity: the deterministic fetch behind tron:weekly-update. Computes
# the report window, pulls the user's Jira activity via acli, and — only if
# GitHub is actually available — their authored PRs via gh. Emits compact,
# pre-digested buckets so the composing model reads labelled text, not raw JSON.
#
# GitHub is OPTIONAL by design: many people on the team have Jira but no git /
# gh. If gh is missing, unauthenticated, or --no-github is passed, the PR
# buckets are skipped (with the reason stated) and the report is built from
# Jira alone. acli is the only hard dependency.
#
# Usage:
#   weekly-activity.sh fetch [--weeks N] [--start YYYY-MM-DD]
#                            [--owner ORG] [--no-github]
#     (no subcommand defaults to `fetch`)
#
#   --weeks N        look back N whole weeks to the Monday start (default 1;
#                    use 2 for a biweekly / "past two weeks" report)
#   --start DATE     override the computed window start (YYYY-MM-DD)
#   --owner ORG      GitHub org to search PRs in (default: Facilitron)
#   --no-github      skip the GitHub pull even if gh is available
#
# Output: compact structured text on stdout (the data the model composes from);
# narration on stderr. Exit 0 success / 1 logical failure (e.g. Jira auth) /
# 2 usage error.
set -euo pipefail

log() { echo "weekly-activity: $*" >&2; }
usage_err() { echo "weekly-activity.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"
command -v python3 >/dev/null 2>&1 || usage_err "python3 is required but not on PATH"

# ---- flags ------------------------------------------------------------------
CMD="${1:-fetch}"
case "$CMD" in
  fetch) shift ;;
  ""|help|-h|--help) sed -n '2,26p' "$0"; exit 0 ;;
  -*) CMD=fetch ;;                       # bare flags → implicit fetch
  *) usage_err "unknown subcommand '$CMD' (try: fetch, help)" ;;
esac

WEEKS=1; START=""; OWNER="Facilitron"; NO_GITHUB=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --weeks) WEEKS="${2:-}"; shift ;;
    --start) START="${2:-}"; shift ;;
    --owner) OWNER="${2:-}"; shift ;;
    --no-github) NO_GITHUB=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) usage_err "unknown flag '$1'" ;;
  esac
  shift
done

[[ "$WEEKS" =~ ^[0-9]+$ && "$WEEKS" -ge 1 ]] || usage_err "--weeks must be a positive integer (got '$WEEKS')"
if [[ -n "$START" ]]; then
  [[ "$START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage_err "--start must be YYYY-MM-DD (got '$START')"
fi

# ---- window -----------------------------------------------------------------
# Default start = the Monday WEEKS weeks before this week's Monday (BSD `date`
# weekday math is painful, so use python3).
if [[ -z "$START" ]]; then
  START="$(python3 -c "
from datetime import date, timedelta
import sys
weeks = int(sys.argv[1])
today = date.today()
this_mon = today - timedelta(days=today.weekday())
print((this_mon - timedelta(days=7 * weeks)).isoformat())
" "$WEEKS")"
fi

# ---- Jira (required) --------------------------------------------------------
command -v acli >/dev/null 2>&1 || { log "acli not found — install the Atlassian CLI and run: acli jira auth"; exit 1; }

jira_search() { # jql → JSON array on stdout, or nonzero on failure
  acli jira workitem search --jql "$1" --json 2>/dev/null
}

UPDATED_JQL="assignee = currentUser() AND updated >= '$START' ORDER BY updated DESC"
DONE_JQL="assignee = currentUser() AND status changed TO ('Done','Closed','Resolved') DURING ('$START', now()) ORDER BY updated DESC"

if ! JIRA_UPDATED="$(jira_search "$UPDATED_JQL")"; then
  log "Jira query failed — check auth with: acli jira auth"
  exit 1
fi
JIRA_DONE="$(jira_search "$DONE_JQL")" || JIRA_DONE="[]"
[[ -n "$JIRA_UPDATED" ]] || JIRA_UPDATED="[]"
[[ -n "$JIRA_DONE" ]] || JIRA_DONE="[]"

# jq filters (shared)
DONE_FMT='.[] | "- \(.key) — \(.fields.summary) [\(.fields.status.name)\((.fields.labels // []) | if length>0 then "; "+join(",") else "" end)]"'
FLIGHT_FMT='.[]
  | select((.fields.status.name|ascii_downcase) as $s | ($s=="done" or $s=="closed" or $s=="resolved") | not)
  | "- \(.key) — \(.fields.summary) [\(.fields.status.name)\((.fields.labels // []) | if length>0 then "; "+join(",") else "" end)\(if .fields.parent then "; epic: "+.fields.parent.key else "" end)]"'

DONE_OUT="$(jq -r "$DONE_FMT" <<<"$JIRA_DONE")"
FLIGHT_OUT="$(jq -r "$FLIGHT_FMT" <<<"$JIRA_UPDATED")"

# ---- GitHub (optional) ------------------------------------------------------
GH_NOTE=""; PRS_MERGED_OUT=""; PRS_OPEN_OUT=""
PR_FMT='.[] | "- \(.title) — \(.repository.name) (\(.url))"'

gh_available() {
  [[ "$NO_GITHUB" -eq 1 ]] && { GH_NOTE="skipped — --no-github"; return 1; }
  command -v gh >/dev/null 2>&1 || { GH_NOTE="skipped — gh not installed (Jira-only mode)"; return 1; }
  gh auth status >/dev/null 2>&1 || { GH_NOTE="skipped — gh not authenticated (run: gh auth login)"; return 1; }
  GH_NOTE="included"; return 0
}

if gh_available; then
  MERGED="$(gh search prs --author=@me --owner="$OWNER" --merged --merged-at=">=$START" --limit 50 \
              --json title,repository,url 2>/dev/null || echo '[]')"
  OPEN="$(gh search prs --author=@me --owner="$OWNER" --state open --limit 50 \
              --json title,repository,url 2>/dev/null || echo '[]')"
  [[ -n "$MERGED" ]] || MERGED="[]"; [[ -n "$OPEN" ]] || OPEN="[]"
  PRS_MERGED_OUT="$(jq -r "$PR_FMT" <<<"$MERGED")"
  PRS_OPEN_OUT="$(jq -r "$PR_FMT" <<<"$OPEN")"
fi

# ---- emit -------------------------------------------------------------------
section() { # title  body  empty-fallback
  printf '%s\n' "$1"
  if [[ -n "$2" ]]; then printf '%s\n' "$2"; else printf '%s\n' "$3"; fi
  printf '\n'
}

printf 'WINDOW_START=%s  (%s week%s)\n' "$START" "$WEEKS" "$([[ "$WEEKS" -eq 1 ]] || echo s)"
printf 'GITHUB: %s\n\n' "$GH_NOTE"

section "DONE (transitioned to done in window):" "$DONE_OUT" "(none)"
section "IN FLIGHT (In Progress / To Do, updated in window):" "$FLIGHT_OUT" "(none)"

if [[ "$GH_NOTE" == "included" ]]; then
  section "PRS MERGED in window:" "$PRS_MERGED_OUT" "(none)"
  section "PRS OPEN:" "$PRS_OPEN_OUT" "(none)"
else
  section "PRS MERGED in window:" "" "(github $GH_NOTE)"
  section "PRS OPEN:" "" "(github $GH_NOTE)"
fi

log "window=$START weeks=$WEEKS github=$GH_NOTE"
