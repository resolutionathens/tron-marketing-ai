#!/usr/bin/env bash
# start-ticket: the DETERMINISTIC spine of tron:start-ticket (Phase B) — classify
# the ref, create the branch+worktree with wt, carry over gitignored env files,
# and transition/assign the ticket. Emits a machine-readable result line. The
# JUDGMENT steps stay in the SKILL.md: reading the ticket, wording the slug, and
# the tmux-session / dev-server / worker-spawn offers.
#
# Usage:
#   start-ticket.sh <ref> (--branch <name> | --summary <text>) [--no-transition] [--base <branch>]
#     <ref>            MD-1234 | owner/repo#42 | #42 | a Jira/GitHub URL
#     --branch <name>  use this exact branch name (agent already decided the slug)
#     --summary <text> build the branch as <KEY>-<slug> / issue-<N>-<slug>
#     --no-transition  create the worktree but don't touch Jira/GitHub state
#     --base <branch>  base the new branch on this (default: wt's default branch)
#
# Output: one JSON line on stdout (narration on stderr), e.g.
#   {"ok":true,"refType":"jira","key":"MD-1801","branch":"MD-1801-x",
#    "worktreePath":"/…","envCopied":[".env.local"],"transitioned":true}
set -euo pipefail

log() { echo "start-ticket: $*" >&2; }

REF=""; BRANCH=""; SUMMARY=""; NO_TRANSITION=0; BASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift ;;
    --summary) SUMMARY="${2:-}"; shift ;;
    --no-transition) NO_TRANSITION=1 ;;
    --base) BASE="${2:-}"; shift ;;
    -*) echo "start-ticket.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) if [[ -z "$REF" ]]; then REF="$1"; else echo "start-ticket.sh: unexpected arg '$1'" >&2; exit 2; fi ;;
  esac
  shift
done
[[ -z "$REF" ]] && { echo "usage: start-ticket.sh <ref> (--branch <name>|--summary <text>) [--no-transition]" >&2; exit 2; }

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
LIB="${ROOT:+$ROOT/tools/ticket/ticket-lib.sh}"
[[ -z "$LIB" || ! -f "$LIB" ]] && LIB="$(cd "$(dirname "$0")/../../../tools/ticket" && pwd)/ticket-lib.sh"
# shellcheck source=/dev/null
source "$LIB"

# ---- classify the ref -------------------------------------------------------
if ! DET="$(tl_detect_ref "$REF")"; then
  echo "{\"ok\":false,\"error\":\"ambiguous-ref\",\"ref\":\"$REF\",\"hint\":\"use #N for a GitHub issue or PROJ-N for Jira\"}"
  exit 1
fi
read -r RTYPE RID RREPO <<< "$DET"   # RREPO may be empty (current-repo GH issue)

# ---- resolve the branch name ------------------------------------------------
if [[ -z "$BRANCH" ]]; then
  [[ -z "$SUMMARY" ]] && { echo "{\"ok\":false,\"error\":\"need-branch-or-summary\",\"refType\":\"$RTYPE\"}"; exit 1; }
  BRANCH="$(tl_branch_name "$RTYPE" "$RID" "$SUMMARY")"
fi
log "ref=$REF → $RTYPE $RID ${RREPO:-(current repo)} → branch $BRANCH"

# ---- freshen the base so the new branch starts from origin's latest ---------
# `wt switch -c` bases the new branch on the LOCAL default branch and does NOT
# fetch first, so a main checkout that's behind origin makes the worker start on
# a stale base. Fast-forward the local default to origin/<default> before wt
# branches off it. Best-effort / non-fatal: an offline or diverged checkout falls
# back to the current local base. Skipped when the caller pinned an explicit --base.
BASE_FRESHENED=false
if [[ -z "$BASE" ]]; then
  MAIN_NOW="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || true
  if [[ -n "$MAIN_NOW" ]]; then
    if DEFBR="$(tl_freshen_default "$MAIN_NOW")"; then
      BASE_FRESHENED=true; log "base $DEFBR fast-forwarded to origin/$DEFBR"
    else
      log "could not freshen base ${DEFBR:-default} — branching off the local default (may be stale)"
    fi
  fi
fi

# ---- create the worktree with wt -------------------------------------------
if ! command -v wt >/dev/null 2>&1; then
  echo "{\"ok\":false,\"error\":\"wt-not-found\",\"refType\":\"$RTYPE\",\"branch\":\"$BRANCH\"}"; exit 1
