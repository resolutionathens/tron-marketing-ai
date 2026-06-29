---
name: start-ticket
model: sonnet
effort: medium
description: "Start work on a Jira ticket or GitHub issue by looking it up, creating a branch and worktree, transitioning it to In Progress, and opening a tmux session with the ticket. Detects Jira vs GitHub from the input format. Use this skill when the user says 'start working on MD-1234', 'pick up ticket ABC-456', 'start issue #42', 'work on this issue', 'start work on owner/repo#7', 'pick up that GitHub issue', or pastes a Jira / GitHub issue URL. Also trigger when the user says 'grab that ticket', 'let me work on this', or 'set up a branch for <ticket-ref>'."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Start Ticket

Look up a ticket, create a worktree, transition it, open a tmux session + ticket page.

## Step 0: Detect ticket type

| Input | Path | Key |
|-------|------|-----|
| `MD-1234`, `PROJ-456` (`[A-Z]+-\d+`) | Jira | The key |
| `https://facilitron.atlassian.net/browse/MD-1234` | Jira | Last path segment |
| `#42` (cwd has github.com remote) | GH | `42`; repo = current repo slug |
| `owner/repo#42` | GH | `42`; repo = `owner/repo` |
| `https://github.com/owner/repo/issues/42` | GH | `42`; repo = `owner/repo` |

Ambiguous bare number → ask user. `#42` outside a github remote → ask for `owner/repo#42`.

## Step 1: Look up the ticket

```bash
# Jira
acli jira workitem view <KEY> --fields '*all'

# GitHub
gh issue view <N> --json number,title,state,labels,assignees,author,body
```

Present: **title, status, assignee, description** (Jira) or **title, state, author, labels, body (~5 lines)** (GitHub). Save the ticket URL for later.

## Fast path (deterministic spine — script handles the mechanical core)

The mechanical middle (classify, freshen base, create branch+worktree, copy env files, symlink node_modules, transition/assign) is one script:

```bash
name=start-ticket
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/start-ticket.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/start-ticket.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/start-ticket.sh" ] || { echo "tron:$name: scripts/start-ticket.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/start-ticket.sh" <ref> (--branch <name> | --summary <text>) [--no-transition] [--base <branch>]
```

1. You look up the ticket (Step 1) — the script doesn't do this.
2. Run it with `--branch <name>` or `--summary "<title>"` (slugifies to `<KEY>-slug` or `issue-<N>-slug`).
3. It freshens the base, runs `wt switch -c … --yes`, copies `.env*`/`.dev.vars*`, symlinks `node_modules` (root + workspaces), transitions Jira → In Progress / assigns GitHub issue.

```json
{"ok":true,"refType":"jira","key":"MD-1801","branch":"MD-1801-x","worktreePath":"/…","envCopied":[".env.local"],"nodeModulesLinked":["node_modules"],"baseFreshened":true,"transitioned":true}
```

Read `worktreePath` from the result. The script exits on `ambiguous-ref`, `wt-switch-failed`, or transition failure — fall back to the manual steps below if it fails.

### Manual fallback (if script unavailable)

**Branch naming:** `<KEY>-<slugified-summary>` (Jira) or `issue-<N>-<slugified-title>` (GitHub). Lowercase, hyphenated, ~60 chars max.

**Create worktree:** Freshen base first — `git fetch origin <default> && git merge --ff-only origin/<default>` in the main checkout. Then `wt switch -c <branch> --yes`. If the post-create hook fails with `mise trust`, recover with `mise trust <worktree>/.mise.toml && (cd <worktree> && mise install && mise exec -- bun i)`.

**Env files:** Copy `.env*`/`.dev.vars*` from the main checkout (first entry in `git worktree list`) into the worktree root. Without these, the dev server 500s with config errors.

**Node modules:** Check `ls <worktree>/node_modules/ | head -1`. Empty → run the project's install command.

**Jira transition:**
```bash
acli jira workitem transition --key <KEY> --status 'In Progress' --yes
```

**GitHub assignment:**
```bash
gh issue edit <N> --add-assignee @me
# Optional in-progress label:
gh label list --json name | grep -iE 'in.progress|wip|active' && gh issue edit <N> --add-label "<label>"
```

## Step 4: Set up the tmux session

Skip this when invoked by `tron:ship-ticket` orchestrator. Create a detached session in the worktree:

```bash
SESSION="$(printf '%s' '<branch>' | tr '.:' '--')"
tmux new-session -d -s "$SESSION" -c "<worktreePath>"
tmux send-keys -t "$SESSION" 'vim .' Enter
tmux split-window -v -t "$SESSION" -c "<worktreePath>"
```

Open the ticket URL: `open "<url>"`. Tell the user: `tmux attach -t "$SESSION"`.

## Step 5: Offer dev server

Offer to start a worktree-scoped dev server for code/UI tickets (skip for content-only work). Run as a background task of this session:

```bash
cd <worktree-path> && bun dev   # run_in_background: true
```

Tell the user the URL once the server boots.

## Step 6: Offer a worker agent (optional)

For implementation tickets, offer to spawn a Claude worker in the tmux session's pane. See `reference/worker-spawn.md` for launch variants and kickoff instructions. Skip when invoked by `tron:ship-ticket`.

## Step 7: Confirm

Give the user: session name + `tmux attach -t <name>`, browser URL, dev server URL, worker status (if spawned). Keep it brief.