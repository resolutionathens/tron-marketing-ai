---
name: git-dev
model: sonnet
effort: low
description: "Merge the current feature branch into the dev branch and push. Use this skill when the user says 'merge to dev', 'push to dev', 'deploy to dev', 'send to dev', or anything that implies they want their feature branch merged into the dev environment branch."
allowed-tools:
  - Bash
  - AskUserQuestion
scout:
  surface: developer
---

# Merge to Dev Assistant

Merge the current clean feature branch into dev, push, and return to the feature branch.

## Fast path (deterministic)

```bash
name=git-dev
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/git-dev.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/git-dev.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/git-dev.sh" ] || { echo "tron:$name: scripts/git-dev.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/git-dev.sh" [feature-branch] [--worktree <abs-path>]
#   feature-branch    defaults to the branch checked out in the worktree
#   --worktree <path> resolve source branch + dirty-check from this path, not $PWD
```

Validates the branch (refuses master/main/dev/staging/production), checks the tree is clean, detects worktree vs checkout, merges into `dev`, pushes, restores your starting state. Only resolves dependency lockfiles (`package.json`, `package-lock.json`, `bun.lock` → `--ours`); any other conflict aborts cleanly — read the conflicting files and resolve with the user.

Use `--worktree` when calling from a worktree-integrated shell where `$PWD` resets to the main checkout after each Bash call.

One JSON line on stdout:

```json
{"ok":true,"branch":"MD-1801-x","target":"dev","pushed":true,"worktree":true,"depsResolved":["package.json"]}
{"ok":false,"branch":"MD-1801-x","target":"dev","error":"conflicts","conflicts":["src/a.ts"]}
{"ok":false,"branch":"MD-1801-x","target":"dev","error":"no-dev-branch"}
```

- `error: dirty-working-tree` → commit/stash first (`tron:git-commit`)
- `error: no-dev-branch` → this repo has no `dev`; open a PR with `tron:git-pr` instead

## If the script reports a conflict

The only auto-resolved conflicts are dependency lockfiles (per project rule: long-lived branches own their dep state). For any other file:

1. Read the conflicting file
2. Show the user the conflict markers and ask how to resolve
3. Run `git add <file>` and `git commit --no-edit` manually after they decide

## Next steps

After the merge: `tron:git-pr` for review, or `tron:git-pushtoprod` to deploy. Clean up with `tron:close-worktree` when done with the ticket.