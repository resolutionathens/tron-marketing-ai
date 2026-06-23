---
name: git-pr
model: sonnet
effort: medium
description: "Create a pull request from the current feature branch with an auto-generated title and description. Use this skill when the user says 'create a PR', 'open a pull request', 'make a PR', 'submit for review', or anything that implies they want to create a pull request on GitHub. Also trigger when the user says 'PR this', 'put up a PR', or asks to get their branch reviewed."
allowed-tools:
  - Bash
  - Grep
  - Glob
  - Read
  - AskUserQuestion
---

# Pull Request Assistant

Create a PR from the current feature branch with a clear, conventional title and structured body.

## Step 1: Validate current branch

Run `git branch --show-current`.

**Stop if** the current branch is `master`, `main`, `dev`, or `production` — the user must be on a feature branch.

## Step 2: Ensure clean working tree

Run `git status --porcelain`.

If there are uncommitted changes, tell the user to commit or stash first. Suggest they use the tron:git-commit skill.

## Step 3: Ensure branch is pushed

Run `git status -sb` to check tracking.

- No upstream → `git push -u origin <branch-name>`
- Ahead of remote → `git push`
- Up to date → continue

## Step 4: Gather context

Run in parallel:

```bash
git log --oneline master..HEAD    # fall back to main..HEAD
git diff master...HEAD --stat     # fall back to main...HEAD
```

Read relevant changed files if needed to understand the purpose of the changes.

## Step 5: Generate PR title and body

**Title:**
- Under 70 characters
- Conventional commit format: `type(scope): description`
- Example: `feat: add responsive navigation menu`

**Types:**
- `feat` - New feature, component, or functionality
- `fix` - Bug fix or error correction
- `docs` - Documentation changes
- `style` - Formatting, code style (not CSS)
- `refactor` - Code cleanup without behavior change
- `test` - Test additions or changes
- `chore` - Config, tooling, dependencies

Ensure the title accurately reflects the nature of the changes — "add" means a wholly new feature, "update" means an enhancement, "fix" means a bug fix.

**Body:**
```
## Summary
- bullet point 1
- bullet point 2

## Test plan
- [ ] test step 1
- [ ] test step 2
```

Reference issue numbers in the summary if applicable (e.g., from the branch name like `MD-1660`).

**Do NOT include any Co-Authored-By line, credits, or "Generated with" footer.**

## Step 6: Get user approval

Use `AskUserQuestion` to show the generated title and body. The user can approve or edit. If they edit, use their input verbatim.

## Step 7: Create the PR

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body here>
EOF
)"
```

Target `master` by default unless the user specifies a different base branch.

## Step 8: Request a Copilot code review (best-effort)

Right after the PR is created, request a **GitHub Copilot code review** on it. The point is to get an automated reviewer in the loop on every agent-opened PR: Copilot's findings land alongside the human's, so a parked worker can start addressing them immediately.

This step is **best-effort and must never fail the lifecycle.** The PR is already open by the time this runs — if the request errors for any reason (Copilot review not enabled for the repo/org, the bot is not assignable, an older `gh`), log a one-line notice and continue. Do **not** hard-fail or roll anything back.

**Mechanism (verified against `gh` 2.94.0, the GitHub-documented path):** use the `gh` CLI's built-in `@copilot` reviewer alias. `gh` resolves `@copilot` to the Copilot reviewer bot itself (no GraphQL node-id lookup or REST `requested_reviewers` plumbing to maintain), and `gh pr edit --help` documents the alias directly: *"Use `@copilot` to request review from Copilot."*

```bash
# Replace "<N>" with the PR number or URL returned by `gh pr create` in Step 7.
# Keep it quoted — an unquoted <N> is parsed by the shell as a stdin redirection.
gh pr edit "<N>" --add-reviewer "@copilot" \
  || echo "notice: could not request a Copilot review (Copilot code review may not be enabled for this repo/org, or this gh is too old) — continuing; the PR is already open."
```

**Prerequisite — Copilot code review must be enabled for the repo/org.** It is a paid Copilot feature (Copilot Pro/Business/Enterprise with code review turned on). Where it is enabled, a Copilot review is requested and appears in the PR's reviewers. Where it is **not** enabled, the command exits non-zero, the `||` branch logs the notice above, and the step is a clean no-op — the PR still opens and the worker still parks for human review.

**Scope: request once, at PR open only.** Do not re-request a Copilot review on later pushes to the same branch — a single request at open is the entire scope, which avoids review-comment spam. Copilot re-reviews new commits on its own per the repo's settings; this skill never re-triggers it.

> Inherited by the orchestrator: `tron:ship-ticket` (and any other whole-lifecycle driver) reaches PR open by delegating to this skill, so the Copilot request flows through automatically — no separate change in those skills.

## Step 9: Report

Show the PR URL returned by `gh pr create`. Note whether the Copilot review was requested or the step was a logged no-op.

## Next steps

After the PR is merged, remind the user:
- **Deploy:** Use **tron:git-pushtoprod** to merge master into staging and production
- **Update the ticket:** offer **tron:jira-comment** to post a short progress note with the PR link
- **Clean up worktree** (if working in one): use `wt remove` or the **tron:close-worktree** skill
