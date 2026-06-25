---
name: gh
model: sonnet
effort: medium
description: "Interact with EXISTING GitHub issues and PRs from the CLI using the `gh` tool — look up, comment, review, merge, list, and the raw `gh api`. Use this skill whenever the user references a GitHub issue or PR (e.g., `#42`, `owner/repo#42`, a github.com URL), wants to look up a PR's reviews or checks, needs to comment on / transition / merge an issue or PR, or asks anything like 'what's the status of PR X', 'list my open issues', 'merge that PR', 'who reviewed this', or 'what changed in this release'. Also trigger when the user pastes a github.com/owner/repo/issues/N or /pull/N URL. To CREATE a new PR from the current branch use tron:git-pr. For just the staging/preview URL of a branch use tron:preview-url; for CircleCI pipeline internals use tron:circleci."
allowed-tools:
  - Bash
  - Read
  - WebFetch
---

# GitHub via `gh`

Use the `gh` CLI (`brew install gh`, typically at `/opt/homebrew/bin/gh`) for everything GitHub. Run `gh auth status` to see the active account and token scopes. A typical dev token carries `gist, project, read:org, repo, workflow` but **not** `admin:org`, so org-level admin ops will fail with a scope error — check scopes before attempting them rather than assuming.

## Auto-trigger behavior

When a GitHub issue/PR reference appears in conversation, **fetch it without waiting to be asked**. Patterns that should auto-trigger lookup:

- A bare `#42` when the conversation already has repo context (`cwd` is inside a git repo with a `github.com` remote)
- `owner/repo#42` regardless of cwd
- A full `https://github.com/owner/repo/(issues|pull)/N` URL
- A PR or issue number mentioned alongside repo context

The lookup itself is `gh issue view N` or `gh pr view N` — `gh` auto-detects whether it's an issue or a PR from the number if you don't know.

## Fast path (scripted)

The four most common mechanical operations are wrapped as subcommands of the
bundled script — reach for it first instead of hand-typing `gh ...` flags:

```bash
# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=gh
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains scripts/gh.sh
# (skips a stale mirror that lacks it; newest version wins, marketplace breaks ties)
[ -e "$SKILL_DIR/scripts/gh.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/gh.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/gh.sh" ] || { echo "tron:$name: can't find scripts/gh.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/gh.sh" <subcommand> [flags]
```

| Want                                    | Command                                                                                                         |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| PR summary (state, checks, review, URL) | `gh.sh gh-view-pr --number N [--repo owner/repo]`                                                               |
| List issues as JSON                     | `gh.sh gh-list-issues [--state open\|closed\|all] [--assignee @me] [--label L] [--limit N] [--repo owner/repo]` |
| Worktree-safe merge + branch delete     | `gh.sh gh-merge-pr --number N [--method squash\|merge\|rebase] [--no-delete-branch] [--repo owner/repo]`        |
| Comment on an issue or PR               | `gh.sh gh-comment --number N --body "..." [--repo owner/repo]`                                                  |

Each subcommand emits one JSON line carrying an `ok` boolean (`--repo` defaults to
the current repo). `gh-merge-pr` uses the **server-side API merge** so it is safe
from a git worktree (see "Merging a PR" below for why). Exit `0` success / `1`
logical failure / `2` usage error. Smoke the dispatch + flag contract with
`bash "$SKILL_DIR/scripts/test-gh.sh"`.

For everything else — issue/PR create and edit, search across repos, workflow
runs, deployment-URL lookup, releases, raw `gh api`, auth — see the full CLI
command reference in `reference/cli.md`. The judgment notes below stay here.

## Merging a PR (worktree-safe)

Default to the **server-side API merge**. It merges the PR on GitHub and does **no local git
operations**, so it returns clean JSON and never touches a checkout. Use it everywhere — it is the
only path that is safe from a git worktree, and it is identical to `gh pr merge`'s result on a
regular checkout.

```bash
# 1. Merge server-side (squash; swap merge_method for merge|rebase to match the repo's allowed methods)
gh api -X PUT repos/:owner/:repo/pulls/<N>/merge -f merge_method=squash

# 2. Delete the remote branch server-side (replaces `--delete-branch`; also no local op)
gh api -X DELETE repos/:owner/:repo/git/refs/heads/<branch>
```

`:owner` and `:repo` are filled in automatically by `gh` from the current repo; to target a
different repo, pass `--repo owner/repo`. The head branch name is
`$(gh pr view <N> --json headRefName --jq .headRefName)`.

### Why not bare `gh pr merge` from a worktree

`gh pr merge <N> --squash --delete-branch` does two things: (1) merges the PR server-side, which
succeeds, then (2) runs **local** cleanup — `git checkout <default>` + a local branch delete. Step 2
fails inside a git worktree because the default branch (main/master) is already checked out by the
main worktree:

```
fatal: '<default>' is already checked out at <path>
```

`gh` surfaces that as a loud error **after the merge already landed**, so the worker has to re-query
the PR to confirm it actually merged. The merge always succeeded; the error is a false alarm from
the local-checkout half. Because workers run the lifecycle from worktrees, this fires on every merge.

- **From a worktree (the common case for lifecycle workers): use the API merge above.** No local
  ops, no false-alarm error, no re-verify step.
- **`gh pr merge` is fine for an interactive merge from a regular (non-worktree) checkout.** If you
  do hit the `already checked out` error from a worktree, treat it as benign and confirm state with
  `gh pr view <N> --json state` (expect `"MERGED"`).

This mirrors the worktree-awareness already baked into `git-dev.sh` / `git-pushtoprod.sh`, applied
to the single-promotion-branch `gh pr merge` path.

## When something goes wrong

| Symptom                                                      | Fix                                                                                                            |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| `HTTP 403: Resource not accessible by personal access token` | The token is missing a scope. `gh auth refresh -s <scope>`.                                                    |
| `HTTP 404` on a private repo                                 | The token doesn't have access. Confirm `gh auth status` shows the right account; `gh auth switch` if needed.   |
| `no commits in common`                                       | The PR's base branch was force-pushed or rewritten. Don't merge; investigate.                                  |
| `Required status check failing`                              | `gh pr checks <N> --watch` to see which one; `gh run view <run-id> --log-failed` to read the failure.          |
| `gh api` returns truncated body                              | The response is large. Use `--paginate` for list endpoints; for single-resource truncation, switch to GraphQL. |
| Wrong account for a personal repo                            | `gh auth switch` or pass `--hostname github.com` to disambiguate.                                              |

Worked examples of the longer recipes — latest open issue, all-my-open-PRs,
staging-URL lookup, watch-CI, tail-failing-job, bulk-close — live in the
"Common harness recipes" section of `reference/cli.md`.

## Environment noise

Running `gh` in this shell sometimes prints harmless `zoxide` warnings to stderr (`zoxide: ...`). These are unrelated to `gh` and can be ignored. If they're polluting your output parsing, redirect: `gh ... 2> >(grep -v zoxide >&2)`.
