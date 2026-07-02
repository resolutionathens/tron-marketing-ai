---
name: gh
model: sonnet
effort: medium
description: "Interact with EXISTING GitHub issues and PRs from the CLI using the `gh` tool — look up, comment, review, merge, list, and the raw `gh api`. Use this skill whenever the user references a GitHub issue or PR (e.g., `#42`, `owner/repo#42`, a github.com URL), wants to look up a PR's reviews or checks, needs to comment on / transition / merge an issue or PR, or asks anything like 'what's the status of PR X', 'list my open issues', 'merge that PR', 'who reviewed this', or 'what changed in this release'. To CREATE a new PR use tron:git-pr."
allowed-tools:
  - Bash
  - Read
  - WebFetch
---

# GitHub via `gh`

Use the `gh` CLI for everything GitHub. Run `gh auth status` to check the active account and scopes.

## Auto-trigger behavior

When a GitHub issue/PR reference appears (`#42`, `owner/repo#42`, full URL), fetch details immediately without waiting to be asked.

## Fast path (scripted)

```bash
name=gh
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/gh.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/gh.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/gh.sh" ] || { echo "tron:$name: scripts/gh.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/gh.sh" <subcommand> [flags]
```

| Want | Command |
|------|---------|
| PR summary | `gh.sh gh-view-pr --number N [--repo owner/repo]` |
| List issues | `gh.sh gh-list-issues [--state open\|closed] [--assignee @me] [--label L] [--limit N]` |
| Merge PR (worktree-safe) | `gh.sh gh-merge-pr --number N [--method squash\|merge\|rebase] [--no-delete-branch]` |
| Comment on issue/PR | `gh.sh gh-comment --number N --body "..."` |

Each returns one JSON line with an `ok` boolean. For everything else (create, edit, search, workflow runs, releases, raw API), see `reference/cli.md`.

## Merging a PR — worktree-safe

**Default to the server-side API merge** (no local git ops, safe from worktrees):

```bash
gh api -X PUT repos/:owner/:repo/pulls/<N>/merge -f merge_method=squash
gh api -X DELETE repos/:owner/:repo/git/refs/heads/<branch>
```

Get the branch name: `gh pr view <N> --json headRefName --jq .headRefName`

**Why not bare `gh pr merge` from a worktree:** `gh pr merge <N> --squash --delete-branch` runs local cleanup (`git checkout <default>`) that fails inside a worktree with `fatal: '<default>' is already checked out at <path>`. The merge succeeds but the error is a false alarm. From a regular (non-worktree) checkout, `gh pr merge` is fine.

## Common ad-hoc commands

```bash
gh issue view <N>                             # look up an issue
gh pr view <N>                                # look up a PR
gh pr view <N> --comments                      # view PR comments thread
gh pr checks <N> --watch                      # watch CI for a PR
gh issue list --assignee @me --state open     # my open issues
gh search issues "deploy" --owner facilitron  # search across a repo
gh run list --limit 5                         # recent workflow runs
gh run view <N> --log-failed                  # read a failed job log
gh api repos/:owner/:repo/deployments?ref=<branch>  # find preview URLs
```

## PR review inspection

When checking a PR's review status:

```bash
# Overall review decision (APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED)
gh pr view <N> --json reviewDecision --jq .reviewDecision

# All reviews — who reviewed, what they said, and their verdict
gh pr view <N> --json reviews --jq '.[] | {reviewer: .author.login, state: .state, body: .body}'

# Inline comments (non-review threads)
gh pr view <N> --json comments --jq '.[] | {author: .author.login, body: .body}'

# Who was requested to review (pending)
gh pr view <N> --json reviewRequests --jq '.[] | .requestedReviewer.login'

# All at once — decision + reviews + comments
gh pr view <N> --json reviews,comments,reviewDecision \
  --jq '{decision: .reviewDecision, reviews: [.reviews[] | {reviewer: .author.login, state: .state, body: .body}], comments: [.comments[] | {author: .author.login, body: .body}]}'
```

For multi-step recipes (staging-URL lookup, watch CI, bulk-close), see `reference/cli.md`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `HTTP 403: Resource not accessible` | Token missing scope. `gh auth refresh -s <scope>` |
| `HTTP 404` on private repo | Token doesn't have access. `gh auth status` + `gh auth switch` |
| `no commits in common` | Base branch force-pushed. Don't merge. |
| `Required status check failing` | `gh pr checks N --watch` to see which; `gh run view N --log-failed` for details |
| Truncated `gh api` response | Use `--paginate` for lists; GraphQL for single-resource bodies |

Ignore harmless `zoxide` warnings on stderr — redirect with `2> >(grep -v zoxide >&2)` if noisy.