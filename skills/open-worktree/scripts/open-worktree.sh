#!/usr/bin/env bash
# open-worktree: the DETERMINISTIC spine of tron:open-worktree (Phase B) —
# switch to / resolve an existing worktree, carry over the gitignored env files
# that don't follow a worktree, and flag an empty node_modules. These are the
# two footguns from the skill's "Common gotchas" (a dev server that 500s on
# missing env, or a silently-failed install). The cmux three-pane layout stays
# in the SKILL.md prose — interactive surface composition is judgment, and its
# sibling start-ticket.sh keeps cmux setup in prose for the same reason.
#
# Usage:
#   open-worktree.sh --branch <name> [--repo <path>] [--no-switch]
#     --branch <name>  the worktree's branch (default: current branch)
#     --repo <path>    run git from here (default: cwd)
#     --no-switch      don't run `wt switch` — just resolve the existing worktree
#
# Output: one JSON line on stdout (narration on stderr):
#   {"ok":true,"branch":"MD-1801-x","worktreePath":"/…","mainCheckout":"/…",
#    "envCopied":[".env.local"],"nodeModulesEmpty":false}
#   {"ok":false,"branch":"x","error":"worktree-not-found","hint":"create it with tron:start-ticket"}
set -euo pipefail

log() { echo "open-worktree: $*" >&2; }

BRANCH=""; REPO="$(pwd)"; NO_SWITCH=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift ;;
    --repo) REPO="${2:-}"; shift ;;
    --no-switch) NO_SWITCH=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "open-worktree.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) echo "open-worktree.sh: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

[[ -d "$REPO" ]] || { echo "open-worktree.sh: no such repo: $REPO" >&2; exit 2; }
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
[[ -z "$BRANCH" ]] && { echo "open-worktree.sh: --branch required (could not resolve current branch)" >&2; exit 2; }

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
src_lib() { # relative-path
  local lib="${ROOT:+$ROOT/tools/$1}"
  [[ -z "$lib" || ! -f "$lib" ]] && lib="$(cd "$(dirname "$0")/../../../tools" && pwd)/$1"
  # shellcheck source=/dev/null
  source "$lib"
}
src_lib worktree/worktree-lib.sh
src_lib ticket/ticket-lib.sh

# ---- switch to the worktree (best-effort) -----------------------------------
if [[ "$NO_SWITCH" -eq 0 ]] && command -v wt >/dev/null 2>&1; then
  ( cd "$REPO" && wt switch "$BRANCH" --yes >&2 ) || log "wt switch failed (continuing to resolve from git)"
fi

# ---- resolve paths ----------------------------------------------------------
WTPATH="$(wl_worktree_path_for_branch "$BRANCH" "$REPO" || true)"
if [[ -z "$WTPATH" ]]; then
  printf '{"ok":false,"branch":"%s","error":"worktree-not-found","hint":"create it with tron:start-ticket, or check `wt list`"}\n' "$BRANCH"
  exit 1
fi
MAIN_CHECKOUT="$(wl_main_checkout "$REPO" || true)"
log "branch=$BRANCH → worktree $WTPATH (main: ${MAIN_CHECKOUT:-?})"

# ---- carry gitignored env/secret files into the worktree --------------------
ENV_COPIED=()
if [[ -n "$MAIN_CHECKOUT" && "$WTPATH" != "$MAIN_CHECKOUT" ]]; then
  while IFS= read -r n; do [[ -n "$n" ]] && ENV_COPIED+=("$n"); done < <(tl_copy_env_files "$MAIN_CHECKOUT" "$WTPATH")
  [[ ${#ENV_COPIED[@]} -gt 0 ]] && log "carried env files: ${ENV_COPIED[*]}"
fi

# ---- node_modules sanity ----------------------------------------------------
NODE_EMPTY=true
if [[ -d "$WTPATH/node_modules" ]] && [[ -n "$(ls -A "$WTPATH/node_modules" 2>/dev/null)" ]]; then
  NODE_EMPTY=false
fi
[[ "$NODE_EMPTY" == true ]] && log "node_modules is empty/absent — run the project's install before launching dev"

# ---- emit -------------------------------------------------------------------
env_json=""
for i in "${!ENV_COPIED[@]}"; do [[ $i -gt 0 ]] && env_json+=","; env_json+="\"${ENV_COPIED[$i]}\""; done
printf '{"ok":true,"branch":"%s","worktreePath":"%s","mainCheckout":"%s","envCopied":[%s],"nodeModulesEmpty":%s}\n' \
  "$BRANCH" "$WTPATH" "${MAIN_CHECKOUT:-}" "$env_json" "$NODE_EMPTY"
