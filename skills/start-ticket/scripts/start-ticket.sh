#!/usr/bin/env bash
# start-ticket: the DETERMINISTIC spine of tron:start-ticket (Phase B) — classify
# the ref, create the branch+worktree with wt, carry over gitignored env files,
# and transition/assign the ticket. Emits a machine-readable result line. The
# JUDGMENT steps stay in the SKILL.md: reading the ticket, wording the slug, and
# moving into the worktree to begin the work.
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
command -v jq >/dev/null 2>&1 || { echo '{"ok":false,"error":"jq-not-found"}'; exit 1; }

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
WLIB="${ROOT:+$ROOT/tools/worktree/worktree-lib.sh}"
[[ -z "$WLIB" || ! -f "$WLIB" ]] && WLIB="$(cd "$(dirname "$0")/../../../tools/worktree" && pwd)/worktree-lib.sh"
# shellcheck source=/dev/null
source "$WLIB"

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
  MAIN_NOW="$(wl_main_checkout 2>/dev/null || true)"
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
WTPATH="$(wl_worktree_path_for_branch "$BRANCH" || true)"
MAIN_CHECKOUT="$(wl_main_checkout || true)"

# `wt switch -c` can leave a new branch inheriting the default branch's
# upstream (for example origin/master). Set the intended same-name upstream now,
# before git-commit or another lifecycle step performs the branch's first push.
UPSTREAM_PROVISIONED=false
if [[ -n "$WTPATH" ]]; then
  if tl_provision_same_name_upstream "$WTPATH" "$BRANCH"; then
    UPSTREAM_PROVISIONED=true
    log "upstream provisioned: $BRANCH → origin/$BRANCH"
  else
    log "could not provision origin/$BRANCH upstream (origin or checkout unavailable)"
  fi
fi

