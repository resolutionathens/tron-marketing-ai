#!/usr/bin/env bash
# close-worktree: deterministically tear down a ticket's worktree, branch, and
# tmux session, then emit a machine-readable result line.
#
# This is the DETERMINISTIC core of the close-worktree skill (Phase B of the
# determinism plan). The SKILL.md keeps the interactive narrative (picking which
# worktree, force-on-dirty judgment); this script is the fixed sequence the agent
# runs as ONE command instead of N improvised steps. It is idempotent: a piece
# that is already gone counts as done, never an error — the same philosophy the
# OS uses to VERIFY cleanup (tron-os lib/git.ts summarizeCleanup), so the skill
# does it + reports, and the OS independently confirms it.
#
# Usage:
#   close-worktree.sh <branch> [--force] [--keep-branch] [--keep-remote]
#
#   --force        force-remove a dirty worktree. Local branch force-deletion is
#                  still allowed only after its merge has been verified.
#   --keep-branch  remove the worktree but leave the local+remote branch
#   --keep-remote  delete the local branch but leave origin's copy
#
# Operates from the main checkout (resolved via --git-common-dir), so it works
# even when invoked from inside the worktree being removed.
#
# Output: exactly ONE line of JSON on stdout, e.g.
#   {"ok":true,"branch":"MD-1801-x","worktreeRemoved":true,"worktreePath":"/…",
#    "localBranchDeleted":true,"remoteBranchDeleted":true,"sessionClosed":true,
#    "workspaceClosed":true,"leftovers":[]}
# (`workspaceClosed` is a backwards-compatible alias of `sessionClosed`.)
# All human-readable narration goes to stderr. ok=false iff `leftovers` is
# non-empty (something the script was asked to remove is still present).

set -euo pipefail

BRANCH=""
FORCE=0
KEEP_BRANCH=0
KEEP_REMOTE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --keep-branch) KEEP_BRANCH=1 ;;
    --keep-remote) KEEP_REMOTE=1 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 0 ;;
    -*) echo "close-worktree.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)
      if [[ -z "$BRANCH" ]]; then BRANCH="$1"; else
        echo "close-worktree.sh: unexpected argument '$1'" >&2; exit 2
      fi ;;
  esac
  shift
done

if [[ -z "$BRANCH" ]]; then
  echo "usage: close-worktree.sh <branch> [--force] [--keep-branch] [--keep-remote]" >&2
  exit 2
fi

log() { echo "close-worktree: $*" >&2; }

# ---- source shared libs -------------------------------------------------------
_TLIB="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/tools/ticket/ticket-lib.sh}"
[[ -z "$_TLIB" || ! -f "$_TLIB" ]] && _TLIB="$(cd "$(dirname "$0")/../../../tools/ticket" && pwd)/ticket-lib.sh"
# shellcheck source=/dev/null
source "$_TLIB"
_WLIB="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/tools/worktree/worktree-lib.sh}"
[[ -z "$_WLIB" || ! -f "$_WLIB" ]] && _WLIB="$(cd "$(dirname "$0")/../../../tools/worktree" && pwd)/worktree-lib.sh"
# shellcheck source=/dev/null
source "$_WLIB"
unset _TLIB _WLIB

# ---- resolve the main checkout ---------------------------------------------
# --git-common-dir points at the shared .git for every worktree; strip the
# trailing /.git to get the primary checkout (same idiom as tron:git-dev).
if ! GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  echo '{"ok":false,"error":"not inside a git repository","leftovers":["repo"]}'
  exit 1
fi
MAIN_REPO="${GIT_COMMON_DIR%/.git}"
g() { git -C "$MAIN_REPO" "$@"; }

WTPATH="$(wl_worktree_path_for_branch "$BRANCH" "$MAIN_REPO" || true)"

# Track anything we were asked to remove but couldn't.
LEFTOVERS=()
WORKTREE_REMOVED=true
SESSION_CLOSED=true
LOCAL_DELETED=true
REMOTE_DELETED=true

