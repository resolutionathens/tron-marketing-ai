---
name: close-worktree
model: sonnet
effort: low
description: "Close and clean up git worktrees and their associated tmux sessions. Use this skill when the user says 'close worktree', 'remove worktree', 'clean up worktree', 'delete worktree', or wants to remove a worktree they're done with. Also trigger when the user says 'I'm done with this branch', 'tear down the workspace', or 'clean up finished worktrees'."
allowed-tools:
  - Bash
  - AskUserQuestion
scout:
  surface: developer
---

# Close Worktree

Remove git worktrees that are no longer needed, along with their tmux sessions and optionally branches.

## When dispatched (worker mode)

If `TRON_DISPATCH_ID` is set, this skill is running as a non-interactive dispatched worker — never
call `AskUserQuestion`. A dispatched worker almost always already knows which branch to close (it's
the branch it was working in), so the "don't know which branch" case below should rarely trigger.
If it does — the list is ambiguous and picking wrong risks deleting the wrong worktree or unsaved
work — post ONE concise plain-text message listing the candidate branches and stop to wait for the
reply, rather than using `AskUserQuestion`.

Interactive users are unaffected — this section only changes behavior when `TRON_DISPATCH_ID` is set.

## Fast path — when you already know the branch

**Step 1: Move to the main checkout** — this changes the invoking session's cwd so it survives worktree removal.

```bash
if ! GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  echo "close-worktree: not inside a git repository" >&2; exit 1
fi
cd "${GIT_COMMON_DIR%/.git}" || exit 1
```

**Step 2: Run the removal script** — after moving out, invoke the script with your branch name.

```bash
name=close-worktree
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/close-worktree.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/close-worktree.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/close-worktree.sh" ] || { echo "tron:$name: scripts/close-worktree.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/close-worktree.sh" <branch> [--force] [--keep-branch] [--keep-remote]
```

Kills the tmux session, removes the worktree (verifies it's gone), deletes local + remote branch, re-syncs the main checkout's default branch. Idempotent — any piece already gone counts as done.

- `--force` — force-remove a dirty worktree / force-delete an unmerged branch
- `--keep-branch` — remove worktree only, leave local + remote branch
- `--keep-remote` — delete local branch but keep origin's copy

One JSON line:

```json
{"ok":true,"branch":"MD-1801-x","worktreeRemoved":true,"localBranchDeleted":true,"remoteBranchDeleted":true,"sessionClosed":true,"leftovers":[]}
```

`ok:false` with non-empty `leftovers` means something is still present — rerun with `--force`, or stop if there may be unsaved work.

**Before removal — stop the worktree's dev server.** If `start-ticket` spun up a `bun dev` background task for this worktree, `TaskStop` it first. The script kills the tmux session but can't stop that task (it's a background task of the orchestrator session, not in tmux); a live dev server keeps file handles open in the worktree dir and races `wt remove`, leaving orphaned fragments behind.

## When you DON'T know which branch to close

Run `wt list` to show all worktrees. The user will either name a branch or say "clean up." If they say "clean up," present the list and let them pick.

## For the manual path (if script is unavailable)

Use `wt remove <branch>` (with `--force` if dirty). Kill the tmux session first with `tmux kill-session -t <name>` — wait a beat between kill and remove to avoid file-handle races. After removal, `rm -rf <worktree-path>` if `wt`'s background cleanup left fragments. Delete branches with `git branch -d <branch>` and `git push origin --delete <branch>`.

## Batch cleanup for merged worktrees

```bash
wt step prune
```

Removes all worktrees whose branches are merged into the default branch. Skips worktrees younger than 1h — for recent ones, fall back to individual `wt remove`.