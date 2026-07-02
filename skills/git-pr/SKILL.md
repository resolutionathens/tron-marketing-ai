---
name: git-pr
model: sonnet
effort: medium
description: "Create a pull request from the current feature branch with an auto-generated title and description. Use this skill when the user says 'create a PR', 'open a pull request', 'make a PR', 'submit for review', or anything that implies they want to create a pull request on GitHub."
allowed-tools:
  - Bash
  - Grep
  - Glob
  - Read
  - AskUserQuestion
---

# Pull Request Assistant

Create a PR from the current feature branch with a clear, conventional title and structured body.

## Step 1: Validate branch and tree

```bash
git branch --show-current
git status --porcelain
```

Stop if on master/main/dev/production. If uncommitted changes, suggest `tron:git-commit`.

## Step 2: Push branch

Check tracking: `git status -sb`. If no upstream, `git push -u origin <branch>`. If ahead, `git push`. If up to date, continue.

## Step 3: Gather context

```bash
git log --oneline master..HEAD    # fallback to main..HEAD
git diff master...HEAD --stat
```

Read changed files if needed to understand purpose.

## Step 4: Generate title and body

**Title:** under 70 chars, conventional commit format: `type(scope): description`. Types: `feat` `fix` `docs` `style` `refactor` `test` `chore`.

**Body:**
```
## Summary
- key change

## Test plan
- [ ] test step
```

Reference the Jira key from the branch name if present. No Co-Authored-By or "Generated with" footer.

## Step 5: Get approval

Show the title + body via `AskUserQuestion`. User can approve or edit. If they edit, use verbatim.

## Step 6: Create the PR

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)" --base master
```

## Step 7: Request Copilot code review (best-effort, skip for small doc-only PRs)

Skip the request only when **both** hold, using the `git diff master...HEAD --stat` output
from Step 3:

- every changed file is documentation (`*.md`, `*.mdx`, or a `reference/*.md`) — no `.mjs`,
  `.sh`, `.json`, `.ts`, `.yml`, or other logic/config files touched
- the diff is small: **3 files or fewer** and **40 changed lines or fewer** (insertions +
  deletions, from the `--stat` summary line)

A SKILL.md counts as documentation for this check, but its size and blast radius (it's
instructions an agent executes) still make it easy to blow past the line/file threshold —
don't special-case it lower than the numbers above.

If both hold, skip the request and note in Step 9 that Copilot review was skipped as a
small doc-only change. Otherwise:

```bash
gh pr edit "<N>" --add-reviewer "@copilot" \
  || echo "notice: Copilot review not enabled for this repo/org — continuing"
```

Must never fail the lifecycle. One request at PR open only.

## Step 8: Post retro comment

First resolve and run the token-usage helper — it reads this session's real token
counts from the transcript and prints the footer's token line:

```bash
TOKEN_USAGE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/git/token-usage.sh"
TOKENS="$([ -e "$TOKEN_USAGE" ] && bash "$TOKEN_USAGE")"
```

`$TOKENS` holds a line like `*in 18k · out 8.2k · cache 1.2M read / 40k write*`,
or empty string if the transcript can't be read (it must never block the PR).
Then post the comment in the **same shell** so `$TOKENS` expands:

```bash
gh pr comment "<N>" --body "<!-- tron-retro -->
### Retro
**What went well:**
**Friction / surprises:**
**Follow-up (filed):**
**Out of scope / not filed:**
FOLLOW-UP:

---
*<your model ID>*
$TOKENS"
```

Replace `<your model ID>` with your own exact model ID (e.g. `claude-opus-4-8[1m]`) as **literal text** before running the command. Do not paste a shell variable like `${CLAUDE_MODEL_ID}` for the model ID — Claude Code does not export it to the shell, so it would not expand and the literal `${...}` would end up in the comment. You know your own model ID from your session context; write it in directly. (`$TOKENS` is different — it's set by the helper above and *does* expand, so leave it as the variable.)

The `<!-- tron-retro -->` marker is required for the OS reviewer. Use `FOLLOW-UP:` for work this PR did not do — one per line. Use `<!-- tron-note -->` on any other comment you post on this PR.

## Step 9: Report

Give the user the PR URL. If Step 7 skipped the Copilot request, say so in one line.