#!/usr/bin/env bash
# git-dev: merge the current feature branch into `dev`, push, and restore the
# starting state. The DETERMINISTIC core of tron:git-dev (Phase B) — the agent
# runs this one command instead of the checkout/pull/merge/push dance. Works
# from a worktree or a regular checkout. The ONLY conflict it resolves is
# package*.json (--ours, per project rule); any other conflict aborts cleanly
# and is handed back for human judgment.
#
# Usage:
#   git-dev.sh [feature-branch] [--worktree <abs-path>]
#     feature-branch     defaults to the branch checked out in the worktree
#     --worktree <path>  resolve the source branch + dirty-check from this path
#                        instead of $PWD. The worktree-integrated shell resets
#                        $PWD to the MAIN checkout after every Bash call, so a wt
#                        caller (tron-os) must pass the worktree path explicitly
#                        or this script would read the main checkout's branch
#                        (often master → on-protected-branch) and stray files.
#
# Output: one JSON line on stdout (narration on stderr). Examples:
#   {"ok":true,"branch":"MD-1801-x","target":"dev","pushed":true,"depsResolved":[],"skippedSupersededCommits":[]}
#   {"ok":true,"branch":"MD-1801-x","target":"dev","pushed":false,"depsResolved":[],"skippedSupersededCommits":["abc123"]}
#   {"ok":false,"branch":"MD-1801-x","target":"dev","error":"conflicts","conflicts":["src/a.ts"]}
set -euo pipefail

log() { echo "git-dev: $*" >&2; }
emit_err() { printf '{"ok":false,"branch":"%s","target":"dev","error":"%s"%s}\n' "${BRANCH:-}" "$1" "${2:-}"; exit 1; }

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
LIB="${ROOT:+$ROOT/tools/git/git-promote.sh}"
[[ -z "$LIB" || ! -f "$LIB" ]] && LIB="$(cd "$(dirname "$0")/../../../tools/git" && pwd)/git-promote.sh"
# shellcheck source=/dev/null
source "$LIB"

# ---- parse args: optional positional branch + --worktree <abs-path> ---------
BRANCH=""; WT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree)
      [[ -z "${2:-}" ]] && { echo '{"ok":false,"error":"missing-worktree-value"}'; exit 2; }
      WT="$2"; shift 2; continue ;;
    -*) echo "{\"ok\":false,\"error\":\"unknown-flag\",\"flag\":\"$1\"}"; exit 2 ;;
    *) if [[ -z "$BRANCH" ]]; then BRANCH="$1"; else echo "{\"ok\":false,\"error\":\"unexpected-arg\",\"arg\":\"$1\"}"; exit 2; fi ;;
  esac
  shift
done
# The worktree we promote FROM: an explicit --worktree, else the current dir.
WT="${WT:-$(pwd)}"

MAIN="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  && MAIN="${MAIN%/.git}" || { echo '{"ok":false,"error":"not a git repo"}'; exit 1; }

# Branch + dirty-check are worktree-scoped — read them from $WT, never $PWD
# (which the wt-integrated shell resets to MAIN after every Bash call).
[[ -z "$BRANCH" ]] && BRANCH="$(git -C "$WT" branch --show-current)"
case "$BRANCH" in
  master|main|dev|production|staging|HEAD|"") emit_err "on-protected-branch" ;;
esac

# Working tree must be clean — commit or stash first (tron:git-commit).
if [[ -n "$(gp_dirty "$WT")" ]]; then emit_err "dirty-working-tree" ; fi

# Friendly guard: a direct-ship repo (tron-os, tron-marketing-ai) has no `dev`
# branch, so gp_merge_into would fail with the opaque error:checkout-dev.
if ! gp_has_branch "$MAIN" dev; then emit_err "no-dev-branch"; fi

IN_WT=false; gp_in_worktree "$MAIN" "$WT" && IN_WT=true

log "merging $BRANCH → dev (main=$MAIN, worktree=$IN_WT)"
RES="$(gp_merge_into "$MAIN" dev "$BRANCH")" || true

case "$RES" in
  ok|ok:*)
    DEPS="${RES#ok}"; DEPS="${DEPS#:}"
    DEPS_JSON=""
    if [[ -n "$DEPS" ]]; then
      IFS=',' read -ra parts <<< "$DEPS"
      for i in "${!parts[@]}"; do [[ $i -gt 0 ]] && DEPS_JSON+=","; DEPS_JSON+="\"${parts[$i]}\""; done
    fi
    # Restore: a regular checkout returns to the feature branch; from a worktree
    # the worktree is already on it, so just park the main checkout on master.
    if $IN_WT; then git -C "$MAIN" checkout master >/dev/null 2>&1 || true
    else git -C "$MAIN" checkout "$BRANCH" >/dev/null 2>&1 || true; fi
    log "dev updated and pushed"
    printf '{"ok":true,"branch":"%s","target":"dev","pushed":true,"worktree":%s,"depsResolved":[%s],"skippedSupersededCommits":[]}\n' \
      "$BRANCH" "$IN_WT" "$DEPS_JSON"
    ;;
  skipped:*)
    SKIPPED="${RES#skipped:}"; SKIPPED_JSON=""
    IFS=',' read -ra parts <<< "$SKIPPED"
    for i in "${!parts[@]}"; do [[ $i -gt 0 ]] && SKIPPED_JSON+=","; SKIPPED_JSON+="\"${parts[$i]}\""; done
    if $IN_WT; then git -C "$MAIN" checkout master >/dev/null 2>&1 || true
    else git -C "$MAIN" checkout "$BRANCH" >/dev/null 2>&1 || true; fi
    log "dev already contains equivalent patches; skipped superseded commits: $SKIPPED"
    printf '{"ok":true,"branch":"%s","target":"dev","pushed":false,"worktree":%s,"depsResolved":[],"skippedSupersededCommits":[%s]}\n' \
      "$BRANCH" "$IN_WT" "$SKIPPED_JSON"
    ;;
  conflict:*)
    FILES="${RES#conflict:}"; CJSON=""
    IFS=',' read -ra parts <<< "$FILES"
    for i in "${!parts[@]}"; do [[ $i -gt 0 ]] && CJSON+=","; CJSON+="\"${parts[$i]}\""; done
    if $IN_WT; then git -C "$MAIN" checkout master >/dev/null 2>&1 || true; fi
    log "non-package conflicts — merge aborted, resolve manually: $FILES"
    emit_err "conflicts" ",\"conflicts\":[$CJSON]"
    ;;
  *)
    if $IN_WT; then git -C "$MAIN" checkout master >/dev/null 2>&1 || true; fi
    log "merge failed: $RES"
    emit_err "${RES#error:}"
    ;;
esac
