---
name: start-ticket
model: sonnet
effort: medium
description: "Start work on a Jira ticket or GitHub issue by looking it up, creating a branch and worktree, transitioning it to In Progress, and then moving into the worktree and beginning the implementation against the ticket as the spec. Detects Jira vs GitHub from the input format. Use this skill when the user says 'start working on MD-1234', 'pick up ticket ABC-456', 'start issue #42', 'work on this issue', 'start work on owner/repo#7', 'pick up that GitHub issue', or pastes a Jira / GitHub issue URL. Also trigger when the user says 'grab that ticket', 'let me work on this', or 'set up a branch for <ticket-ref>'. It scaffolds the workspace and kicks off the work; it does not commit, promote, or open a PR (those are separate lifecycle skills)."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Start Ticket

Look up a ticket, create a worktree, transition it, then move into the worktree and begin the work.

## Step 0: Detect ticket type

| Input                                             | Path | Key                            |
| ------------------------------------------------- | ---- | ------------------------------ |
| `MD-1234`, `PROJ-456` (`[A-Z]+-\d+`)              | Jira | The key                        |
| `https://facilitron.atlassian.net/browse/MD-1234` | Jira | Last path segment              |
| `#42` (cwd has github.com remote)                 | GH   | `42`; repo = current repo slug |
| `owner/repo#42`                                   | GH   | `42`; repo = `owner/repo`      |
| `https://github.com/owner/repo/issues/42`         | GH   | `42`; repo = `owner/repo`      |

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
{
  "ok": true,
  "refType": "jira",
  "key": "MD-1801",
  "branch": "MD-1801-x",
  "worktreePath": "/…",
  "envCopied": [".env.local"],
  "nodeModulesLinked": ["node_modules"],
  "baseFreshened": true,
  "transitioned": true
}
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

## Step 2: Move into the worktree and begin the work

Setup is done. Now actually start the ticket — do not stop at scaffolding.

1. **Switch your working context to the worktree.** Every command, file read, and edit from here runs against `worktreePath`, never the main checkout. `cd` into it (or pass it explicitly) so the dev server, edits, and git all target the new branch.
2. **Use the ticket as the spec.** Work from the description you looked up in Step 1 — its Context, Sources, Implementation notes, and Acceptance criteria. Open the linked sources the description names (Figma, Confluence, GitHub, docs).
3. **If the ticket is too thin to act on** (empty or vague description, no implementation notes), enrich it first with `tron:enrich-jira-ticket`, or ask the user for the missing detail. Do not guess at scope.
4. **State a short plan, then start.** Restate the first implementation steps in a line or two, then make the first changes in the worktree, working the acceptance criteria top to bottom.

Open the ticket URL for reference: `open "<url>"`.

This skill begins the work; it does not finish it. Committing, dev promotion, PR, and prod stay with their own lifecycle skills (`tron:git-commit`, `tron:git-dev`, `tron:git-pr`, `tron:git-pushtoprod`). Hand off once there is something to commit.

