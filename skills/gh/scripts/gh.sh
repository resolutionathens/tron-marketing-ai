#!/usr/bin/env bash
# gh.sh: a thin, deterministic wrapper over the `gh` CLI — the mechanical core of
# the tron:gh skill. The error-prone, hand-typed `gh ...` invocations in SKILL.md
# get one consistent entry point each so the model calls a subcommand instead of
# re-assembling flags by hand. Anything not covered here is still reachable via
# the raw `gh`/`gh api` recipes in reference/cli.md.
#
# Usage:
#   gh.sh <subcommand> [flags]
#
# Subcommands (all need the `gh` binary on PATH + an authed account):
#   gh-view-pr    --number N [--repo owner/repo]   PR summary as one JSON line
#   gh-list-issues [--repo owner/repo] [--state open|closed|all]
#                  [--assignee @me] [--label L] [--limit N]   issues as JSON
#   gh-merge-pr   --number N [--repo owner/repo] [--method squash|merge|rebase]
#                  [--no-delete-branch]   worktree-safe server-side merge + branch delete
#   gh-comment    --number N --body "..." [--repo owner/repo]   comment on an issue/PR
#
# Output contract: each subcommand emits ONE JSON line on stdout carrying an `ok`
# boolean; narration/errors go to stderr. Exit 0 success / 1 logical failure /
# 2 usage error.
set -euo pipefail

log() { echo "gh.sh: $*" >&2; }
usage_err() { echo "gh.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || usage_err "jq is required but not on PATH"
command -v gh >/dev/null 2>&1 || usage_err "the gh CLI is not on PATH (brew install gh)"

# ---- flags ------------------------------------------------------------------
CMD="${1:-}"; [[ $# -gt 0 ]] && shift
NUMBER=""; REPO=""; STATE="open"; ASSIGNEE=""; LABEL=""; LIMIT=30
BODY=""; METHOD="squash"; DELETE_BRANCH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --number|-n) NUMBER="${2:-}"; shift ;;
    --repo) REPO="${2:-}"; shift ;;
    --state) STATE="${2:-}"; shift ;;
    --assignee) ASSIGNEE="${2:-}"; shift ;;
    --label) LABEL="${2:-}"; shift ;;
    --limit) LIMIT="${2:-}"; shift ;;
    --body) BODY="${2:-}"; shift ;;
    --method) METHOD="${2:-}"; shift ;;
    --no-delete-branch) DELETE_BRANCH=0 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) usage_err "unexpected argument '$1'" ;;
  esac
  shift
done

# `--repo owner/repo` passthrough for any gh subcommand (empty → current repo).
repo_args() { [[ -n "$REPO" ]] && printf -- '--repo\n%s\n' "$REPO"; }

# ---- subcommands ------------------------------------------------------------
cmd_view_pr() {
  [[ -z "$NUMBER" ]] && usage_err "gh-view-pr requires --number <N>"
  local out
  if ! out="$(gh pr view "$NUMBER" $(repo_args) \
      --json number,title,state,isDraft,mergeable,reviewDecision,headRefName,baseRefName,url,statusCheckRollup 2>/dev/null)"; then
    jq -nc --arg n "$NUMBER" '{ok:false,number:($n|tonumber),reason:"PR not found or no access"}'; exit 1
  fi
  jq -c '{ok:true,number,title,state,isDraft,mergeable,reviewDecision,
          headRefName,baseRefName,url,
          checks:[(.statusCheckRollup // [])[]|{name:(.name // .context),
                  status:(.status // null),conclusion:(.conclusion // .state // null)}]}' <<<"$out"
}

cmd_list_issues() {
  local args=(issue list --state "$STATE" --limit "$LIMIT"
              --json number,title,state,author,labels,assignees,updatedAt,url)
  [[ -n "$ASSIGNEE" ]] && args+=(--assignee "$ASSIGNEE")
  [[ -n "$LABEL" ]] && args+=(--label "$LABEL")
  local out
  if ! out="$(gh "${args[@]}" $(repo_args) 2>/dev/null)"; then
    jq -nc '{ok:false,reason:"could not list issues — check repo context and gh auth"}'; exit 1
  fi
  jq -c --arg s "$STATE" \
    '{ok:true,state:$s,count:length,
      items:[.[]|{number,title,state,author:.author.login,
                  labels:[.labels[].name],assignees:[.assignees[].login],
                  updatedAt,url}]}' <<<"$out"
}

cmd_merge_pr() {
  [[ -z "$NUMBER" ]] && usage_err "gh-merge-pr requires --number <N>"
  case "$METHOD" in squash|merge|rebase) ;; *) usage_err "--method must be squash|merge|rebase (got '$METHOD')" ;; esac
  # Resolve the head branch up front so we can delete it after merging.
  local branch
  branch="$(gh pr view "$NUMBER" $(repo_args) --json headRefName --jq .headRefName 2>/dev/null || true)"
  [[ -z "$branch" ]] && { jq -nc --arg n "$NUMBER" '{ok:false,number:($n|tonumber),reason:"PR not found or no access"}'; exit 1; }
  # Server-side API merge — no local git ops, so it is safe from a worktree.
  if ! gh api -X PUT "repos/{owner}/{repo}/pulls/$NUMBER/merge" $(repo_args) \
        -f merge_method="$METHOD" >/dev/null 2>&1; then
    local st; st="$(gh pr view "$NUMBER" $(repo_args) --json state --jq .state 2>/dev/null || echo UNKNOWN)"
    jq -nc --arg n "$NUMBER" --arg s "$st" '{ok:false,number:($n|tonumber),state:$s,reason:"merge failed — check CI/conflicts/merge-method (gh pr checks)"}'; exit 1
  fi
  local deleted=false
  if [[ "$DELETE_BRANCH" == 1 ]]; then
    if gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$branch" $(repo_args) >/dev/null 2>&1; then deleted=true
    else log "merged, but could not delete remote branch '$branch' (may be protected or already gone)"; fi
  fi
  jq -nc --arg n "$NUMBER" --arg m "$METHOD" --arg b "$branch" --argjson d "$deleted" \
    '{ok:true,number:($n|tonumber),merged:true,method:$m,branch:$b,branch_deleted:$d}'
}

cmd_comment() {
  [[ -z "$NUMBER" ]] && usage_err "gh-comment requires --number <N>"
  [[ -z "$BODY" ]] && usage_err "gh-comment requires --body \"...\""
  # `gh issue comment` works for both issues and PRs (PRs are issues server-side).
  local url
  if ! url="$(gh issue comment "$NUMBER" $(repo_args) --body "$BODY" 2>/dev/null)"; then
    jq -nc --arg n "$NUMBER" '{ok:false,number:($n|tonumber),reason:"could not post comment — check number, repo, and gh auth"}'; exit 1
  fi
  jq -nc --arg n "$NUMBER" --arg u "$url" '{ok:true,number:($n|tonumber),comment_url:$u}'
}

case "$CMD" in
  gh-view-pr)     cmd_view_pr ;;
  gh-list-issues) cmd_list_issues ;;
  gh-merge-pr)    cmd_merge_pr ;;
  gh-comment)     cmd_comment ;;
  ""|help|-h|--help) sed -n '2,25p' "$0" ;;
  *) usage_err "unknown subcommand '$CMD' (try: gh-view-pr, gh-list-issues, gh-merge-pr, gh-comment)" ;;
esac
