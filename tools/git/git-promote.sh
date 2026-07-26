#!/usr/bin/env bash
# git-promote.sh — shared deterministic primitives for the branch-promotion
# skills (tron:git-dev, tron:git-pushtoprod). Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/git/git-promote.sh"
#
# Every function operates on the MAIN checkout (resolved via --git-common-dir)
# so the skills work identically from a worktree or a regular checkout. The one
# piece of conflict "judgment" we encode is the project rule that dependency
# manifests/lockfiles are owned by the long-lived branches (dev/staging/prod) and
# never updated by an incoming merge — those resolve to --ours automatically;
# ANY other conflict aborts and is handed back to the agent/human.

# Lockfiles/manifests owned by the long-lived branch — a conflict on any of these
# resolves to --ours (keep the target branch's copy). List-driven so a repo that
# uses yarn/pnpm can extend it (add yarn.lock / pnpm-lock.yaml here).
GP_DEP_FILES=(package.json package-lock.json bun.lock bun.lockb)
gp_is_dep_file() {
  local f="$1" d
  for d in "${GP_DEP_FILES[@]}"; do [[ "$f" == "$d" ]] && return 0; done
  return 1
}

# Resolve the primary checkout (strip trailing /.git from the common dir).
gp_main_repo() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s\n' "${common%/.git}"
}

# True when <path> (default: $PWD) is a linked worktree, not the primary checkout.
#   gp_in_worktree <main> [path]
gp_in_worktree() {
  local main="$1" path="${2:-$PWD}" top
  top="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "$top" != "$main" ]]
}

# Echo the dirty/porcelain lines if the working tree has uncommitted changes;
# empty output (return 0) means clean.
gp_dirty() { git -C "$1" status --porcelain; }

# True when <branch> exists on the main checkout, either as a local branch or a
# remote-tracking ref on origin. Used to give a friendly message before trying to
# promote into a branch the repo doesn't have (e.g. `dev` in a direct-ship repo).
gp_has_branch() {
  local main="$1" branch="$2"
  git -C "$main" show-ref --verify --quiet "refs/heads/$branch" && return 0
  git -C "$main" show-ref --verify --quiet "refs/remotes/origin/$branch" && return 0
  return 1
}

# Merge <source> into <target> on the main checkout, pushing on success.
#   gp_merge_into <main_repo> <target> <source>
# Echoes one of:
#   "ok"                         merged cleanly (or fast-forward), pushed
#   "ok:package.json,..."        only package*.json conflicted → --ours, pushed
#   "skipped:<sha>,<sha>"        every incoming patch is already on target
#   "conflict:<file>,<file>"     other conflicts → merge aborted, NOT pushed
#   "error:<stage>"              checkout/pull/push failed
# Return code mirrors success (0) vs conflict/error (1).
gp_merge_into() {
  local main="$1" target="$2" source="$3"
  git -C "$main" checkout "$target" >/dev/null 2>&1 || { echo "error:checkout-$target"; return 1; }
  # Promotion targets must match their remote tracking branch before we inspect
  # or merge them. A fallback pull can create a local merge commit, which makes
  # the later skip path report success after mutating the target without pushing.
  git -C "$main" pull --ff-only >/dev/null 2>&1 || { echo "error:pull-$target"; return 1; }

  # An empty `git cherry` result is ambiguous: it can mean there are no incoming
  # commits because source is already reachable from target. Identify that exact
  # commit explicitly so callers report an identical promotion as superseded.
  local source_tip
  if git -C "$main" merge-base --is-ancestor "$source" "$target" 2>/dev/null; then
    source_tip="$(git -C "$main" rev-parse "$source" 2>/dev/null)" || { echo "error:resolve-$source"; return 1; }
    echo "skipped:$source_tip"
    return 0
  fi

  # `git cherry` compares stable patch IDs rather than commit IDs. If every
  # source-only commit is marked `-`, the target already contains equivalent
  # changes, commonly through a squash or an independently applied fix. Merging
  # those commits adds no behavior and can create unrelated conflicts, so report
  # the superseded SHAs and leave the target untouched. Any `+` keeps the normal
  # merge path, ensuring a merely similar commit is never skipped.
  local cherry superseded="" has_incoming=false has_non_equivalent=false mark sha
  cherry="$(git -C "$main" cherry "$target" "$source" 2>/dev/null || true)"
  while read -r mark sha; do
    [[ -z "${mark:-}" || -z "${sha:-}" ]] && continue
    has_incoming=true
    if [[ "$mark" == "-" ]]; then
      superseded+="${superseded:+,}$sha"
    else
      has_non_equivalent=true
    fi
  done <<< "$cherry"
  if $has_incoming && ! $has_non_equivalent; then
    echo "skipped:$superseded"
    return 0
  fi

  if git -C "$main" merge --no-edit "$source" >/dev/null 2>&1; then
    git -C "$main" push >/dev/null 2>&1 || { echo "error:push-$target"; return 1; }
    echo "ok"; return 0
  fi

  # Merge stopped on conflict. Inspect the unmerged set.
  local unmerged resolved="" other="" resolved_arr=()
  unmerged="$(git -C "$main" diff --name-only --diff-filter=U)"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if gp_is_dep_file "$f"; then
      resolved+="${resolved:+,}$f"; resolved_arr+=("$f")
    else
      other+="${other:+,}$f"
    fi
  done <<< "$unmerged"

  if [[ -n "$other" ]]; then
    git -C "$main" merge --abort >/dev/null 2>&1 || true
    echo "conflict:$other"; return 1
  fi

  # Only the dependency files conflicted — keep the target branch's copies.
  # Touch just the files that actually conflicted (a repo may not carry every
  # lockfile in GP_DEP_FILES).
  git -C "$main" checkout --ours ${resolved_arr[@]+"${resolved_arr[@]}"} >/dev/null 2>&1 || true
  git -C "$main" add ${resolved_arr[@]+"${resolved_arr[@]}"} >/dev/null 2>&1 || true
  git -C "$main" commit --no-edit >/dev/null 2>&1 || { echo "error:commit-$target"; return 1; }
  git -C "$main" push >/dev/null 2>&1 || { echo "error:push-$target"; return 1; }
  echo "ok:$resolved"; return 0
}
