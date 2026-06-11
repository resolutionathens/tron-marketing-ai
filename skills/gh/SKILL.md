---
name: gh
description: "Interact with GitHub from the CLI using the `gh` tool — issues, pull requests, workflow runs, deployments, releases, and the raw `gh api`. Use this skill whenever the user references a GitHub issue or PR (e.g., `#42`, `owner/repo#42`, a github.com URL), asks about workflow runs / CI status / Actions, wants to look up a PR's reviews or checks, needs to comment on or transition an issue, wants the staging URL for a PR, or asks anything like 'what's the status of PR X', 'why is CI failing', 'list my open issues', 'merge that PR', 'who reviewed this', 'tail the workflow', 'find the deployment URL', or 'what changed in this release'. Also trigger when the user pastes a github.com/owner/repo/issues/N or /pull/N URL, mentions GitHub Actions, references a workflow file, or asks about anything in a repo's GitHub state."
allowed-tools:
  - Bash
  - Read
  - WebFetch
---

# GitHub via `gh`

Use the `gh` CLI (`/opt/homebrew/bin/gh`) for everything GitHub. The user is currently authed as `resolutionathens` with `gist, project, read:org, repo, workflow` scopes — no `admin:org`, so org-level admin ops will fail with a scope error and should not be attempted.

## Auto-trigger behavior

When a GitHub issue/PR reference appears in conversation, **fetch it without waiting to be asked**. Patterns that should auto-trigger lookup:

- A bare `#42` when the conversation already has repo context (`cwd` is inside a git repo with a `github.com` remote)
- `owner/repo#42` regardless of cwd
- A full `https://github.com/owner/repo/(issues|pull)/N` URL
- A PR or issue number mentioned alongside repo context

The lookup itself is `gh issue view N` or `gh pr view N` — `gh` auto-detects whether it's an issue or a PR from the number if you don't know.

## Issues

```bash
# View an issue (current repo) — lead with --json for parseable output, avoid wasting tokens on the pretty-printed text form
gh issue view <N> --json title,body,state,labels,assignees,milestone,createdAt,author
gh issue view <N> --comments              # include the full thread
gh issue view <N>                          # human-readable (only when the user wants to read it themselves)

# Other repos
gh issue view <N> --repo owner/repo

# List
gh issue list                                          # open issues in current repo
gh issue list --assignee @me --state open
gh issue list --label "bug,priority:high"
gh issue list --search "is:open author:@me created:>=2026-01-01"

# Search across all GitHub (cross-repo, not just current)
gh search issues "label:bug language:typescript" --limit 20
gh search issues --author=@me --state=open                 # all your open issues across all repos
gh search issues "is:open updated:>=2026-05-01" --limit 30

# Create
gh issue create --title "..." --body "..." --label bug --assignee @me
gh issue create --title "..." --body-file ./desc.md     # multi-line bodies

# Comment / close / reopen / transition
gh issue comment <N> --body "..."
gh issue close <N>
gh issue reopen <N>
gh issue edit <N> --add-label "in-progress" --remove-label "backlog"
gh issue edit <N> --add-assignee @me
gh issue edit <N> --milestone "v1.2"
```

GitHub has no formal "In Progress" status like Jira. Conventions vary by repo — common patterns are:
- An `in-progress` (or similar) label
- An "In Progress" column on a GitHub Project (use `gh project item-edit` if you go this route)
- Just assigning yourself, no label

Default behavior when "starting work on an issue": assign `@me`. Add a label only if the repo's existing issues clearly use one (check `gh label list` first).

## Pull Requests

