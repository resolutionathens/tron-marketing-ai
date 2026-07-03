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
