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

Under dispatch (`TRON_DISPATCH_ID` set) `AskUserQuestion` is not callable — see
[WORKER_CONTRACT.md](../../WORKER_CONTRACT.md) → *Tools and skills unavailable to you*.

What that means here: skip Step 5's approval prompt and proceed straight to Step 6 with the
generated title and body as-is. If something genuinely blocks progress (e.g. the branch has no
resolvable base, or a required detail is missing and can't be inferred from the diff), post ONE
concise plain-text message stating what's needed and stop to wait for the reply, rather than using
`AskUserQuestion`.

## Step 1: Validate branch and tree

```bash
git branch --show-current
git status --porcelain
```

Stop if on master/main/dev/production. If uncommitted changes, suggest `tron:git-commit`.

## Step 1b: Select and run repository-supported verification

Use the bundled selector to choose the current repository's supported local gates. It preserves
the plugin's complete Layer-1 suite when available; otherwise it selects declared package scripts
named `test`, `typecheck`, and `smoke`. The selector reports every selected command before running
it:

```bash
name=git-pr
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/select-verification-gates.sh)"
bash "$SKILL_DIR/scripts/select-verification-gates.sh" --repo-dir "$(pwd)"
```

Stop if a selected test fails. Do not create the PR until every reported gate passes. The plugin's
local macOS Layer-1 gate is intentional: it exercises the real Bash 3.2 and BSD-coreutils runtime
without paying for a GitHub-hosted macOS runner on every PR and `master` push.

If the selector reports that no automatic gates were found, inspect `CLAUDE.md`, `README`, package
scripts, and contribution docs. Announce the exact repository-defined checks selected, run those
that cover the change, and stop on failure. Never substitute or reference the plugin-only Layer-1
script when it is absent.

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

Resolve `owner/repo` from the origin remote — never hardcode a slug, since this plugin ships to
many consuming repos under different orgs:

```bash
SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
[ -n "$SLUG" ] || { echo "error: could not resolve owner/repo from the origin remote" >&2; exit 1; }
```

Write the body to a temp file and pass it via `--body-file`:

```bash
cat > /tmp/.pr-body.md <<'EOF'
<body>
EOF
gh pr create --title "<title>" --body-file /tmp/.pr-body.md --base "$BASE" --head "$BRANCH" --repo "$SLUG"
```

## Steps 7–8: Copilot review + retro comment

Request a Copilot review, wait for it to land, act on it, then post the retro. The mechanics — the
script resolution, the skip arithmetic, the `await-review` status branches, and the retro comment
shape — are in [reference/copilot-review.md](reference/copilot-review.md). Read it before running
this step; what follows is only the part that is your judgment.

- **A PR is not approval-ready the instant it opens.** If a review was requested, wait for it
  (MD-2112), and report the outcome in a status comment. That status is what makes the PR genuinely
  ready for the human gate, and under dispatch it is how the tron-os dashboard learns the PR is
  review-resolved.
- **On review comments:** address the valid ones in the worktree and `tron:git-commit` the fixes so
  they push to the PR branch. Skip any that are wrong or out of scope, and say which ones and why.
- **When no automated review ran** (skipped, timed out, or errored), say so prominently rather than
  proceeding quietly. The human gate is then the only review that happened.
- **The retro sections are yours to write.** Use `FOLLOW-UP:` for work this PR deliberately did not
  do, one per line.

If the bundled script cannot be resolved, follow the
[manual review fallback](reference/manual-review-fallback.md).

## Step 9: Report

Give the user the PR URL. If Step 7 skipped the Copilot request, say so in one line.
If Step 7b ran, report the Copilot outcome too — "no comments", "N comment(s)
addressed", or "no automated review ran (skipped/timed out/error), proceeded to
the human gate" — since that is what makes the PR genuinely ready for the human
approval gate.
