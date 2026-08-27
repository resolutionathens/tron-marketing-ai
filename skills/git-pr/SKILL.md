---
name: git-pr
model: sonnet
effort: medium
fallback:
  cost: low
  skip_when: "Use tron:git-pr only when a PR needs creating. For doc-only or trivial changes, verify and skip directly."
  stage_skips:
    - stage: "Step 7 — retro comment"
      skip_when: "PR is doc-only or trivial"
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
BRANCH="$(git branch --show-current)"
git status --porcelain

name=git-pr
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/resolve-jira-key.sh)"
JIRA_KEY="$(bash "$SKILL_DIR/scripts/resolve-jira-key.sh" "$BRANCH")" || exit $?
```

Stop if on master/main/dev/production. If uncommitted changes, suggest `tron:git-commit`.
The Jira-key resolver stops and names any branch that does not follow the required `<KEY>-<slug>`
convention. Do not continue to verification or open a PR after that failure.

## Step 1b: Select and run repository-supported verification

Use the bundled selector to choose the current repository's supported local gates. It preserves
the plugin's complete Layer-1 suite when available, then validates real native Claude/Codex package
installations and the current branch's release boundary against `origin/master`. For consuming
repositories it selects declared package scripts named `test`, `typecheck`, and `smoke`. The
selector reports every selected command before running it:

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

## Step 1c: Run the local code review — BEFORE the PR exists

Code review happens **on this machine, before the pull request opens** (MD-2745). Nothing reviews
the PR after it opens. Run the review here, while you still own the branch.

Resolve the bundled client, then run one round. It reaches the control plane over
`TRON_API_URL`, so it works from **any** repo's worktree — you do not need a tron-os checkout
(MD-2749):

```bash
name=git-pr
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-plugin-root.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-plugin-root.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
REVIEW="$(bash "$RESOLVER" "$name" tools/review/review.mjs)/tools/review/review.mjs"

node "$REVIEW" local --verified "<a check you already ran green in Step 1b>"
```

`--verified` is repeatable — pass each gate Step 1b ran green (e.g.
`--verified "bun run test: 4774 pass, 0 fail"`) so the reviewer spends its budget reading code
instead of re-running what you already proved. It is passed as a **claim**, not proof.

This applies **under dispatch** (`TRON_DISPATCH_ID` set). Outside a dispatch the command exits 2 —
an interactive run has no local review, and the human reviewing the PR is the only review that
happens. Say so in Step 8.

Branch on the exit code — it is your instruction, not a status:

- **0 — settled.** Continue to Step 2.
- **1 — findings to address in round 1 or 2.** Fix the valid ones in the worktree, then record a
  disposition for **every** finding from that round, including the ones you disagree with:

  ```bash
  node "$REVIEW" disposition --finding <id> --fixed|--skipped|--disagreed --note "<what you did, or why not>"
  ```

  The review prints the exact invocation under each finding — copy it, don't compose it. Verify the
  affected behavior, then re-run `node "$REVIEW" local` for the next round. The live gate permits
  **three** rounds: rounds one and two require this remediation and disposition loop.
- **1 — findings to address in round 3.** Fix every actionable finding and unmet criterion, run the
  affected tests and verification ladder, then record repair plus verification evidence for every
  final-round target before PR registration:

  ```bash
  node "$REVIEW" remediation --target <finding:id|criterion:text> --repair "<what changed>" --verification "<command and passing result>"
  ```

  A non-passing third round is a remediation list, not permission to park. **There is no fourth
  round.** Do not create the PR until the final-remediation evidence is recorded.
- **1 — terminal review failed with no repair targets.** Only when the control plane records a
  failed terminal review with no finding or unmet criterion, record its reason and verification:

  ```bash
  node "$REVIEW" recovery --failed-review-reason "<why the terminal review failed without a target>" --verification "<command and passing result>"
  ```

  Do not use recovery to bypass a final-round finding or unmet criterion. Do not create the PR
  until this recovery evidence is recorded.
- **2 — the review could not run at all** (no dispatch env, control plane unreachable). This is
  **not** a clean review. Do not represent it as one; report it in Step 8.

A silent fix is worse than a disagreement — it destroys the round-one/round-two comparison that the
second review exists to make.

## Step 2: Push branch

Check tracking: `git status -sb`. Resolve the branch name from the current worktree:

```bash
# Resolve the linked worktree containing the current directory.
WORKTREE="$(git rev-parse --show-toplevel)"
BRANCH="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || { echo "error: detached HEAD in $WORKTREE — cannot determine branch" >&2; exit 1; }
```

Use a plain push only when the upstream's branch name matches `$BRANCH`; an
inherited differently named upstream must be replaced with the branch's own
remote tracking branch:

```bash
UPSTREAM="$(git -C "$WORKTREE" rev-parse --abbrev-ref "@{u}" 2>/dev/null || true)"
if [ "${UPSTREAM#*/}" = "$BRANCH" ]; then
  git -C "$WORKTREE" push
