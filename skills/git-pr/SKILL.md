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
scout:
  surface: developer
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

Resolve the default branch **once** here and reuse it for the diff and for
`--base` in Step 6:

```bash
BASE="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)"; BASE="${BASE:-master}"
git log --oneline "$BASE..HEAD"
git diff "$BASE...HEAD" --stat
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

`$BASE` is the default branch resolved in Step 3 — if this runs in a fresh shell,
re-run the Step 3 resolver line first.

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)" --base "$BASE"
```

## Steps 7–8: Copilot review + retro comment (scripted)

The mechanics — the doc-only skip arithmetic, the token-usage lookup, and the
marker-comment assembly — live in the bundled `git-pr-retro.sh`. Resolve it once:

```bash
name=git-pr
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/git-pr-retro.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/git-pr-retro.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/git-pr-retro.sh" ] || { echo "tron:$name: scripts/git-pr-retro.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
```

**Step 7 — Copilot review (best-effort, skipped for small doc-only PRs):**

```bash
bash "$SKILL_DIR/scripts/git-pr-retro.sh" skip-check --pr "<N>"
```

Prints `{"skip":bool,"reason":"..."}` (doc = `*.md`/`*.mdx` only; small = ≤3 files
and ≤40 changed lines). A SKILL.md counts as documentation, but its blast radius
(it's instructions an agent executes) still makes it easy to blow past the
thresholds — don't special-case it lower. If `skip` is true, skip the request and
note it in Step 9. Otherwise:

```bash
bash "$SKILL_DIR/scripts/git-pr-retro.sh" request-review --pr "<N>"
```

Never fails the lifecycle (an org without Copilot review returns `requested:false`,
exit 0). One request at PR open only.

**Step 8 — retro comment.** Write the filled-in retro sections (this is your
judgment) to a temp file, then post:

```bash
cat > /tmp/tron-retro-body.md <<'EOF'
**What went well:**
**Friction / surprises:**
**Follow-up (filed):**
**Out of scope / not filed:**
FOLLOW-UP:
EOF
bash "$SKILL_DIR/scripts/git-pr-retro.sh" retro-comment --pr "<N>" \
  --model "<your model ID>" --body-file /tmp/tron-retro-body.md
```

The script adds the `<!-- tron-retro -->` marker (required for the OS reviewer),
the `### Retro` header, and the footer: the `*<model ID>*` line plus this session's
real token line from `tools/git/token-usage.sh` (empty token data never blocks the
comment).

Replace `<your model ID>` with your own exact model ID (e.g. `claude-opus-4-8[1m]`) as **literal text**. Do not paste a shell variable like `${CLAUDE_MODEL_ID}` — Claude Code does not export it to the shell, so the literal `${...}` would end up in the comment. You know your own model ID from your session context; write it in directly.

Use `FOLLOW-UP:` for work this PR did not do — one per line. Use `<!-- tron-note -->` on any other comment you post on this PR.

**Manual fallback** (if the bundled script can't be resolved): skip the Copilot
request only for doc-only diffs (`*.md`/`*.mdx`, ≤3 files, ≤40 changed lines from
Step 3's `--stat`); else `gh pr edit "<N>" --add-reviewer "@copilot" || true`. For
the retro, run `tools/git/token-usage.sh` into `$TOKENS` and, in the same shell,
`gh pr comment "<N>" --body "<!-- tron-retro -->..."` with the sections above, a
`---`, the literal model ID, and `$TOKENS`.

## Step 9: Report

Give the user the PR URL. If Step 7 skipped the Copilot request, say so in one line.