```bash
# View
gh pr view <N>
gh pr view <N> --comments
gh pr view <N> --json title,state,mergeable,statusCheckRollup,reviews,reviewDecision

# Current branch's PR
gh pr view                                  # in a feature branch, shows the open PR

# List (current repo only — single-repo)
gh pr list
gh pr list --author @me --state open
gh pr list --search "draft:false review:required" --limit 20

# List ACROSS ALL repos you have access to — use gh search prs, not gh pr list
gh search prs --author=@me --state=open
gh search prs --author=@me --state=open --review-requested=@me
gh search prs "is:open draft:false review:required" --limit 30

# Checks (CI status)
gh pr checks <N>                            # short status table
gh pr checks <N> --watch                    # live-watch until done
gh pr checks <N> --required                 # required checks only

# Reviews
gh pr review <N> --approve --body "lgtm"
gh pr review <N> --request-changes --body "..."
gh pr review <N> --comment --body "..."

# Comments (issue comments on a PR — different from review comments)
gh pr comment <N> --body "..."

# Lifecycle
gh pr ready <N>                             # mark draft as ready
gh pr edit <N> --add-reviewer "user1,user2"
gh pr merge <N> --squash --delete-branch    # squash-merge + cleanup
gh pr merge <N> --merge                     # merge commit
gh pr merge <N> --rebase                    # rebase
gh pr close <N>

# Diff / files
gh pr diff <N>
gh pr diff <N> --name-only
```

**Inline review comments** (the kind attached to specific lines) aren't fully exposed via the top-level `gh pr` commands. Use the API:

```bash
gh api repos/{owner}/{repo}/pulls/<N>/comments    # all line comments on a PR
```

### Field value reference

When parsing `gh pr view --json`, these are the values the fields actually take:

