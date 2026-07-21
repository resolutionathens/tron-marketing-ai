---
name: git-pr
model: sonnet
effort: medium
fallback:
  cost: low
  skip_when: "Use tron:git-pr only when a PR needs creating. For doc-only or trivial changes, verify and skip directly."
  stage_skips:
    - stage: "Steps 7-8 — Copilot review + retro comment"
      skip_when: "PR is doc-only, trivial, or Copilot review is unavailable"
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

## When dispatched (worker mode)

If `TRON_DISPATCH_ID` is set, this skill is running as a non-interactive dispatched worker — never
call `AskUserQuestion`. Skip Step 5's approval prompt and proceed straight to Step 6 with the
generated title and body as-is. If something genuinely blocks progress (e.g. the branch has no
resolvable base, or a required detail is missing and can't be inferred from the diff), post ONE
concise plain-text message stating what's needed and stop to wait for the reply, rather than using
`AskUserQuestion`.

Interactive users are unaffected — this section only changes behavior when `TRON_DISPATCH_ID` is set.

## Step 1: Validate branch and tree

```bash
git branch --show-current
git status --porcelain
```

Stop if on master/main/dev/production. If uncommitted changes, suggest `tron:git-commit`.

## Step 2: Push branch

Check tracking: `git status -sb`. Resolve the branch name once, independent of the shell's cwd
(works even if cwd has reset to main checkout):

```bash
# Find the feature-branch worktree (not the main checkout)
MAIN_WD="$(git rev-parse --git-dir | xargs dirname)"
WORKTREE="$(git worktree list --porcelain | grep -v "^bare:" | awk '{print $1}' | grep -v "^$MAIN_WD\$" | head -1)" || WORKTREE="$MAIN_WD"
BRANCH="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || { echo "error: detached HEAD in $WORKTREE — cannot determine branch" >&2; exit 1; }
```

If no upstream, `git push -u origin "$BRANCH"`. If ahead, `git push`. If up to date, continue.

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

`$BASE` is the default branch resolved in Step 3 and `$BRANCH` from Step 2 — both must be resolved
in the current shell. If this runs in a fresh shell, re-run both Step 2's branch resolver and
Step 3's base resolver before creating the PR.

Write the body to a temp file first, then pass it via `--body-file` — this avoids
silent `gh pr create` failures when the body contains single quotes, backticks, or
other shell-sensitive characters (see MD-1907 retro):

```bash
cat > /tmp/.pr-body.md <<'EOF'
<body>
EOF
gh pr create --title "<title>" --body-file /tmp/.pr-body.md --base "$BASE" --head "$BRANCH"
```

## Steps 7–8: Copilot review + retro comment (scripted)

The mechanics — the doc-only skip arithmetic, the token-usage lookup, and the
marker-comment assembly — live in the bundled `git-pr-retro.sh`. Resolve it once:

```bash
name=git-pr
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/git-pr-retro.sh" ] || SKILL_DIR="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 5 -type d -path "*/skills/$name" 2>/dev/null | while read -r d; do [ -e "$d/scripts/git-pr-retro.sh" ] && echo "$d"; done | sort -V | tail -1 || true)"
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

**Step 7b — wait for Copilot's review, then report status (MD-2112).** A PR is
**not** approval-ready the instant it opens — if a Copilot review was requested
(`requested:true` above), you must wait for that review to actually land before
handing off to the human approval gate. Skip this step only when Step 7 skipped
the request or returned `requested:false`.

```bash
bash "$SKILL_DIR/scripts/git-pr-retro.sh" await-review --pr "<N>"
```

Polls until Copilot posts its review (default: up to 10 min, every 20s — tighter,
120s, for a dispatched worker with `TRON_DISPATCH_ID` set, unless you pass
`--timeout` yourself; tune with `--timeout`/`--interval` seconds). It prints one
JSON line — branch on `status`:

- **`skipped`** — the operator set `TRON_COPILOT_UNAVAILABLE` (e.g. during a
  known Copilot outage) so the poll was skipped entirely; no gh calls were made
  (MD-2194). Treat exactly like `timeout` below for the status comment.
- **`commented`** — Copilot left inline comments (in `comments[]`, each with
  `path`/`line`/`body`). Read them, **address the valid ones in the worktree**,
  then `tron:git-commit` the fixes so they push to the PR branch. Skip any that
  are wrong or out of scope, and say which in your status. Then post a status
  comment: `Copilot review: N comment(s), addressed in <short-sha>` (or note the
  ones you deliberately left), ending with the `<!-- tron-note -->` marker.
- **`no-comments`** — Copilot reviewed and had nothing to flag. Post a one-line
  `Copilot review: no comments` status comment with the `<!-- tron-note -->`
  marker. No code changes.
- **`timeout`** / **`error`** / **`skipped`** — no automated review ran (Copilot
  never posted within the window, the wait couldn't run at all, or an operator
  flagged it unavailable). Do **not** hang, retry, or proceed silently — post a
  prominent status comment so the human gate is unmistakably the only review
  that happened: `**No automated review ran** — <reason>. Proceeding to the
  human approval gate.` (fill `<reason>` from the JSON's `reason` field; use
  `<!-- tron-note -->`).

Post the status comment with `gh pr comment "<N>" --body-file <tmp>` (write the
body to a unique `mktemp` file first — never inline `--body` — per the retro
note above). Only after this status is reported is the PR genuinely ready for the
human approval gate. When dispatched (`TRON_DISPATCH_ID` set), this status comment
is also how the tron-os dashboard learns the PR is review-resolved.

**Step 8 — retro comment.** Write the filled-in retro sections (this is your
judgment) to a fresh, unique temp file — never a fixed name, which risks
posting a stale draft left over from a prior PR — then post and clean up:

```bash
RETRO_BODY="$(mktemp /tmp/tron-retro-body.XXXXXX.md)"
cat > "$RETRO_BODY" <<'EOF'
**What went well:**
**Friction / surprises:**
**Follow-up (filed):**
**Out of scope / not filed:**
FOLLOW-UP:
EOF
bash "$SKILL_DIR/scripts/git-pr-retro.sh" retro-comment --pr "<N>" \
  --model "<your model ID>" --body-file "$RETRO_BODY" && rm -f "$RETRO_BODY"
```

The script adds the `<!-- tron-retro -->` marker (required for the OS reviewer),
the `### Retro` header, and the footer: the `*<model ID>*` line plus this session's
real token line from `tools/git/token-usage.sh` (empty token data never blocks the
comment).

Replace `<your model ID>` with your own exact model ID (e.g. `claude-opus-4-8[1m]`) as **literal text**. Do not paste a shell variable like `${CLAUDE_MODEL_ID}` — Claude Code does not export it to the shell, so the literal `${...}` would end up in the comment. You know your own model ID from your session context; write it in directly.

Use `FOLLOW-UP:` for work this PR did not do — one per line. Use `<!-- tron-note -->` on any other comment you post on this PR.

If the bundled script cannot be resolved, follow the [manual review fallback](reference/manual-review-fallback.md).

## Step 9: Report

Give the user the PR URL. If Step 7 skipped the Copilot request, say so in one line.
If Step 7b ran, report the Copilot outcome too — "no comments", "N comment(s)
addressed", or "no automated review ran (skipped/timed out/error), proceeded to
the human gate" — since that is what makes the PR genuinely ready for the human
approval gate.