fi
WT_ARGS=(switch -c "$BRANCH" --yes)
[[ -n "$BASE" ]] && WT_ARGS+=(--base "$BASE")
if ! wt "${WT_ARGS[@]}" >&2; then
  echo "{\"ok\":false,\"error\":\"wt-switch-failed\",\"refType\":\"$RTYPE\",\"branch\":\"$BRANCH\"}"; exit 1
fi

# ---- resolve the worktree path + the primary checkout -----------------------
worktree_path_for_branch() {
  local want="$1" path=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch refs/heads/$want") printf '%s\n' "$path"; return 0 ;;
    esac
  done < <(git worktree list --porcelain)
  return 1
}
WTPATH="$(worktree_path_for_branch "$BRANCH" || true)"
MAIN_CHECKOUT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"

# ---- carry over gitignored env/secret files + symlink node_modules ----------
ENV_COPIED=(); NM_LINKED=()
if [[ -n "$WTPATH" && -n "$MAIN_CHECKOUT" && "$WTPATH" != "$MAIN_CHECKOUT" ]]; then
  while IFS= read -r n; do [[ -n "$n" ]] && ENV_COPIED+=("$n"); done < <(tl_copy_env_files "$MAIN_CHECKOUT" "$WTPATH")
  [[ ${#ENV_COPIED[@]} -gt 0 ]] && log "carried env files: ${ENV_COPIED[*]}"
  # Link every node_modules (root + nested workspaces) — private @facilitron/*
  # deps can't be reinstalled from the public registry. Best-effort, non-fatal.
  while IFS= read -r n; do [[ -n "$n" ]] && NM_LINKED+=("$n"); done < <(tl_link_node_modules "$MAIN_CHECKOUT" "$WTPATH")
  [[ ${#NM_LINKED[@]} -gt 0 ]] && log "linked node_modules: ${NM_LINKED[*]}"
fi

# ---- transition (Jira) / assign (GitHub) ------------------------------------
TRANSITIONED=false; ASSIGNED=false
if [[ "$NO_TRANSITION" -eq 0 ]]; then
  if [[ "$RTYPE" == jira ]] && command -v acli >/dev/null 2>&1; then
    if acli jira workitem transition --key "$RID" --status 'In Progress' --yes >/dev/null 2>&1; then
      TRANSITIONED=true; log "Jira $RID → In Progress"
    else
      log "Jira transition failed for $RID (non-blocking)"
    fi
  elif [[ "$RTYPE" == gh ]] && command -v gh >/dev/null 2>&1; then
    GH_ARGS=(issue edit "$RID" --add-assignee @me)
    [[ -n "$RREPO" ]] && GH_ARGS+=(--repo "$RREPO")
    if gh "${GH_ARGS[@]}" >/dev/null 2>&1; then
      ASSIGNED=true; log "GitHub issue $RID assigned to @me"
    else
      log "GitHub assign failed for $RID (non-blocking)"
    fi
  fi
fi

# ---- emit the result line ---------------------------------------------------
env_json=""
for i in "${!ENV_COPIED[@]}"; do [[ $i -gt 0 ]] && env_json+=","; env_json+="\"${ENV_COPIED[$i]}\""; done
nm_json=""
for i in "${!NM_LINKED[@]}"; do [[ $i -gt 0 ]] && nm_json+=","; nm_json+="\"${NM_LINKED[$i]}\""; done
if [[ "$RTYPE" == jira ]]; then
  printf '{"ok":true,"refType":"jira","key":"%s","branch":"%s","worktreePath":"%s","envCopied":[%s],"nodeModulesLinked":[%s],"baseFreshened":%s,"transitioned":%s}\n' \
    "$RID" "$BRANCH" "${WTPATH:-}" "$env_json" "$nm_json" "$BASE_FRESHENED" "$TRANSITIONED"
else
  printf '{"ok":true,"refType":"gh","issue":"%s","repo":"%s","branch":"%s","worktreePath":"%s","envCopied":[%s],"nodeModulesLinked":[%s],"baseFreshened":%s,"assigned":%s}\n' \
    "$RID" "${RREPO:-}" "$BRANCH" "${WTPATH:-}" "$env_json" "$nm_json" "$BASE_FRESHENED" "$ASSIGNED"
fi
