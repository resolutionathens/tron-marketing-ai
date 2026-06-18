#!/usr/bin/env bash
# git-dev: merge the current feature branch into `dev`, push, and restore the
# starting state. The DETERMINISTIC core of tron:git-dev (Phase B) — the agent
# runs this one command instead of the checkout/pull/merge/push dance. Works
# from a worktree or a regular checkout. The ONLY conflict it resolves is
# package*.json (--ours, per project rule); any other conflict aborts cleanly
# and is handed back for human judgment.
#
# Usage:
#   git-dev.sh [feature-branch]   # defaults to the current branch
#
# Output: one JSON line on stdout (narration on stderr). Examples:
#   {"ok":true,"branch":"MD-1801-x","target":"dev","pushed":true,"depsResolved":[]}
#   {"ok":false,"branch":"MD-1801-x","target":"dev","error":"conflicts","conflicts":["src/a.ts"]}
set -euo pipefail

log() { echo "git-dev: $*" >&2; }
emit_err() { printf '{"ok":false,"branch":"%s","target":"dev","error":"%s"%s}\n' "${BRANCH:-}" "$1" "${2:-}"; exit 1; }

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
LIB="${ROOT:+$ROOT/tools/git/git-promote.sh}"
[[ -z "$LIB" || ! -f "$LIB" ]] && LIB="$(cd "$(dirname "$0")/../../../tools/git" && pwd)/git-promote.sh"
# shellcheck source=/dev/null
source "$LIB"

MAIN="$(gp_main_repo)" || { echo '{"ok":false,"error":"not a git repo"}'; exit 1; }

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
case "$BRANCH" in
  master|main|dev|production|staging|HEAD) emit_err "on-protected-branch" ;;
esac

# Working tree must be clean — commit or stash first (tron:git-commit).
if [[ -n "$(gp_dirty "$(pwd)")" ]]; then emit_err "dirty-working-tree" ; fi

IN_WT=false; gp_in_worktree "$MAIN" && IN_WT=true

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
    printf '{"ok":true,"branch":"%s","target":"dev","pushed":true,"worktree":%s,"depsResolved":[%s]}\n' \
      "$BRANCH" "$IN_WT" "$DEPS_JSON"
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
