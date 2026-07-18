#!/usr/bin/env bash
# worktree-lib.sh — pure, offline-testable git-worktree primitives shared by the
# worktree skills (Phase B). Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/worktree/worktree-lib.sh"
#
# Parsing `git worktree list --porcelain` by hand is easy to get subtly wrong
# (the branch line is `branch refs/heads/<name>`, and the first stanza is always
# the primary checkout). These two helpers encode that once. Pure git — no wt,
# no tmux, no network — so they run against a plain `git worktree add` in tests.

# Echo the absolute path of the worktree checked out on <branch>, or return 1.
#   wl_worktree_path_for_branch MD-1801-x [repo] → /Users/…/worktrees/MD-1801-x
wl_worktree_path_for_branch() {
  local want="$1" repo="${2:-$(pwd)}" path="" line
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch refs/heads/$want") printf '%s\n' "$path"; return 0 ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)
  return 1
}

# Sanitize a branch name into a tmux session name. '.' and ':' are illegal in
# tmux session names, so both map to '-'. This is THE canonical rule — the
# open-worktree session setup and close-worktree session matching must agree.
#   wl_session_name_for_branch MD-1801.hotfix → MD-1801-hotfix
wl_session_name_for_branch() {
  printf '%s\n' "$(printf '%s' "$1" | tr '.:' '--')"
}

# Echo the primary checkout (the first `worktree` stanza), or return 1.
#   wl_main_checkout [repo] → /Users/…/marketing-pages
wl_main_checkout() {
  local repo="${1:-$(pwd)}" path
  path="$(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
  [[ -n "$path" ]] && { printf '%s\n' "$path"; return 0; }
  return 1
}

# Verify that deleting the supplied <tip> of <branch> is safe after a merge into
# <default>. A normal merge/rebase is proven by ancestry. A squash merge
# deliberately breaks that ancestry, so accept a GitHub PR only when its exact
# head OID matches <tip> and it was merged into the expected base branch. The
# explicit OID lets callers verify local and remote refs independently and
# supports retries where either ref is already absent. Echoes the proof used;
# returns 1 when neither proof is available. This function never mutates refs.
wl_branch_merge_proof() {
  local branch="$1" default="$2" repo="$3" tip="$4" prs match
  [[ -n "$default" && -n "$tip" ]] || return 1
  if git -C "$repo" cat-file -e "$tip^{commit}" 2>/dev/null \
      && git -C "$repo" merge-base --is-ancestor \
        "$tip" "refs/heads/$default" 2>/dev/null; then
    printf 'ancestor:%s:%s\n' "$default" "$tip"
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 1
  prs="$(cd "$repo" && gh pr list \
    --head "$branch" --base "$default" --state merged \
    --json number,headRefOid --limit 100 2>/dev/null)" || return 1
  match="$(jq -r --arg tip "$tip" \
    'map(select(.headRefOid == $tip)) | first | select(. != null) | "\(.number):\(.headRefOid)"' \
    <<<"$prs" 2>/dev/null)" || return 1
  [[ -n "$match" ]] || return 1
  printf 'merged-pr:%s\n' "$match"
}