else
  git -C "$WORKTREE" push -u origin "$BRANCH"
fi
```

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

**Title:** under 70 characters including the Jira key, in the exact format
`type(scope): description (KEY-1234)`. Use `$JIRA_KEY`, derived from the branch in Step 1, for the
parenthesized suffix. Types: `feat` `fix` `docs` `style` `refactor` `test` `chore`. If the complete
title would exceed 70 characters, shorten the description; never shorten or drop the Jira key.

**Body:**
```
## Summary
- key change

## Test plan
- [ ] test step
```

Reference `$JIRA_KEY` in the body too, so the ticket appears in both the title and body. No
Co-Authored-By or "Generated with" footer.

## Step 5: Get approval

Show the title + body via `AskUserQuestion`. User can approve or edit. If they edit, use verbatim.

## Step 6: Create the PR

`$BASE` is the default branch resolved in Step 3; `$BRANCH` and `$JIRA_KEY` come from Steps 1 and 2.
All three must be resolved in the current shell. If this runs in a fresh shell, re-run Step 1's
branch and Jira-key resolution, Step 2's worktree-aware branch resolver, and Step 3's base resolver
before creating the PR.

Resolve `owner/repo` from the `origin` remote itself (not gh's implicit cwd-based remote
selection) — never hardcode a slug, since this plugin ships to many consuming repos under
different orgs. Use the bundled `resolve-origin-slug.sh` rather than an inline `[[ =~ ]]`/
`BASH_REMATCH` block: zsh populates regex capture groups differently than bash, so that
construct silently produced an empty `SLUG` when this skill ran under a zsh default shell
(MD-2661) — the bundled script uses `case`/parameter expansion instead, which behaves
identically under bash and zsh (verified by its `test-resolve-origin-slug.sh` sibling, run
under both shells):

```bash
name=git-pr
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/resolve-origin-slug.sh)"
SLUG="$(bash "$SKILL_DIR/scripts/resolve-origin-slug.sh")"
```

Write the body to a temp file and pass it via `--body-file`:

```bash
PR_BODY="$(mktemp "${TMPDIR:-/tmp}/tron-pr-body.XXXXXX")"
trap 'rm -f "$PR_BODY"' EXIT
cat > "$PR_BODY" <<'EOF'
<body>
EOF
gh pr create --title "<title>" --body-file "$PR_BODY" --base "$BASE" --head "$BRANCH" --repo "$SLUG"
```

## Step 7: Retro comment

**No automated review arrives after the PR opens.** Do not request a reviewer, do not poll for one,
and do not wait — the review already happened in Step 1c, and both of its rounds are posted to the
PR by the control plane as a single structured comment. A wait here would never terminate, which is
worse than no instruction at all: the worker looks busy while it is stuck.

Post the retro, then **park for the human approval gate**. That gate is the only thing that
authorises a merge, and it is unchanged.

The mechanics — script resolution and the retro comment shape — are in
[reference/retro-comment.md](reference/retro-comment.md). What follows is the part that is your
judgment:

- **The retro sections are yours to write.** Use `FOLLOW-UP:` for work this PR deliberately did not
  do, one per line.
- **If Step 1c's review did not run** (exit 2), say so prominently rather than proceeding quietly.
  The human gate is then the only review that happened.

If the bundled script cannot be resolved, follow the
[manual retro fallback](reference/manual-review-fallback.md).

## Step 8: Report

Give the user the PR URL, then state the Step 1c review outcome in one line — "local review settled
(N finding(s) addressed)", "local review settled, no findings", or "**no local review ran** —
<reason>; the human gate is the only review that happened."

Then stop. The PR is parked at the human approval gate; do not merge, do not promote, and do not go
looking for more work.