# ---- carry over gitignored env/secret files + selectively share node_modules -
ENV_COPIED=(); NM_LINKED=(); NM_NATIVE=(); NM_UNSAFE=(); NM_ABSENT=()
INSTALL_SELECTED=false; INSTALL_CMD=""; INSTALL_RAN=false; INSTALL_SUCCEEDED="null"; INSTALL_REASON=""
if [[ -n "$WTPATH" && -n "$MAIN_CHECKOUT" && "$WTPATH" != "$MAIN_CHECKOUT" ]]; then
  while IFS= read -r n; do [[ -n "$n" ]] && ENV_COPIED+=("$n"); done < <(tl_copy_env_files "$MAIN_CHECKOUT" "$WTPATH")
  [[ ${#ENV_COPIED[@]} -gt 0 ]] && log "carried env files: ${ENV_COPIED[*]}"
  # Sharing dependencies saves disk and install time for pure-JS projects, but
  # a dependency tree is unshareable for two different reasons: compiled
  # .node binaries are mutable build outputs (rebuilding one through a shared
  # symlink repairs one consumer while breaking another), and a Vite-family
  # verification runtime (Vitest, Nuxt) resolves a symlink to its real path
  # and 404s every import outside the worktree (see tl_symlink_unsafe_deps).
  # Either reason leaves every tree unshared and, when the repo has registered
  # an install command, installs into the worktree instead of only reporting.
  NM_PATHS=()
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    NM_PATHS+=("${n#"$MAIN_CHECKOUT"/}")
  done < <(find "$MAIN_CHECKOUT" -maxdepth 3 -type d -name node_modules -prune -print 2>/dev/null)
  if [[ ${#NM_PATHS[@]} -eq 0 ]]; then
    NM_ABSENT=("node_modules")
  else
    PROJECT_HAS_NATIVE=false
    for n in "${NM_PATHS[@]}"; do
      if [[ -n "$(find "$MAIN_CHECKOUT/$n" \( -type f -o -type l \) -name '*.node' -print -quit 2>/dev/null)" ]]; then
        PROJECT_HAS_NATIVE=true
        break
      fi
    done
    PROJECT_SYMLINK_UNSAFE=false
    if [[ "$PROJECT_HAS_NATIVE" == false ]] && tl_symlink_unsafe_deps "$MAIN_CHECKOUT"; then
      PROJECT_SYMLINK_UNSAFE=true
    fi
    if [[ "$PROJECT_HAS_NATIVE" == true || "$PROJECT_SYMLINK_UNSAFE" == true ]]; then
      INSTALL_SELECTED=true
      if [[ "$PROJECT_HAS_NATIVE" == true ]]; then
        NM_NATIVE=("${NM_PATHS[@]}")
        log "native node_modules detected; left unshared: ${NM_NATIVE[*]}"
      else
        NM_UNSAFE=("${NM_PATHS[@]}")
        log "symlink-unsafe verification runtime detected (vite/vitest/nuxt); left unshared: ${NM_UNSAFE[*]}"
      fi
      if INSTALL_CMD="$(tl_dev_install_command "$MAIN_CHECKOUT")"; then
        log "running registered dev.install in $WTPATH: $INSTALL_CMD"
        INSTALL_RAN=true
        if (cd "$WTPATH" && bash -c "$INSTALL_CMD") >&2; then
          INSTALL_SUCCEEDED=true
          log "dev.install succeeded"
        else
          INSTALL_SUCCEEDED=false
          log "dev.install failed (non-blocking — worktree, branch, and ticket transition are kept; run it manually)"
        fi
      else
        INSTALL_CMD=""
        INSTALL_REASON="no dev.install registered in .tron/content-profile.json — run the project's install command manually"
        log "$INSTALL_REASON"
      fi
    else
      # Link every node_modules (root + nested workspaces) when the tree is
      # safe to share. Best-effort, non-fatal for private dependencies.
      while IFS= read -r n; do [[ -n "$n" ]] && NM_LINKED+=("$n"); done < <(tl_link_node_modules "$MAIN_CHECKOUT" "$WTPATH")
      [[ ${#NM_LINKED[@]} -gt 0 ]] && log "linked node_modules: ${NM_LINKED[*]}"
    fi
  fi
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
# Built with jq (not hand-escaped printf) because nodeModulesInstall.command
# carries an arbitrary repo-declared shell command (spaces, flags, `--`).
json_array() {
  if [[ $# -eq 0 ]]; then printf '[]'; return; fi
  printf '%s\n' "$@" | jq -R . | jq -s -c .
}

nodeModulesInstall="$(jq -n \
  --argjson selected "$INSTALL_SELECTED" \
  --arg command "$INSTALL_CMD" \
  --argjson ran "$INSTALL_RAN" \
  --argjson succeeded "$INSTALL_SUCCEEDED" \
  --arg reason "$INSTALL_REASON" \
  '{selected:$selected,
    command:(if $command == "" then null else $command end),
    ran:$ran,
    succeeded:$succeeded,
    reason:(if $reason == "" then null else $reason end)}')"

if [[ "$RTYPE" == jira ]]; then
  jq -nc \
    --arg key "$RID" \
    --arg branch "$BRANCH" \
    --arg worktreePath "${WTPATH:-}" \
    --argjson envCopied "$(json_array "${ENV_COPIED[@]+"${ENV_COPIED[@]}"}")" \
    --argjson nodeModulesLinked "$(json_array "${NM_LINKED[@]+"${NM_LINKED[@]}"}")" \
    --argjson nodeModulesNotLinkedNative "$(json_array "${NM_NATIVE[@]+"${NM_NATIVE[@]}"}")" \
    --argjson nodeModulesNotLinkedUnsafe "$(json_array "${NM_UNSAFE[@]+"${NM_UNSAFE[@]}"}")" \
    --argjson nodeModulesAbsent "$(json_array "${NM_ABSENT[@]+"${NM_ABSENT[@]}"}")" \
    --argjson nodeModulesInstall "$nodeModulesInstall" \
    --argjson baseFreshened "$BASE_FRESHENED" \
    --argjson upstreamProvisioned "$UPSTREAM_PROVISIONED" \
    --argjson transitioned "$TRANSITIONED" \
    '{ok:true,refType:"jira",key:$key,branch:$branch,worktreePath:$worktreePath,
      envCopied:$envCopied,nodeModulesLinked:$nodeModulesLinked,
      nodeModulesNotLinkedNative:$nodeModulesNotLinkedNative,
      nodeModulesNotLinkedUnsafe:$nodeModulesNotLinkedUnsafe,
      nodeModulesAbsent:$nodeModulesAbsent,nodeModulesInstall:$nodeModulesInstall,
      baseFreshened:$baseFreshened,upstreamProvisioned:$upstreamProvisioned,
      transitioned:$transitioned}'
else
  jq -nc \
    --arg issue "$RID" \
    --arg repo "${RREPO:-}" \
    --arg branch "$BRANCH" \
    --arg worktreePath "${WTPATH:-}" \
    --argjson envCopied "$(json_array "${ENV_COPIED[@]+"${ENV_COPIED[@]}"}")" \
    --argjson nodeModulesLinked "$(json_array "${NM_LINKED[@]+"${NM_LINKED[@]}"}")" \
    --argjson nodeModulesNotLinkedNative "$(json_array "${NM_NATIVE[@]+"${NM_NATIVE[@]}"}")" \
    --argjson nodeModulesNotLinkedUnsafe "$(json_array "${NM_UNSAFE[@]+"${NM_UNSAFE[@]}"}")" \
    --argjson nodeModulesAbsent "$(json_array "${NM_ABSENT[@]+"${NM_ABSENT[@]}"}")" \
    --argjson nodeModulesInstall "$nodeModulesInstall" \
    --argjson baseFreshened "$BASE_FRESHENED" \
    --argjson upstreamProvisioned "$UPSTREAM_PROVISIONED" \
    --argjson assigned "$ASSIGNED" \
    '{ok:true,refType:"gh",issue:$issue,repo:$repo,branch:$branch,worktreePath:$worktreePath,
      envCopied:$envCopied,nodeModulesLinked:$nodeModulesLinked,
      nodeModulesNotLinkedNative:$nodeModulesNotLinkedNative,
      nodeModulesNotLinkedUnsafe:$nodeModulesNotLinkedUnsafe,
      nodeModulesAbsent:$nodeModulesAbsent,nodeModulesInstall:$nodeModulesInstall,
      baseFreshened:$baseFreshened,upstreamProvisioned:$upstreamProvisioned,
      assigned:$assigned}'
fi
