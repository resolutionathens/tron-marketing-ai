---
name: git-commit
model: sonnet
effort: medium
fallback:
  cost: low
  skip_when: "Use tron:git-commit only when there are changes to commit. For single-file trivial fixes, commit directly instead."
  stage_skips:
    - stage: "Analyze & group"
      skip_when: "Only one file changed or changes are all related to one concern"
description: "Stage, commit, and push changes with auto-generated conventional commit messages. Produces atomic commits — when changes span multiple concerns, they're split into separate focused commits rather than one large dump. Use for 'commit', 'commit and push', 'push this up', 'ship it', or anything that implies finalizing current work."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
scout:
  surface: developer
---

# Git Commit Assistant

Analyze changes, group them into atomic commits by logical concern, get user approval, commit, and push.

## When dispatched (worker mode)

Under dispatch (`TRON_DISPATCH_ID` set) `AskUserQuestion` is not callable — see
[WORKER_CONTRACT.md](../../WORKER_CONTRACT.md) → *Tools and skills unavailable to you*.

What that means here:

- **Step 4's approval prompt:** skip it and proceed straight to Step 5 with the generated commit
  plan as-is.
- **The missing-Jira-key question** in the guard below: it's a genuine open question with no safe
  default (creating an unwanted ticket or misattributing work is hard to undo) — post it as ONE
  concise plain-text message and stop to wait for the reply, rather than using `AskUserQuestion`.

## Guard: never commit to master/main

Check the current branch name with `git branch --show-current`. If it's `master` or `main`, block immediately:

> You're on the default branch. Use `tron:start-ticket` to create a feature branch first.

If the output is **empty**, HEAD is detached — stop and tell the user to create or
check out a branch first (e.g. `git checkout -b <branch>`); never commit on a
detached HEAD.

If the branch name doesn't contain a Jira key (`[A-Z]+-\d+`), ask the user:

> This branch doesn't reference a Jira ticket. Would you like me to create one in the MD board via `tron:jira` before committing? Or proceed without one?

If they say yes, create a minimal ticket (title from work-in-progress context, project MD) and confirm the key before proceeding. If no, proceed. Give them a free-text option to provide their own key they've already created.

## Step 1: Gather state

```bash
git status
git diff
git diff --staged
git log --oneline -5
```

If the working tree is clean and nothing is staged, tell the user and stop.

## Step 2: Analyze and group changes

Read any changed files needed to understand intent. Group by logical concern — one coherent idea per commit (a feature, a fix, a refactor, a config change). Don't split unnecessarily. When in doubt, fewer commits is better.

## Step 3: Generate commit plan

For each group, a conventional commit message:

```
type(scope): description

- key detail
- key detail
```

Types: `feat` `fix` `docs` `style` `refactor` `test` `chore`

Subject under 70 chars, focus on "why" not "what." Reference the Jira key if the branch has one.

## Step 4: Present for approval via AskUserQuestion

Show each commit's message and files. The user can approve, edit messages, regroup, or merge groups. If they edit, use their input verbatim.

## Step 5: Execute

For each group in order:

1. `git add <files>`
2. Commit with a real multi-line heredoc (same pattern as `tron:git-pr` Step 6) — no Co-Authored-By line, no credits:

```bash
git commit -m "$(cat <<'EOF'
<message>
EOF
)"
```

If a commit fails (pre-commit hook), report and stop.

## Step 6: Push

Resolve the branch name independent of the shell's cwd (finds the feature-branch worktree):

```bash
# Find the feature-branch worktree (not the main checkout)
MAIN_WD="$(git rev-parse --git-dir | xargs dirname)"
WORKTREE="$(git worktree list --porcelain | grep -v "^bare:" | awk '{print $1}' | grep -v "^$MAIN_WD\$" | head -1)" || WORKTREE="$MAIN_WD"
BRANCH="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || { echo "error: detached HEAD in $WORKTREE — cannot determine branch" >&2; exit 1; }

# Check if already tracking upstream; if so, plain push. Else use -u.
if git -C "$WORKTREE" rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1; then
  git -C "$WORKTREE" push
else
  git -C "$WORKTREE" push -u origin "$BRANCH"
fi
```

Never force push.

## Step 7: Report

`git log --oneline -N` showing each commit hash and message. Brief confirmation. Then nudge toward `tron:git-dev` or `tron:git-pr` for the next lifecycle stage.