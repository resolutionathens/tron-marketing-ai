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

## Step 8: Report

Show the PR URL returned by `gh pr create`.

## Next steps

After the PR is merged, remind the user:
- **Deploy:** Use **tron:git-pushtoprod** to merge master into staging and production
- **Clean up worktree** (if working in one): use `wt remove` or the **tron:close-worktree** skill
