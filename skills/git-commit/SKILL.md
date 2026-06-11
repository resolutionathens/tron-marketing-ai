---
name: git-commit
description: "Stage, commit, and push changes with auto-generated conventional commit messages. Produces atomic commits — when changes span multiple concerns, they're split into separate focused commits rather than one large dump. Use this skill when the user says 'commit', 'commit and push', 'save my changes', 'push this up', or anything that implies they want to commit their current work. Also trigger when the user asks to 'ship it', 'wrap this up', or wants to finalize changes they've been working on."
allowed-tools:
  - Bash
  - Grep
  - Glob
  - Read
  - AskUserQuestion
---

# Git Commit Assistant

Analyze changes, group them into atomic commits by logical concern, get user approval, commit, and push.

The goal is a clean, readable git history. Each commit should represent one coherent idea — a feature, a fix, a refactor, a config change. This makes reviews easier, bisecting possible, and reverts safe.

## Step 1: Gather state

Run these in parallel:

```bash
git status
git diff
git diff --staged
git log --oneline -5
```

If the working tree is clean and nothing is staged, tell the user and stop.

## Step 2: Analyze and group changes

Look at every modified, added, and deleted file. Understand what each change does — read files if needed to understand the purpose, not just the path.

**Group by logical concern, not by file type or directory.** A component and its types file that serve the same feature belong in one commit. A config change and a component change that are unrelated belong in separate commits.

Examples of good grouping:
- A blog post `.md` file + its front matter image → one commit
- A new component + its types + the page that uses it → one commit (they serve one feature)
- A typo fix in a README + a dependency bump in package.json → two commits (unrelated)
- A nav refactor touching 8 files → one commit (one concern, many files is fine)

**When to split vs keep together:**
- Split when changes serve genuinely different purposes — a bug fix mixed with a feature addition, content updates alongside tooling changes, etc.
- Keep together when multiple files serve one purpose — even if they span directories. A rename touching 15 files is one commit. A feature touching a component, its composable, and a page is one commit.
- When in doubt, fewer commits is better than too many. Over-splitting creates noise.

**If all changes serve a single concern**, skip grouping and go straight to Step 3 with a single commit — don't force a split.

## Step 3: Generate commit plan

For each group, generate a conventional commit message:

```
type(scope): description

- key change 1
- key change 2
```

**Types:**
- `feat` - New feature, component, or functionality
- `fix` - Bug fix or error correction
- `docs` - Documentation changes
- `style` - Formatting, code style (not CSS)
- `refactor` - Code cleanup without behavior change
- `test` - Test additions or changes
- `chore` - Config, tooling, dependencies

Ensure each message accurately reflects the nature of its changes — "add" means a wholly new feature, "update" means an enhancement to an existing feature, "fix" means a bug fix.

Rules:
- Subject line under 70 characters
- Focus on "why" not "what" (the code shows "what")
- Use bullet points for multi-line descriptions
- Reference issue numbers if visible in branch name or changes (e.g., MD-1660)

## Step 4: Present plan for approval

Use `AskUserQuestion` to show the full commit plan. For each proposed commit, show:
- The commit message
- The files included

If there's only one commit, just show the message.

The user can:
- Approve the plan as-is
- Edit messages, regroup files, merge groups, or split further
- Provide replacement text via the free-text option

If they edit, use their input verbatim.

## Step 5: Execute commits

For each group in the approved plan, in order:

1. Stage only the files for that group: `git add <file1> <file2> ...`
2. Commit with a HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
<message here>
EOF
)"
```

**Do NOT append any Co-Authored-By line. No credits. Just the message.**

If a commit fails (e.g., pre-commit hook), report the error and stop. Do not continue to the next group.

## Step 6: Push

Run `git push` once after all commits are made.

- If no upstream tracking branch exists, use `git push -u origin <current-branch>`.
- Never force push. If the push fails, report the error and stop.

## Step 7: Report

Show a summary of all commits made:
- Each commit hash and message (`git log --oneline -N` where N is the number of commits)
- Push result
- Brief confirmation
