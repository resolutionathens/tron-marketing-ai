---
name: gh
model: sonnet
effort: medium
description: "Interact with EXISTING GitHub issues and PRs from the CLI using the `gh` tool — look up, comment, review, merge, list, and the raw `gh api`. Use this skill whenever the user references a GitHub issue or PR (e.g., `#42`, `owner/repo#42`, a github.com URL), wants to look up a PR's reviews or checks, needs to comment on / transition / merge an issue or PR, or asks anything like 'what's the status of PR X', 'list my open issues', 'merge that PR', 'who reviewed this', or 'what changed in this release'. To CREATE a new PR use tron:git-pr."
allowed-tools:
  - Bash
  - Read
  - WebFetch
scout:
  surface: developer
---

# GitHub via `gh`

Use the `gh` CLI for everything GitHub. Run `gh auth status` to check the active account and scopes.

## Auto-trigger behavior

When a GitHub issue/PR reference appears (`#42`, `owner/repo#42`, full URL), fetch details immediately without waiting to be asked.

## Fast path (scripted)

```bash
name=gh
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/gh.sh)"
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

**Default to the server-side API merge** — no local git ops, so it's safe from a
worktree. Use the scripted `gh.sh gh-merge-pr` (table above); the raw commands are
in `reference/cli.md` § "Server-side (worktree-safe) merge commands".

**Why not bare `gh pr merge` from a worktree:** `gh pr merge <N> --squash --delete-branch` runs local cleanup (`git checkout <default>`) that fails inside a worktree with `fatal: '<default>' is already checked out at <path>`. The merge succeeds but the error is a false alarm. From a regular (non-worktree) checkout, `gh pr merge` is fine.

## Common ad-hoc commands

```bash
gh pr view <N>                                # look up a PR (add --comments for the thread)
gh pr checks <N> --watch                      # watch CI for a PR
gh run view <N> --log-failed                  # read a failed job log
```

For everything else — issue lookup/search, workflow runs, deployments/preview URLs,
PR review inspection (the `--json reviews` jq recipes), and multi-step recipes
(staging-URL lookup, watch CI, bulk-close) — see `reference/cli.md`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `HTTP 403: Resource not accessible` | Token missing scope. `gh auth refresh -s <scope>` |
| `HTTP 404` on private repo | Token doesn't have access. `gh auth status` + `gh auth switch` |
| `no commits in common` | Base branch force-pushed. Don't merge. |
| `Required status check failing` | `gh pr checks N --watch` to see which; `gh run view N --log-failed` for details |
| Truncated `gh api` response | Use `--paginate` for lists; GraphQL for single-resource bodies |

Ignore harmless `zoxide` warnings on stderr — redirect with `2> >(grep -v zoxide >&2)` if noisy.