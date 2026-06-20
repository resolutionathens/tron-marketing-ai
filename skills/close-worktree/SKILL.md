---
name: close-worktree
model: sonnet
effort: low
description: "Close and clean up git worktrees and their associated cmux workspaces. Use this skill when the user says 'close worktree', 'remove worktree', 'clean up worktree', 'delete worktree', or wants to remove a worktree they're done with. Also trigger when the user says 'I'm done with this branch', 'tear down the workspace', or 'clean up finished worktrees'."
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Close Worktree

Remove git worktrees that are no longer needed using `wt`, along with their cmux workspaces and optionally their branches.

## Fast path (deterministic) — when you already know the branch

When you know exactly which branch to close (the common case after a merge, and the
only case when the OS routes here), skip the interactive steps and run the bundled
script. It does the fixed sequence as ONE command — close the cmux workspace, remove
the worktree and verify it's gone, delete the local branch, delete the origin branch —
and is **idempotent**: any piece that's already gone counts as done, not an error.

```bash
bash $CLAUDE_SKILL_DIR/scripts/close-worktree.sh <branch> [--force] [--keep-branch] [--keep-remote]
```

- `--force` — force-remove a dirty worktree / force-delete an unmerged branch.
- `--keep-branch` — remove the worktree only, leave the branch (local + remote).
- `--keep-remote` — delete the local branch but leave origin's copy.

It prints exactly one line of JSON on stdout (everything else is on stderr):

```json
{"ok":true,"branch":"MD-1801-x","worktreeRemoved":true,"worktreePath":"/…",
 "localBranchDeleted":true,"remoteBranchDeleted":true,"workspaceClosed":true,"leftovers":[]}
```

`ok` is `false` (and exit code `1`) **iff `leftovers` is non-empty** — i.e. something it
was asked to remove is still present (usually a dirty worktree or unmerged branch; rerun
with `--force`, or stop and tell the user if they may have unsaved work). The result
fields mirror the dimensions the OS independently verifies, so the skill *does* the
cleanup and the OS *confirms* it — neither trusts the other's word. The narrative below
is the fallback for when you DON'T already know the branch (the user said "clean up" and
you need to show the list and let them pick) or when something goes wrong.

Smoke it against real git any time with
`bash $CLAUDE_SKILL_DIR/scripts/test-close-worktree.sh`.

## Step 1: Identify worktrees to close

Run:
```bash
wt list
```

This shows all worktrees with their status, including uncommitted changes and sync state.

The user will either:
- Name a specific branch or worktree
- Say "all" or "clean up" — show them the list and let them pick
- Reference the current worktree — `wt list` marks the current one with `@`

If the user is currently inside the worktree being closed, warn them that their cmux workspace will be closed and they'll need to switch.

## Step 2: For each worktree, run cleanup

### 2a. Stop the worktree's dev server (if one was started)

If `start-ticket` spun up a `bun dev` background task for this worktree earlier in the session, stop it before removing the worktree — otherwise the running Node process keeps file handles open on a directory that's about to be deleted, which can race with `wt remove`'s async cleanup. Use `TaskStop` with the task ID that `start-ticket` captured. If you don't have the ID handy (different session, or the user started the server manually), it's fine to skip; the worktree removal will still succeed, but the user may need to kill the stale process themselves.

### 2b. Close the cmux workspace (if one exists)

Find the workspace by matching the title against the branch name or ticket key:

```bash
cmux --json list-workspaces
```

Workspace titles may be the full branch name or just the ticket key (e.g., "MD-1661" for branch "MD-1661-add-logos-case-studies-testimonials"). Match flexibly — check if the workspace title starts with the ticket key portion of the branch name.

If a matching workspace is found:
```bash
cmux close-workspace --workspace <ref>
```

If the user is currently in that workspace, close it anyway — cmux will move them to another workspace automatically.

**Do not chain `cmux close-workspace` with `wt remove` in a single `&&` command.** `close-workspace` returns as soon as the workspace is unregistered, but the panes inside (vim, shells, lingering postinstall scripts) take a moment to die and release file handles on files inside the worktree directory. If `wt remove` fires while those handles are still open, its background `rm` leaves fragments behind and you end up with orphan directories on disk that `wt list` no longer knows about. Run them as separate commands and give the panes a beat.

### 2c. Switch away if needed

If the user is in the worktree being removed, switch to main first:
```bash
wt switch main
```

### 2d. Remove the worktree with wt — and verify it actually went away

```bash
wt remove <branch-name>
```

`wt remove` unregisters the worktree from git synchronously and kicks off a background `rm` of the directory. The unregister is reliable; the directory removal can fail silently if a process inside the worktree still has files open (see 2b).

**Always verify and clean up afterward.** Capture the path from `wt list` before removing, then after `wt remove`:

```bash
# Give wt's background cleanup a moment, then check
sleep 2
if [ -d "<worktree-path>" ]; then
  rm -rf "<worktree-path>"
fi
```

This is the one place where a manual `rm -rf` *is* the right move — `wt` has already deregistered the worktree from git, so there's no race left to lose. You're just mopping up filesystem leftovers.

If the worktree has uncommitted changes, `wt remove` will warn. Tell the user and ask what to do — they can force it with `--force` or go save their work first.

### 2e. Branch deletion (usually already handled)

When the branch is fully merged, `wt remove` deletes it as part of the same operation. If the branch was unmerged or `wt remove` left it in place, ask the user:

- **Delete local branch only** — `git branch -d <branch>` (safe — fails if not fully merged)
- **Delete local and remote** — also `git push origin --delete <branch>`
- **Keep branches** — skip deletion

If a local delete fails because the branch isn't merged, mention this and ask if they want to force it (`git branch -D`). This is a safety net — they may have unmerged work.

**Tip:** If the user's workflow ends with `wt merge`, the branch is already deleted as part of the merge process.

## Step 3: Summary

After cleanup, confirm what was done:
- Worktree removed: `<branch-name>`
- cmux workspace closed (if applicable)
- Branches deleted (if applicable)

Keep it brief.

## Batch mode

For cleaning up multiple merged worktrees at once, use:
```bash
wt step prune
```

This removes all worktrees whose branches have been merged into the default branch and deletes the branches. Fast and safe — it only touches fully merged work.

`wt step prune` skips worktrees younger than 1h. For very recent worktrees, fall back to `wt remove <branch>` for each one.

For manual batch cleanup, loop through each one and run Steps 2a-2e. Ask about branch deletion once with options like "delete all", "keep all", or "ask for each".

## Alternative: wt merge

If the user wants to merge their changes and clean up in one step, suggest:
```bash
wt merge main
```

This will:
1. Commit any uncommitted changes (with LLM-generated message if configured)
2. Rebase onto main
3. Fast-forward merge to main
4. Remove the worktree and delete the branch

This is the cleanest workflow when the work is done and ready to merge.