- `reviewDecision`: `""` (empty — no reviews required and none submitted), `"REVIEW_REQUIRED"`, `"APPROVED"`, `"CHANGES_REQUESTED"`. Empty is normal for solo repos without branch protection.
- `mergeable`: `"MERGEABLE"`, `"CONFLICTING"`, `"UNKNOWN"` (GitHub hasn't computed it yet — retry in a few seconds).
- `state`: `"OPEN"`, `"CLOSED"`, `"MERGED"`.
- `statusCheckRollup`: array of check objects with `conclusion` ∈ `"SUCCESS"`, `"FAILURE"`, `"CANCELLED"`, `"SKIPPED"`, `"NEUTRAL"`, `"TIMED_OUT"`, `"ACTION_REQUIRED"`, or `status` ∈ `"QUEUED"`, `"IN_PROGRESS"`, `"COMPLETED"`. **An empty `statusCheckRollup` array is ambiguous** — it could mean (a) no checks are configured for this repo, (b) checks haven't started yet (race after push), or (c) the PR is from a fork and required checks haven't run. Cross-check with `gh pr checks <N>` for human-readable diagnosis.

## Workflow runs (CI / Actions)

```bash
# List recent runs
gh run list                                 # current repo
gh run list --workflow ci.yml --limit 10
gh run list --branch <branch-name>
gh run list --status failure --limit 20

# View a single run
gh run view <run-id>
gh run view <run-id> --log-failed           # just the failing job's log — what you want 90% of the time
gh run view <run-id> --log                  # full log (large)

# Live-watch a run
gh run watch <run-id>
gh run watch <run-id> --exit-status         # exit non-zero if the run failed (useful in scripts)

# The current branch's latest run
gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 1 --json databaseId,status,conclusion

# Rerun (whole run, or just failed jobs)
gh run rerun <run-id>
gh run rerun <run-id> --failed
```

For long-running watches, use the Bash tool's `run_in_background: true` and monitor via `Monitor` rather than blocking the session.

## Deployments (finding staging URLs)

**Critical:** GitHub's `/deployments` endpoint only sees deployments the CI explicitly registers via the Deployments API. Many Cloudflare setups don't. **Always check what registered the deployments before trusting the result** — `pages-build-deployment` stubs from a vestigial `github-pages` workflow are the most common red herring.

```bash
# First: enumerate environments to see what's actually registered
gh api repos/:owner/:repo/deployments --jq '[.[] | .environment] | unique'

# If you see only "github-pages", the project doesn't register real deployments — see the fallback table below.
# If you see "Preview", "Production", "staging", etc. — those are real and worth following.
```

```bash
# List recent deployments
gh api -X GET repos/:owner/:repo/deployments --jq '.[] | {id, ref, environment, created_at}'

# Filter by branch / environment (NB: env names are case-sensitive — Cloudflare Pages uses "Preview" not "preview")
gh api -X GET "repos/:owner/:repo/deployments?ref=<branch>&environment=Preview" --jq '.[0]'

# Get the latest status (which carries the deployment URL)
DEPLOY_ID="$(gh api repos/:owner/:repo/deployments?ref=<branch> --jq '.[0].id')"
gh api "repos/:owner/:repo/deployments/$DEPLOY_ID/statuses" --jq '.[0] | {state, environment_url, log_url}'
```

`environment_url` is the staging/preview URL. `log_url` is where the CI's deploy step lives.

### Deploy-target → source-of-truth lookup

| Project deploys via…                                  | GitHub deployments? | Real source of truth                                                          |
|-------------------------------------------------------|--------------------|-------------------------------------------------------------------------------|
| **Cloudflare Pages** (`wrangler pages deploy`)        | ✅ Yes (`environment: "Preview"` / `"Production"`) | `gh api .../deployments` + `wrangler pages deployment list --project-name=<name>` |
| **Cloudflare Workers** (`wrangler deploy` via `cloudflare/wrangler-action`) | ❌ **No** — the action does NOT register a GitHub deployment | `wrangler deployments list` (in the project dir) + `gh run view <run-id> --log` |
| **Vercel/Netlify** (via their GH App)                 | ✅ Yes              | `gh api .../deployments` directly                                              |
| **CircleCI**                                          | ⚠ Depends on the orb — often NO | `circleci runs` / workflow output (see `/circleci`)                            |
| **Plain `gh workflow` actions deploying to anywhere** | ❌ Unless the workflow explicitly calls `actions/github-script` to create one | `gh run view <run-id> --log` and grep for the URL                              |

**The athenspedia / photozines / mabe-nuxt / fiftymillimeter / fourXfive / ospdbe / photozines.com / slouching-towards-hollywood / truck-ianslap-top repos all deploy Workers via `wrangler-action`** — for those, ignore `gh api .../deployments` (you'll see only `github-pages` stubs from a vestigial pages workflow) and go straight to:

```bash
# In the project directory:
unset CLOUDFLARE_API_TOKEN && npx wrangler deployments list   # latest deploys + commit SHAs + who triggered them

# Or via the failing-run log to find the URL the deploy was *trying* to use:
gh run view <run-id> --log-failed | grep -iE 'https?://|deployed|published'
```

If the deploy failed and you want to retry: `gh run rerun <run-id> --failed` (just the failed jobs, not the whole pipeline).

For Cloudflare-Pages projects that DO register deployments, the env names are typically `"Preview"` (PR previews) and `"Production"` (master/main pushes) — capitalization matters in the `?environment=` filter.

## Releases

```bash
gh release list
gh release view <tag>
gh release view <tag> --json tagName,publishedAt,assets,body
gh release create <tag> --title "..." --notes-file ./notes.md
gh release create <tag> --generate-notes      # auto-generate from PRs/commits
gh release upload <tag> ./dist/*.zip
```

## `gh api` — the escape hatch

Anything the dedicated subcommands don't cover is reachable via the REST or GraphQL API:

```bash
# REST
gh api repos/:owner/:repo/issues/<N>/timeline
gh api -X PATCH repos/:owner/:repo/issues/<N> -f state=closed

# Paginate automatically
gh api --paginate repos/:owner/:repo/issues --jq '.[].number'

# GraphQL
gh api graphql -f query='query { viewer { login } }'

# Substitution: `:owner` / `:repo` resolve from the current git remote;
# pass --hostname/--repo if you need to target a different repo.
gh api repos/{owner}/{repo}/contents/path/to/file --jq -r '.content' | base64 -d
```

For complex bodies, write to a file:

```bash
gh api -X POST repos/:owner/:repo/pulls --input pr.json
```

## Auth

```bash
gh auth status            # current user, scopes, host
gh auth login             # interactive (browser flow); usually already done
gh auth refresh -s workflow,repo,project    # add scopes to existing auth
gh auth switch            # toggle between accounts if multiple are logged in
gh auth token             # print the active token (useful for `curl` calls)
```

Current scopes on this machine: `gist, project, read:org, repo, workflow`. **No `admin:org`** — don't attempt org-admin operations (team management, org settings) without first running `gh auth refresh -s admin:org`.

## Output handling

- `--json <fields>` returns structured JSON; pair with `--jq` for inline filtering.
- `--template '{{.field}}'` for Go-template formatting.
- For lists, `--limit <N>` to bound the response; default is 30.

```bash
# Common idioms
gh pr list --json number,title,headRefName,reviewDecision --jq '.[] | "\(.number) \(.title) [\(.reviewDecision)]"'
gh run list --json databaseId,conclusion,headBranch --limit 5 --jq '.[]'
```

## Detecting repo type & defaults

```bash
gh repo view                             # current repo's metadata
gh repo view --json name,owner,defaultBranchRef,visibility,isArchived

# Repo's preferred merge method (squash/merge/rebase)
gh api repos/:owner/:repo --jq '{merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge}'
```

Before merging, check the repo's allowed merge methods — `gh pr merge --squash` will fail on a repo that disables squash.

## When something goes wrong

| Symptom                                                    | Fix                                                                   |
|------------------------------------------------------------|-----------------------------------------------------------------------|
| `HTTP 403: Resource not accessible by personal access token` | The token is missing a scope. `gh auth refresh -s <scope>`.            |
| `HTTP 404` on a private repo                               | The token doesn't have access. Confirm `gh auth status` shows the right account; `gh auth switch` if needed. |
| `no commits in common`                                     | The PR's base branch was force-pushed or rewritten. Don't merge; investigate. |
| `Required status check failing`                            | `gh pr checks <N> --watch` to see which one; `gh run view <run-id> --log-failed` to read the failure. |
| `gh api` returns truncated body                            | The response is large. Use `--paginate` for list endpoints; for single-resource truncation, switch to GraphQL. |
| Wrong account for a personal repo                          | `gh auth switch` or pass `--hostname github.com` to disambiguate.     |

## Common harness recipes

### "What's the latest open issue here?"
```bash
gh issue list --state open --limit 1 \
  --json number,title,author,createdAt,body \
  --jq '.[0] | {n: .number, title, who: .author.login, when: .createdAt, body}'
```

### "All my open issues across every repo"
```bash
gh search issues --author=@me --state=open \
  --json number,title,repository,updatedAt \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) — \(.title) (\(.updatedAt))"'
```

### "Status of my open PRs (across all repos)"
```bash
gh search prs --author=@me --state=open \
  --json number,title,repository,isDraft,url \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) [\(if .isDraft then "DRAFT" else "READY" end)] — \(.title)"'

# Per-PR detail (slower, but full CI + review picture):
gh pr view <N> --repo <owner/repo> \
  --json title,state,mergeable,isDraft,reviewDecision,statusCheckRollup
```

### "Find the staging URL for the PR on the current branch"
```bash
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# 1) Check which environments this repo actually registers deployments for:
gh api repos/:owner/:repo/deployments --jq '[.[] | .environment] | unique'

# 2a) If it includes "Preview" (Cloudflare Pages, Vercel, Netlify):
gh api "repos/:owner/:repo/deployments?ref=$BRANCH&environment=Preview" --jq '.[0].id' \
  | xargs -I {} gh api "repos/:owner/:repo/deployments/{}/statuses" --jq '.[0].environment_url'

# 2b) If you only see "github-pages" stubs (i.e. the project deploys Workers via wrangler-action):
unset CLOUDFLARE_API_TOKEN && npx wrangler deployments list   # in the project dir
```

### "Watch CI on the current PR and exit when done"
```bash
gh pr checks --watch
```

### "Tail the failing job from the latest run on this branch"
```bash
RUN="$(gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run view "$RUN" --log-failed
```

### "A deploy just failed — retry only the failed jobs"
```bash
gh run rerun <run-id> --failed
```

### "Bulk-close stale issues older than 6 months with no activity"
```bash
gh issue list --state open --search "updated:<2025-11-22" --json number --jq '.[].number' \
  | xargs -I{} gh issue close {} --comment "Closing as stale. Reopen if still relevant."
```

(Always confirm the search before running — `gh issue list` first, then pipe.)

## Environment noise

Running `gh` in this shell sometimes prints harmless `zoxide` warnings to stderr (`zoxide: ...`). These are unrelated to `gh` and can be ignored. If they're polluting your output parsing, redirect: `gh ... 2> >(grep -v zoxide >&2)`.
