---
name: git-pushtoprod
model: sonnet
effort: low
description: "Promote master to production — merging through staging first when the repo has a staging branch, otherwise master→production directly. Use this skill when the user says 'push to prod', 'deploy to production', 'push to staging and production', 'ship to prod', or anything that implies they want master deployed to the production (and staging) branches."
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Deploy to Production Assistant

Promote master to production — through `staging` first when it exists, otherwise straight to `production`.

## Fast path (deterministic)

```bash
name=git-pushtoprod
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/git-pushtoprod.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/git-pushtoprod.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/git-pushtoprod.sh" ] || { echo "tron:$name: scripts/git-pushtoprod.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/git-pushtoprod.sh" [--no-jira] [--key <TICKET>] [--worktree <abs-path>]
```

Use `--worktree` when calling from a worktree-integrated shell where `$PWD` resets to the main checkout after each Bash call — the dirty-check, starting branch, and Jira-key parsing then use that path instead of `$PWD` (same convention as `tron:git-dev`).

Checks clean tree, brings master current, merges through staging → production (or just production if no staging branch), pushes each, transitions the Jira ticket to Done. Stops at the first failed environment — production is never touched if staging fails. Lockfile conflicts resolve to `--ours`; any other conflict aborts.

One JSON line on stdout:

```json
{"ok":true,"staging":true,"production":true,"jira":"MD-1801:Done"}
{"ok":true,"staging":"skipped","production":true,"jira":"MD-1801:Done"}
{"ok":false,"staging":false,"production":false,"error":"staging-conflicts","conflicts":["src/a.ts"]}
```

The Jira key is parsed from the branch; `--no-jira` skips the transition. `staging` field is `true`/`false` when the repo has a staging branch, or `"skipped"` when it has none.

> **Tier reminder:** production deploy is high-risk. The script is the mechanics; the decision to run it stays with the human/PR gate — don't invoke autonomously.

## If the script reports a conflict

Only dependency lockfiles are auto-resolved. For other conflicts, show the conflicting files to the user and ask how to resolve. Then `git add <file>` and `git commit --no-edit` manually.

## Manual fallback (if the bundled script can't be resolved)

High-risk — confirm with the user first. Resolve `<default>` (`master` or `main`), then promote through `staging` when that branch exists, else straight to `production`:

```bash
git checkout <default> && git pull --ff-only
for env in staging production; do
  git rev-parse --verify "origin/$env" >/dev/null 2>&1 || continue   # skip staging if the repo has none
  git checkout "$env" && git merge "<default>" --no-edit \
    || { echo "conflict on $env — STOP; never push production if staging failed"; break; }
  git push origin "$env"
  git checkout <default>
done
```

Stop at the first failed environment — production is never touched if staging fails. Lockfile conflicts resolve to `--ours` (`git checkout --ours <lockfile> && git add <lockfile>`); any other conflict aborts. Then transition the ticket (the branch's `<KEY>`), unless the user asked to skip it:

```bash
acli jira workitem transition --key <KEY> --status 'Done' --yes
```

## After promotion

Offer `tron:jira-comment` to post a "shipped to production" note, then `tron:close-worktree` if the ticket is done.