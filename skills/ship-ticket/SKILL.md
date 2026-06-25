---
name: ship-ticket
model: sonnet
effort: medium
description: "Walk the canonical Facilitron task lifecycle end-to-end: ticket lookup → branch & worktree → atomic commits → dev → PR → prod → cleanup. Use this skill ONLY when the user asks for the whole flow at once — phrases like 'ship MD-XXXX end-to-end', 'take this ticket from start to finish', 'walk me through the full Facilitron flow', 'run the full lifecycle on CCAL-XXXX', or 'do everything for this ticket'. Do NOT use this skill when the user asks for a single stage ('commit', 'open a PR', 'start MD-XXXX'); those have their own dedicated skills (tron:git-commit, tron:git-pr, tron:start-ticket). This is the orchestrator for whole-lifecycle requests, not individual moves."
allowed-tools:
  - Skill
  - Bash
  - Read
  - AskUserQuestion
---

# Ship Ticket — Whole-Lifecycle Orchestrator

Walk the canonical Facilitron task lifecycle by **delegating to the existing per-stage skills** in sequence. This skill never reimplements stage logic — it routes.

## Lifecycle stages

```
1. INTAKE       — fetch Jira ticket details                  (tron:jira)
2. KICKOFF      — branch, worktree, "In Progress"            (tron:start-ticket)
3. WORK         — implementation by the user                 (no skill — user-driven)
4. COMMIT       — atomic conventional commits + push         (tron:git-commit)
5. PROMOTE-DEV  — promote branch to dev environment          (tron:git-dev)
6. REVIEW       — open the PR                                (tron:git-pr)
7. PROMOTE-PROD — promote to production                      (tron:git-pushtoprod)
8. CLEANUP      — remove worktree, prune branch              (tron:close-worktree)
```

This orchestrator drives every stage itself, so it does **not** want a dedicated tmux session — there's nothing to work in it. When delegating KICKOFF, tell `tron:start-ticket` to skip its tmux session setup step. CLEANUP likewise has no session to close. The dev-server step in `tron:start-ticket`, on the other hand, is still useful — orchestrator-driven UI work needs a worktree-scoped dev server too — so leave that one in.

## Step 1 — Determine current lifecycle position

Before running anything, figure out where the user is in the lifecycle. Don't assume a fresh start — they may already have a branch, commits, or an open PR.

Check in this order:

1. **Branch name** — `git rev-parse --abbrev-ref HEAD`. If it matches `<KEY>-<slug>` already, kickoff has happened.
2. **Uncommitted changes** — `git status --porcelain | head -1`. If non-empty, work is in progress.
3. **Unpushed commits** — `git log --oneline @{u}.. 2>/dev/null | head -1` (if upstream exists). If non-empty, commits are local-only.
4. **Open PR** — `gh pr view --json url,state 2>/dev/null`. If it returns, REVIEW has been reached.
5. **Merged to dev / prod** — check whether the PR is merged and to which target.

Briefly tell the user where they are: "You're at stage 4 (COMMIT) — branch exists, 3 uncommitted files, no PR yet."

## Step 2 — Confirm the next stage with the user

Present the **next single stage** and ask for confirmation before delegating. Use AskUserQuestion with two options: "Run /<next-skill>" and "Skip this stage". Never advance past the next stage in one bound — let the user gate each step.

Example:

> Next: stage 5 — PROMOTE-DEV via tron:git-dev. Proceed?

## Step 3 — Delegate via the Skill tool

Invoke the dedicated skill for the chosen stage using the Skill tool. Do not run the stage's commands directly — the per-stage skills own their own logic, prompts, and edge cases.

When delegating KICKOFF, pass `tron:start-ticket` an explicit instruction to skip its tmux session setup step (the dev-server step stays — orchestrator-driven UI work needs a worktree-scoped dev server) — see the note under "Lifecycle stages" above.

Skill mapping:

| Stage        | Skill name          |
| ------------ | ------------------- |
| INTAKE       | tron:jira           |
| KICKOFF      | tron:start-ticket   |
| COMMIT       | tron:git-commit     |
| PROMOTE-DEV  | tron:git-dev        |
| REVIEW       | tron:git-pr         |
| PROMOTE-PROD | tron:git-pushtoprod |
| CLEANUP      | tron:close-worktree |

After REVIEW or PROMOTE-PROD, optionally offer `tron:jira-comment` to post a short progress note (PR opened / shipped to prod) on the ticket.

## Step 4 — After the stage, re-check position

When the delegated skill finishes, return to Step 1 — re-detect lifecycle position. The user may have decided to stop, or the stage may have produced unexpected state. Don't blindly advance.

## Step 5 — Stop conditions

Stop the loop and hand back to the user when:

- The user declines the next stage in Step 2.
- Stage 8 (CLEANUP) completes — the lifecycle is done.
- A stage fails non-recoverably (e.g. CI red on PR, merge conflict on PROMOTE-DEV). Report what failed and let the user decide.

## What this skill does NOT do

- It does not perform commits, opens PRs, or runs deploys directly. Those are owned by per-stage skills.
- It does not skip stages without explicit user opt-in.
- It does not auto-fire on any Jira mention. Auto-firing happens only on whole-lifecycle phrasing — see the description's trigger list.
- It does not replace `/gsd:*` commands. GSD is for multi-phase initiatives, not single tickets.
