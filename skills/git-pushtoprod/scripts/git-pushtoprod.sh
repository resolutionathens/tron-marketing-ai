#!/usr/bin/env bash
# git-pushtoprod: merge master into `staging` and `production`, push both, then
# transition the ticket to Done. The DETERMINISTIC core of tron:git-pushtoprod
# (Phase B). Works from a worktree or a regular checkout. Stops at the FIRST
# failed/conflicted environment and reports which ones made it (master→staging
# is attempted before master→production; production is never touched if staging
# fails). package*.json conflicts resolve to --ours; any other conflict aborts.
#
# Usage:
#   git-pushtoprod.sh [--no-jira] [--key <TICKET>]
#     --no-jira     skip the Jira transition (e.g. GitHub-issue work, or tests)
#     --key <KEY>   override the ticket key (default: parsed from the branch)
#
# Output: one JSON line on stdout (narration on stderr). Example:
#   {"ok":true,"staging":true,"production":true,"jira":"MD-1801:Done","leftovers":[]}
set -euo pipefail

log() { echo "git-pushtoprod: $*" >&2; }

NO_JIRA=0; KEY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-jira) NO_JIRA=1 ;;
    --key) KEY="${2:-}"; shift ;;
    -*) echo "git-pushtoprod.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) echo "git-pushtoprod.sh: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
LIB="${ROOT:+$ROOT/tools/git/git-promote.sh}"
[[ -z "$LIB" || ! -f "$LIB" ]] && LIB="$(cd "$(dirname "$0")/../../../tools/git" && pwd)/git-promote.sh"
# shellcheck source=/dev/null
source "$LIB"

MAIN="$(gp_main_repo)" || { echo '{"ok":false,"error":"not a git repo"}'; exit 1; }

if [[ -n "$(gp_dirty "$(pwd)")" ]]; then
  echo '{"ok":false,"error":"dirty-working-tree","staging":false,"production":false}'; exit 1
fi

IN_WT=false; gp_in_worktree "$MAIN" && IN_WT=true
START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ -z "$KEY" ]] && KEY="$(printf '%s' "$START_BRANCH" | grep -oE '^[A-Z]+-[0-9]+' || true)"

restore() {
  if $IN_WT; then git -C "$MAIN" checkout master >/dev/null 2>&1 || true
  else git -C "$MAIN" checkout "$START_BRANCH" >/dev/null 2>&1 || true; fi
}

# Bring master current first so staging/production receive the latest.
git -C "$MAIN" checkout master >/dev/null 2>&1 || { echo '{"ok":false,"error":"checkout-master","staging":false,"production":false}'; exit 1; }
git -C "$MAIN" pull --ff-only >/dev/null 2>&1 || git -C "$MAIN" pull >/dev/null 2>&1 || { restore; echo '{"ok":false,"error":"pull-master","staging":false,"production":false}'; exit 1; }

STAGING_OK=false; PROD_OK=false; ERR=""; CONFLICTS=""

log "merging master → staging"
RES="$(gp_merge_into "$MAIN" staging master)" || true
case "$RES" in
  ok|ok:*) STAGING_OK=true; log "staging updated" ;;
  conflict:*) ERR="staging-conflicts"; CONFLICTS="${RES#conflict:}" ;;
  *) ERR="staging-${RES#error:}" ;;
esac

if $STAGING_OK; then
  log "merging master → production"
  RES="$(gp_merge_into "$MAIN" production master)" || true
  case "$RES" in
    ok|ok:*) PROD_OK=true; log "production updated" ;;
    conflict:*) ERR="production-conflicts"; CONFLICTS="${RES#conflict:}" ;;
    *) ERR="production-${RES#error:}" ;;
  esac
fi

restore

# Jira transition only when both environments shipped (best-effort, non-fatal).
# The result always reports a verdict for the key so callers never have to guess
# whether the transition was attempted: Done / transition-failed / skipped.
JIRA_JSON='null'
if [[ -n "$KEY" ]]; then
  if [[ "$NO_JIRA" -eq 1 ]] || ! $PROD_OK || ! command -v acli >/dev/null 2>&1; then
    JIRA_JSON="\"$KEY:skipped\""
  elif acli jira workitem transition --key "$KEY" --status 'Done' --yes >/dev/null 2>&1; then
    JIRA_JSON="\"$KEY:Done\""; log "Jira $KEY → Done"
  else
    JIRA_JSON="\"$KEY:transition-failed\""; log "Jira transition failed for $KEY (non-blocking)"
  fi
fi

# Build leftovers = environments that did NOT ship.
LEFT=""
$STAGING_OK || LEFT="\"staging\""
$PROD_OK || LEFT="${LEFT:+$LEFT,}\"production\""

OK=true; { $STAGING_OK && $PROD_OK; } || OK=false
if $OK; then
  printf '{"ok":true,"staging":true,"production":true,"jira":%s,"leftovers":[]}\n' "$JIRA_JSON"
  exit 0
else
  CJSON=""
  if [[ -n "$CONFLICTS" ]]; then
    IFS=',' read -ra parts <<< "$CONFLICTS"
    for i in "${!parts[@]}"; do [[ $i -gt 0 ]] && CJSON+=","; CJSON+="\"${parts[$i]}\""; done
  fi
  printf '{"ok":false,"staging":%s,"production":%s,"error":"%s","conflicts":[%s],"jira":%s,"leftovers":[%s]}\n' \
    "$STAGING_OK" "$PROD_OK" "$ERR" "$CJSON" "$JIRA_JSON" "$LEFT"
  exit 1
fi