# ---- 1. locate the tmux session, but keep it alive until cleanup succeeds ---
# The worker session is the final resource removed. If any git cleanup fails,
# it must remain alive so the worker can inspect the leftovers and retry.
TICKET_KEY="$(printf '%s' "$BRANCH" | grep -oE '^[A-Z]+-[0-9]+' || true)"
BRANCH_SESSION="$(wl_session_name_for_branch "$BRANCH")"
SESSION=""
if command -v tmux >/dev/null 2>&1; then
  SESSION="$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep -E "^(${TICKET_KEY:-$BRANCH_SESSION}|${BRANCH_SESSION})" | head -1 || true)"
  [[ -n "$SESSION" ]] || log "no matching tmux session for ${TICKET_KEY:-$BRANCH_SESSION}"
else
  log "tmux not present — skipping session close"
fi

# ---- 2. refresh default and verify branch-deletion safety -------------------
# Refresh before cleanup so ordinary ancestry checks see newly merged commits.
# If refresh fails, retain the branch unless its merge can still be proven.
if DEFAULT_BRANCH="$(tl_freshen_default "$MAIN_REPO")"; then
  log "refreshed default branch $DEFAULT_BRANCH"
else
  log "could not refresh default branch ${DEFAULT_BRANCH:-unknown}; merge verification will fail closed"
fi
LOCAL_TIP="$(g rev-parse --verify "refs/heads/$BRANCH" 2>/dev/null || true)"
REMOTE_TIP=""
if g remote get-url origin >/dev/null 2>&1; then
  REMOTE_TIP="$(g ls-remote --heads origin "$BRANCH" 2>/dev/null | awk 'NR == 1 { print $1 }')"
fi
LOCAL_PROOF=""
REMOTE_PROOF=""
if [[ "$KEEP_BRANCH" -eq 0 && -n "$LOCAL_TIP" ]]; then
  LOCAL_PROOF="$(wl_branch_merge_proof "$BRANCH" "$DEFAULT_BRANCH" "$MAIN_REPO" "$LOCAL_TIP" || true)"
  if [[ -n "$LOCAL_PROOF" ]]; then
    log "verified local $BRANCH is merged ($LOCAL_PROOF)"
  else
    log "could not verify local $BRANCH at $LOCAL_TIP is merged into $DEFAULT_BRANCH"
  fi
fi
if [[ "$KEEP_BRANCH" -eq 0 && "$KEEP_REMOTE" -eq 0 && -n "$REMOTE_TIP" ]]; then
  REMOTE_PROOF="$(wl_branch_merge_proof "$BRANCH" "$DEFAULT_BRANCH" "$MAIN_REPO" "$REMOTE_TIP" || true)"
  if [[ -n "$REMOTE_PROOF" ]]; then
    log "verified origin/$BRANCH is merged ($REMOTE_PROOF)"
  else
    log "could not verify origin/$BRANCH at $REMOTE_TIP is merged into $DEFAULT_BRANCH"
  fi
fi

# ---- 3. remove the worktree + verify it actually went away -----------------
if [[ -n "$WTPATH" ]]; then
  RM_ARGS=(worktree remove)
  [[ "$FORCE" -eq 1 ]] && RM_ARGS+=(--force)
  RM_ARGS+=("$WTPATH")
  if g "${RM_ARGS[@]}" 2>/dev/null; then
    log "removed worktree $WTPATH"
  else
    log "git worktree remove failed for $WTPATH (dirty? rerun with --force)"
  fi
  # git deregisters synchronously but the dir rm can lag/leak (open handles).
  # The unregister is what matters; mop up a leftover dir only if git no longer
  # tracks it — at that point there is no race left to lose.
  if [[ -d "$WTPATH" ]]; then
    if ! g worktree list --porcelain | grep -qxF "worktree $WTPATH"; then
      rm -rf "$WTPATH" 2>/dev/null || true
      log "swept leftover directory $WTPATH"
    fi
  fi
  if [[ -d "$WTPATH" ]]; then
    WORKTREE_REMOVED=false; LEFTOVERS+=("worktree")
  fi
