---
name: git-dev
model: sonnet
effort: low
description: "Merge the current feature branch into the dev branch and push. Use this skill when the user says 'merge to dev', 'push to dev', 'deploy to dev', 'send to dev', or anything that implies they want their feature branch merged into the dev environment branch."
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Merge to Dev Assistant

Merge the current clean feature branch into dev, push, and return to the feature branch. Works from both regular checkouts and worktrees.

## Fast path (deterministic)

This whole flow is mechanical — run the bundled script instead of the steps below:

```bash
# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=git-dev
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains scripts/git-dev.sh
# (skips a stale mirror that lacks it; newest version wins, marketplace breaks ties)
[ -e "$SKILL_DIR/scripts/git-dev.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/git-dev.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/git-dev.sh" ] || { echo "tron:$name: can't find scripts/git-dev.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/git-dev.sh" [feature-branch]   # defaults to the current branch
```

It validates the branch (refuses master/main/dev/staging/production), checks the
working tree is clean, detects worktree-vs-checkout, merges the feature into `dev`,
pushes, and restores your starting state. The **only** conflict it resolves is
`package.json`/`package-lock.json` (→ `--ours`, per the project rule that the
long-lived branches own their dependency state); **any other conflict aborts the
merge cleanly and is handed back to you** — read the conflicting files, resolve with
the user, and don't re-run blindly.

It prints one JSON line on stdout (narration on stderr):

```json
{"ok":true,"branch":"MD-1801-x","target":"dev","pushed":true,"worktree":true,"depsResolved":["package.json"]}
{"ok":false,"branch":"MD-1801-x","target":"dev","error":"conflicts","conflicts":["src/a.ts"]}
```

`ok:false` with `"error":"dirty-working-tree"` means commit/stash first (tron:git-commit).
Smoke it any time with `bash "$SKILL_DIR/scripts/test-git-dev.sh"`. The steps below
are the explanation / manual fallback for when the script reports a conflict.

## Step 1: Validate current branch

Run `git branch --show-current`.

**Stop if** the current branch is `master`, `main`, `dev`, or `production` — the user must be on a feature branch.

## Step 2: Ensure clean working tree

Run `git status --porcelain`.

If there are uncommitted changes, tell the user to commit or stash first. Suggest they use the tron:git-commit skill.

## Step 3: Detect worktree vs regular checkout

```bash
MAIN_REPO=$(git rev-parse --path-format=absolute --git-common-dir | sed 's/\/.git$//')
CURRENT_DIR=$(pwd)
```

If `MAIN_REPO` and `CURRENT_DIR` are different, you're in a worktree. The dev branch needs to be checked out from the main repo, not the worktree.

## Step 4: Merge into dev

**From a worktree:**
```bash
git -C "$MAIN_REPO" checkout dev
git -C "$MAIN_REPO" pull
git -C "$MAIN_REPO" merge <feature-branch-name>
git -C "$MAIN_REPO" push
```

**From a regular checkout:**
```bash
git checkout dev
git pull
git merge <feature-branch-name>
git push
```

If the merge fails due to conflicts, check which files conflicted:

- **`package.json` and `package-lock.json`** — always keep dev's version. These files should never be updated by feature-branch merges into dev or staging; those branches manage their own dependency state. Resolve automatically:
  ```bash
  git -C "$MAIN_REPO" checkout --ours package.json package-lock.json
  git -C "$MAIN_REPO" add package.json package-lock.json
  ```
  (omit `-C "$MAIN_REPO"` from a regular checkout.)

- **Any other file** — stop and tell the user. Do NOT attempt to resolve other conflicts automatically.

After resolving package file conflicts, continue the merge with `git commit --no-edit`, then push.

Never force push. If the push fails, report the error and stop.

## Step 5: Return to previous state

**From a worktree:** Return the main repo to master:
```bash
git -C "$MAIN_REPO" checkout master
```
The worktree is still on the feature branch — no action needed there.

**From a regular checkout:**
```bash
git checkout <feature-branch-name>
```

## Step 6: Report

Tell the user:
- The feature branch that was merged
- Confirmation that dev is updated and pushed
- That they're back on their feature branch (or still in their worktree)

## Next steps

After testing on dev, remind the user:
- **Ready for review?** Use the **tron:git-pr** skill to create a PR back to master
- **After PR is merged?** Use **tron:git-pushtoprod** to deploy master to staging and production
- **Done with this ticket?** Clean up the worktree:
  ```
  git worktree remove ../<branch-name>
  ```
