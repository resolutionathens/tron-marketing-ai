---
name: ship-ticket
model: haiku
effort: low
description: "Walk the canonical Facilitron task lifecycle end-to-end: ticket lookup → branch & worktree → atomic commits → dev → PR → prod → cleanup. Use this skill ONLY when the user asks for the whole flow at once — phrases like 'ship MD-XXXX end-to-end', 'take this ticket from start to finish', 'walk me through the full Facilitron flow', 'run the full lifecycle on CCAL-XXXX', or 'do everything for this ticket'. Do NOT use this skill when the user asks for a single stage ('commit', 'open a PR', 'start MD-XXXX'); those have their own dedicated skills (tron:git-commit, tron:git-pr, tron:start-ticket). This is the orchestrator for whole-lifecycle requests, not individual moves."
allowed-tools:
  - Skill
  - Bash
  - Read
  - AskUserQuestion
scout:
  surface: developer
---

# Ship Ticket — Whole-Lifecycle Orchestrator

<!-- Model note: kept on `haiku`/`low` deliberately. This skill is pure routing —
     detect lifecycle position from a few cheap git/gh checks, confirm the next
     stage, and delegate via the Skill tool. All real judgment (commit messages,
     PR bodies, deploy gates) lives in the per-stage skills it invokes, each of
     which carries its own model tier. Anything heavier here is a routing bug. -->

Walk the canonical Facilitron task lifecycle by **delegating to the existing per-stage skills** in sequence. This skill never reimplements stage logic — it routes.

## When dispatched (worker mode)

Under dispatch (`TRON_DISPATCH_ID` set) `AskUserQuestion` is not callable — see
[WORKER_CONTRACT.md](../../WORKER_CONTRACT.md) → *Tools and skills unavailable to you*.

What that means here: skip Step 2's per-stage confirmation and advance through the lifecycle
automatically, delegating to each stage's skill in turn — each delegated skill applies its own
dispatch-mode behavior (see its SKILL.md), so approval prompts inside those stages are already
handled.

**Park at the PR gate — do not run past REVIEW.** A dispatched run's autonomy ends when the PR is
open (see [WORKER_CONTRACT.md](../../WORKER_CONTRACT.md) → *The PR-gate autonomy model* and *The
worktree is retained through the PR gate*). Stop the loop at stage 6 (REVIEW) with the branch,
worktree, and worker session **left intact**, and hand back. Do **not** autonomously advance to
stage 7 (PROMOTE-PROD) or stage 8 (CLEANUP): production promotion is human-gated, and
`tron:close-worktree` runs only after the PR merges or a human explicitly asks for cleanup —
removing the worktree early destroys the state the reviewer needs and the branch the merge lands
on. The kickoff prompt authorizes those later stages explicitly or they do not happen.

This changes Step 5's stop conditions under dispatch. Its first condition ("the user declines the
next stage in Step 2") does not apply — there is no Step 2 gate to decline. Its "Stage 8 (CLEANUP)
completes" condition **does not apply either**: in dispatch mode, **stage 6 (REVIEW) completing —
the PR is open — replaces stage 8 as the loop's normal end**, because the run parks at the PR gate
and never reaches PROMOTE-PROD or CLEANUP on its own. Step 5's remaining condition still applies as
written: stop and report on a non-recoverable stage failure. And if a genuinely risky or ambiguous
decision comes up that no stage's default can resolve, post ONE concise plain-text message and stop
to wait for the reply, rather than using `AskUserQuestion`.

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

**Repos that never promote to production** (they ship by tag or PR-merge straight to their
default branch, so stage 7 never runs — e.g. `tron-marketing-ai`, `tron-os`) skip the only
automated Done transition in this lifecycle. Before stage 8 (CLEANUP), mark the ticket Done
explicitly — see `tron:jira` → "Marking a ticket Done at close-out" for the exact invocation.
Repos that do promote keep getting the transition automatically from `tron:git-pushtoprod`; don't
run it again by hand there.

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
- Stage 8 (CLEANUP) completes — the lifecycle is done. **Under dispatch this is replaced by stage 6 (REVIEW) completing** — see "When dispatched (worker mode)" above; a dispatched run parks at the open PR and never reaches stage 8 on its own.
- A stage fails non-recoverably (e.g. CI red on PR, merge conflict on PROMOTE-DEV). Report what failed and let the user decide.

## What this skill does NOT do

- It does not perform commits, opens PRs, or runs deploys directly. Those are owned by per-stage skills.
- It does not skip stages without explicit user opt-in.
- It does not auto-fire on any Jira mention. Auto-firing happens only on whole-lifecycle phrasing — see the description's trigger list.
- It does not replace `/gsd:*` commands. GSD is for multi-phase initiatives, not single tickets.