else
  log "no worktree registered for $BRANCH — already gone"
fi

# ---- 4. delete the local branch --------------------------------------------
branch_exists() { g show-ref --verify --quiet "refs/heads/$BRANCH"; }
if [[ "$KEEP_BRANCH" -eq 0 ]]; then
  if branch_exists; then
    if [[ -z "$LOCAL_PROOF" ]]; then
      log "keeping local branch $BRANCH because merge is not verified"
    elif g branch -d "$BRANCH" >/dev/null 2>&1; then
      log "deleted local branch $BRANCH"
    elif g branch -D "$BRANCH" >/dev/null 2>&1; then
      log "force-deleted squash-merged local branch $BRANCH ($LOCAL_PROOF)"
    else
      log "merge was verified but git could not delete local branch $BRANCH"
    fi
  else
    log "local branch $BRANCH already absent"
  fi
  if branch_exists; then LOCAL_DELETED=false; LEFTOVERS+=("local branch"); fi
else
  log "--keep-branch: leaving local branch $BRANCH"
fi

# ---- 5. delete the remote branch -------------------------------------------
# Idempotent: an already-deleted ref (PR auto-delete on merge) is success.
remote_branch_present() { [[ -n "$(g ls-remote --heads origin "$BRANCH" 2>/dev/null)" ]]; }
if [[ "$KEEP_BRANCH" -eq 0 && "$KEEP_REMOTE" -eq 0 ]]; then
  if g remote get-url origin >/dev/null 2>&1; then
    if remote_branch_present; then
      if [[ -z "$REMOTE_PROOF" ]]; then
        log "keeping origin branch $BRANCH because merge is not verified"
      elif g push origin --delete "$BRANCH" >/dev/null 2>&1; then
        log "deleted origin branch $BRANCH"
      else
        log "git push origin --delete failed for $BRANCH"
      fi
    else
      log "origin branch $BRANCH already absent"
    fi
    if remote_branch_present; then REMOTE_DELETED=false; LEFTOVERS+=("origin branch"); fi
  else
    log "no origin remote — skipping remote delete"
  fi
else
  log "keeping remote branch $BRANCH"
fi

# ---- 6. close the worker session only after all git cleanup is verified -----
if [[ ${#LEFTOVERS[@]} -eq 0 && -n "$SESSION" ]]; then
  if tmux kill-session -t "$SESSION" >/dev/null 2>&1; then
    log "killed tmux session $SESSION"
  else
    SESSION_CLOSED=false; LEFTOVERS+=("session")
    log "failed to kill tmux session $SESSION"
  fi
elif [[ ${#LEFTOVERS[@]} -gt 0 && -n "$SESSION" ]]; then
  SESSION_CLOSED=false
  LEFTOVERS+=("session")
  log "kept tmux session $SESSION alive because cleanup is incomplete"
fi

# ---- 7. emit the machine-readable result line ------------------------------
OK=true; [[ ${#LEFTOVERS[@]} -gt 0 ]] && OK=false
LEFT_JSON=""
for i in "${!LEFTOVERS[@]}"; do
  [[ $i -gt 0 ]] && LEFT_JSON+=","
  LEFT_JSON+="\"${LEFTOVERS[$i]}\""
done
# `sessionClosed` is the current field; `workspaceClosed` is kept as a
# backwards-compatible alias (same value) for any downstream tooling that still
# reads the cmux-era name.
printf '{"ok":%s,"branch":"%s","worktreeRemoved":%s,"worktreePath":"%s","localBranchDeleted":%s,"remoteBranchDeleted":%s,"sessionClosed":%s,"workspaceClosed":%s,"leftovers":[%s]}\n' \
  "$OK" "$BRANCH" "$WORKTREE_REMOVED" "${WTPATH:-}" "$LOCAL_DELETED" "$REMOTE_DELETED" "$SESSION_CLOSED" "$SESSION_CLOSED" "$LEFT_JSON"

[[ "$OK" == true ]] || exit 1
exit 0
