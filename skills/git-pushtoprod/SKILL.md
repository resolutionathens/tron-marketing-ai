---
name: git-pushtoprod
description: "Merge master into staging and production branches, pushing both. Use this skill when the user says 'push to prod', 'deploy to production', 'push to staging and production', 'ship to prod', or anything that implies they want master deployed to the staging and production branches."
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Deploy to Production Assistant

Merge master into staging and production branches, pushing both, then return to the original branch. Works from both regular checkouts and worktrees.

## Fast path (deterministic)

This flow is mechanical — run the bundled script instead of the steps below:

```bash
bash $CLAUDE_SKILL_DIR/scripts/git-pushtoprod.sh [--no-jira] [--key <TICKET>]
```

It checks the tree is clean, brings `master` current, merges master into `staging`
then `production` (pushing each), and transitions the ticket to **Done**. It stops at
the **first** failed/conflicted environment — `production` is never touched if
`staging` fails — so a partial deploy is impossible to miss. `package.json`/
`package-lock.json` conflicts resolve to `--ours`; any other conflict aborts that
environment and is reported. The Jira key is parsed from the branch unless you pass
`--key`; `--no-jira` skips the transition (e.g. GitHub-issue work).

One JSON line on stdout (narration on stderr):

```json
{"ok":true,"staging":true,"production":true,"jira":"MD-1801:Done","leftovers":[]}
{"ok":false,"staging":false,"production":false,"error":"staging-conflicts","conflicts":["src/a.ts"],"jira":null,"leftovers":["staging","production"]}
```

`leftovers` lists the environments that did **not** ship. Smoke it with
`bash $CLAUDE_SKILL_DIR/scripts/test-git-pushtoprod.sh`. The steps below are the
explanation / manual fallback for conflict cases.

> **Tier reminder:** a production deploy is a high-risk action. This script is the
> *mechanics*; the decision to run it stays with the human/PR gate — don't invoke it
> autonomously.

## Step 1: Ensure clean working tree

Run `git status --porcelain`.

If there are uncommitted changes, tell the user to commit or stash first.

## Step 2: Detect worktree vs regular checkout

```bash
MAIN_REPO=$(git rev-parse --path-format=absolute --git-common-dir | sed 's/\/.git$//')
CURRENT_DIR=$(pwd)
```

If in a worktree, all branch operations should use `git -C "$MAIN_REPO"`. Otherwise, run commands normally.

## Step 3: Record current state

Run `git branch --show-current` to save the current branch (needed to return to it if not in a worktree).

## Step 4: Update master

**From a worktree:**
```bash
git -C "$MAIN_REPO" checkout master
git -C "$MAIN_REPO" pull
```

**From a regular checkout:**
```bash
git checkout master
git pull
```

If the pull fails, report the error and stop.

## Step 5: Merge master into staging

```bash
git [-C "$MAIN_REPO"] checkout staging
git [-C "$MAIN_REPO"] pull
git [-C "$MAIN_REPO"] merge master
git [-C "$MAIN_REPO"] push
```

If the merge fails due to conflicts, check which files conflicted:

- **`package.json` and `package-lock.json`** — always keep staging's version. These files should never be updated by merges into dev or staging; those branches manage their own dependency state. Resolve automatically:
  ```bash
  git [-C "$MAIN_REPO"] checkout --ours package.json package-lock.json
  git [-C "$MAIN_REPO"] add package.json package-lock.json
  git [-C "$MAIN_REPO"] commit --no-edit
  git [-C "$MAIN_REPO"] push
  ```

- **Any other file** — stop and tell the user. Do NOT resolve other conflicts automatically.

Never force push. If the push fails, report the error and stop.

## Step 6: Merge master into production

```bash
git [-C "$MAIN_REPO"] checkout production
git [-C "$MAIN_REPO"] pull
git [-C "$MAIN_REPO"] merge master
git [-C "$MAIN_REPO"] push
```

If any step fails, report the error and stop. Do NOT force push or resolve conflicts automatically.

## Step 7: Return to previous state

**From a worktree:** Return the main repo to master:
```bash
git -C "$MAIN_REPO" checkout master
```

**From a regular checkout:**
```bash
git checkout <original-branch-name>
```

## Step 8: Transition Jira ticket to Done

Extract the ticket key from the branch name (e.g., `MD-1714` from `MD-1714-redirect-old-fit-page-to-new` or `CCAL-1789` from `CCAL-1789-fix-panelist-name-typo`). The key is the leading `<PROJECT>-<NUMBER>` segment.

```bash
acli jira workitem transition --key <KEY> --status 'Done' --yes
```

If the transition fails (wrong status name, already done, etc.), mention it but don't block the rest of the flow.

## Step 9: Report

Tell the user:
- Master was merged into staging and pushed
- Master was merged into production and pushed
- They're back on their original branch (or still in their worktree)

## Cleanup reminder

If working in a worktree and this ticket is fully deployed, remind the user they can clean it up:
```
git worktree remove ../<branch-name>
```

This deletes the worktree directory. The branch remains in git history — it's just the working copy that's removed.
