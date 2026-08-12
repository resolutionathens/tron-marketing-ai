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

## Step 1c: Run the local code review — BEFORE the PR exists

Code review happens **on this machine, before the pull request opens** (MD-2745). Nothing reviews
the PR after it opens. Run the review here, while you still own the branch:

```bash
bun run review:local --verified "<a check you already ran green in Step 1b>"
```

`--verified` is repeatable — pass each gate Step 1b ran green (e.g.
`--verified "bun run test: 4774 pass, 0 fail"`) so the reviewer spends its budget reading code
instead of re-running what you already proved.

This applies **under dispatch** (`TRON_DISPATCH_ID` set) and is run from the Scout/tron-os checkout
that defines the script. Outside a dispatch the command exits 2 — an interactive run has no local
review, and the human reviewing the PR is the only review that happens. Say so in Step 8.

Branch on the exit code — it is your instruction, not a status:

- **0 — settled.** Continue to Step 2.
- **1 — findings to address.** Fix the valid ones in the worktree, then record a disposition for
  **every** round-one finding, including the ones you disagree with:

  ```bash
  bun run review:disposition --finding <id> --fixed|--skipped|--disagreed --note "<what you did, or why not>"
  ```

  `review:local` prints the exact invocation under each finding — copy it, don't compose it. Then
  re-run `bun run review:local` once. **There is exactly one fix-and-re-review cycle and no third
  round:** whatever round two returns, you proceed to the PR.
- **2 — the review could not run at all** (no dispatch env, control plane unreachable). This is
  **not** a clean review. Do not represent it as one; report it in Step 8.

A silent fix is worse than a disagreement — it destroys the round-one/round-two comparison that the
second review exists to make.

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
