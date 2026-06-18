#!/usr/bin/env bash
# git-promote.sh — shared deterministic primitives for the branch-promotion
# skills (tron:git-dev, tron:git-pushtoprod). Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/git/git-promote.sh"
#
# Every function operates on the MAIN checkout (resolved via --git-common-dir)
# so the skills work identically from a worktree or a regular checkout. The one
# piece of conflict "judgment" we encode is the project rule that package.json /
# package-lock.json are owned by the long-lived branches (dev/staging/prod) and
# never updated by an incoming merge — those resolve to --ours automatically;
# ANY other conflict aborts and is handed back to the agent/human.

# Resolve the primary checkout (strip trailing /.git from the common dir).
gp_main_repo() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s\n' "${common%/.git}"
}

# True when the current checkout is a linked worktree (not the primary).
gp_in_worktree() {
  local main="$1" top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "$top" != "$main" ]]
}

# Echo the dirty/porcelain lines if the working tree has uncommitted changes;
# empty output (return 0) means clean.
gp_dirty() { git -C "$1" status --porcelain; }

# Merge <source> into <target> on the main checkout, pushing on success.
#   gp_merge_into <main_repo> <target> <source>
# Echoes one of:
#   "ok"                         merged cleanly (or fast-forward), pushed
#   "ok:package.json,..."        only package*.json conflicted → --ours, pushed
#   "conflict:<file>,<file>"     other conflicts → merge aborted, NOT pushed
#   "error:<stage>"              checkout/pull/push failed
# Return code mirrors success (0) vs conflict/error (1).
gp_merge_into() {
  local main="$1" target="$2" source="$3"
  git -C "$main" checkout "$target" >/dev/null 2>&1 || { echo "error:checkout-$target"; return 1; }
  git -C "$main" pull --ff-only >/dev/null 2>&1 || git -C "$main" pull >/dev/null 2>&1 || { echo "error:pull-$target"; return 1; }

  if git -C "$main" merge --no-edit "$source" >/dev/null 2>&1; then
    git -C "$main" push >/dev/null 2>&1 || { echo "error:push-$target"; return 1; }
    echo "ok"; return 0
  fi

  # Merge stopped on conflict. Inspect the unmerged set.
  local unmerged resolved="" other=""
  unmerged="$(git -C "$main" diff --name-only --diff-filter=U)"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      package.json|package-lock.json) resolved+="${resolved:+,}$f" ;;
      *) other+="${other:+,}$f" ;;
    esac
  done <<< "$unmerged"

  if [[ -n "$other" ]]; then
    git -C "$main" merge --abort >/dev/null 2>&1 || true
    echo "conflict:$other"; return 1
  fi

  # Only the dependency files conflicted — keep the target branch's copies.
  # shellcheck disable=SC2086
  git -C "$main" checkout --ours package.json package-lock.json >/dev/null 2>&1 || true
  git -C "$main" add package.json package-lock.json >/dev/null 2>&1 || true
  git -C "$main" commit --no-edit >/dev/null 2>&1 || { echo "error:commit-$target"; return 1; }
  git -C "$main" push >/dev/null 2>&1 || { echo "error:push-$target"; return 1; }
  echo "ok:$resolved"; return 0
}
