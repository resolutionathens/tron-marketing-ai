#!/usr/bin/env bash
# git-pushtoprod: promote master through the repo's deploy branches, push, then
# transition the ticket to Done. The DETERMINISTIC core of tron:git-pushtoprod
# (Phase B). Works from a worktree or a regular checkout. Promotes master→staging
# (only if the repo HAS a staging branch) then master→production; production is
# required. Stops at the FIRST failed/conflicted environment (production is never
# touched if staging fails), so a partial promotion is impossible to miss.
# package*.json conflicts resolve to --ours; any other conflict aborts.
#
# Usage:
#   git-pushtoprod.sh [--no-jira] [--key <TICKET>] [--worktree <abs-path>]
#     --no-jira          skip the Jira transition (e.g. GitHub-issue work, or tests)
#     --key <KEY>        override the ticket key (default: parsed from the branch)
#     --worktree <path>  resolve the starting branch, dirty-check, and Jira key
#                        from this path instead of $PWD. The worktree-integrated
#                        shell resets $PWD to the MAIN checkout after every Bash
#                        call, so a wt caller must pass the worktree explicitly
#                        (same convention as git-dev.sh).
#
# Output: one JSON line on stdout (narration on stderr). `staging` is true/false
# when the repo has a staging branch, or "skipped" when it has none. Examples:
#   {"ok":true,"staging":true,"production":true,"jira":"MD-1801:Done","leftovers":[]}
#   {"ok":true,"staging":"skipped","production":true,"jira":"MD-1801:Done","leftovers":[]}
set -euo pipefail

log() { echo "git-pushtoprod: $*" >&2; }

NO_JIRA=0; KEY=""; WT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-jira) NO_JIRA=1 ;;
    --key) KEY="${2:-}"; shift ;;
    --worktree)
      [[ -z "${2:-}" ]] && { echo '{"ok":false,"error":"missing-worktree-value"}'; exit 2; }
      WT="$2"; shift ;;
    -*) echo "git-pushtoprod.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) echo "git-pushtoprod.sh: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done
# The worktree we start FROM: an explicit --worktree, else the current dir.
WT="${WT:-$(pwd)}"

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
LIB="${ROOT:+$ROOT/tools/git/git-promote.sh}"
[[ -z "$LIB" || ! -f "$LIB" ]] && LIB="$(cd "$(dirname "$0")/../../../tools/git" && pwd)/git-promote.sh"
# shellcheck source=/dev/null
source "$LIB"

MAIN="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  && MAIN="${MAIN%/.git}" || { echo '{"ok":false,"error":"not a git repo"}'; exit 1; }

# Branch + dirty-check are worktree-scoped — read them from $WT, never $PWD
# (which the wt-integrated shell resets to MAIN after every Bash call).
if [[ -n "$(gp_dirty "$WT")" ]]; then
  echo '{"ok":false,"error":"dirty-working-tree","staging":false,"production":false}'; exit 1
fi

IN_WT=false; gp_in_worktree "$MAIN" "$WT" && IN_WT=true
START_BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
[[ -z "$KEY" ]] && KEY="$(printf '%s' "$START_BRANCH" | grep -oE '^[A-Z]+-[0-9]+' || true)"

restore() {
  if $IN_WT; then git -C "$MAIN" checkout master >/dev/null 2>&1 || true
  else git -C "$MAIN" checkout "$START_BRANCH" >/dev/null 2>&1 || true; fi
}

# Bring master current first so staging/production receive the latest.
git -C "$MAIN" checkout master >/dev/null 2>&1 || { echo '{"ok":false,"error":"checkout-master","staging":false,"production":false}'; exit 1; }
git -C "$MAIN" pull --ff-only >/dev/null 2>&1 || git -C "$MAIN" pull >/dev/null 2>&1 || { restore; echo '{"ok":false,"error":"pull-master","staging":false,"production":false}'; exit 1; }

STAGING_OK=false; PROD_OK=false; ERR=""; CONFLICTS=""

# Promotion targets vary by repo. `staging` is OPTIONAL: a repo with only
# master+production (e.g. a Cloudflare Worker app with no staging lane) promotes
# master→production directly. `production` is REQUIRED — without it there is
# nothing to push to and the skill does not apply.
HAS_STAGING=false; gp_has_branch "$MAIN" staging && HAS_STAGING=true
# Staging JSON value, decided once up front so EVERY exit path reports it
# consistently: true/false when the repo has a staging branch, "skipped" when not.
if $HAS_STAGING; then STAGING_JSON="$STAGING_OK"; else STAGING_JSON='"skipped"'; fi
if ! gp_has_branch "$MAIN" production; then
  restore
  printf '{"ok":false,"error":"no-production-branch","staging":%s,"production":false}\n' "$STAGING_JSON"; exit 1
fi

# "staging satisfied" = it shipped OR the repo has no staging branch. Production
# is gated on it, preserving the invariant that a staging failure never lets a
# half-promoted change reach production.
STAGING_DONE=true
if $HAS_STAGING; then
  log "merging master → staging"
  RES="$(gp_merge_into "$MAIN" staging master)" || true
  case "$RES" in
    ok|ok:*) STAGING_OK=true; log "staging updated" ;;
    conflict:*) ERR="staging-conflicts"; CONFLICTS="${RES#conflict:}"; STAGING_DONE=false ;;
    *) ERR="staging-${RES#error:}"; STAGING_DONE=false ;;
  esac
else
  log "no staging branch — promoting master → production directly"
fi

if $STAGING_DONE; then
  log "merging master → production"
  RES="$(gp_merge_into "$MAIN" production master)" || true
  case "$RES" in
    ok|ok:*) PROD_OK=true; log "production updated" ;;
    conflict:*) ERR="production-conflicts"; CONFLICTS="${RES#conflict:}" ;;
    *) ERR="production-${RES#error:}" ;;
  esac
fi

# JSON value for the staging field: true/false when the repo has a staging
# branch, "skipped" when it has none (so callers can tell "n/a" from "failed").
if $HAS_STAGING; then STAGING_JSON="$STAGING_OK"; else STAGING_JSON='"skipped"'; fi

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

# Build leftovers = environments that did NOT ship. A skipped (nonexistent)
# staging branch is not a leftover — there was nothing to promote.
LEFT=""
if $HAS_STAGING && ! $STAGING_OK; then LEFT="\"staging\""; fi
$PROD_OK || LEFT="${LEFT:+$LEFT,}\"production\""

# Success = production shipped AND staging is satisfied (shipped or n/a).
OK=true; { $PROD_OK && $STAGING_DONE; } || OK=false
if $OK; then
  printf '{"ok":true,"staging":%s,"production":true,"jira":%s,"leftovers":[]}\n' "$STAGING_JSON" "$JIRA_JSON"
  exit 0
else
  CJSON=""
  if [[ -n "$CONFLICTS" ]]; then
    IFS=',' read -ra parts <<< "$CONFLICTS"
    for i in "${!parts[@]}"; do [[ $i -gt 0 ]] && CJSON+=","; CJSON+="\"${parts[$i]}\""; done
  fi
  printf '{"ok":false,"staging":%s,"production":%s,"error":"%s","conflicts":[%s],"jira":%s,"leftovers":[%s]}\n' \
    "$STAGING_JSON" "$PROD_OK" "$ERR" "$CJSON" "$JIRA_JSON" "$LEFT"
  exit 1
fi
