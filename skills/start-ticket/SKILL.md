---
name: start-ticket
model: sonnet
effort: medium
description: "Start work on a Jira ticket or GitHub issue by looking it up, creating a branch and worktree, transitioning it to In Progress, and opening a cmux workspace with the browser on the ticket. Detects Jira vs GitHub from the input format. Use this skill when the user says 'start working on MD-1234', 'pick up ticket ABC-456', 'start issue #42', 'work on this issue', 'start work on owner/repo#7', 'pick up that GitHub issue', or pastes a Jira / GitHub issue URL. Also trigger when the user says 'grab that ticket', 'let me work on this', or 'set up a branch for <ticket-ref>'."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Start Ticket

Set up everything needed to begin work on a ticket: look it up, create a worktree, transition the ticket, and open a cmux workspace with the browser on the ticket page. Works for both **Jira tickets** (via `acli`) and **GitHub issues** (via `gh`).

## Fast path (deterministic spine)

The mechanical middle of this skill — classify the ref, create the branch+worktree,
carry over gitignored env files, transition/assign the ticket — is one script:

```bash
# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=start-ticket
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains scripts/start-ticket.sh
# (skips a stale mirror that lacks it; newest version wins, marketplace breaks ties)
[ -e "$SKILL_DIR/scripts/start-ticket.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/start-ticket.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/start-ticket.sh" ] || { echo "tron:$name: can't find scripts/start-ticket.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/start-ticket.sh" <ref> (--branch <name> | --summary <text>) [--no-transition] [--base <branch>]
```

Use it like this:
1. **First, look up the ticket yourself (Step 1 below)** — you need the title/description
   to (a) summarize for the user and (b) word a good branch slug. That reading is judgment;
   the script doesn't do it.
2. Run the script with the ref and either `--branch <name>` (you chose the slug) or
   `--summary "<ticket title>"` (it slugifies into `<KEY>-slug` / `issue-<N>-slug`).
3. It detects Jira-vs-GitHub, runs `wt switch -c … --yes`, copies `.env*`/`.dev.vars*`
   from the main checkout into the new worktree (the Step 2.5 pitfall — skip it and the
   dev server 500s), and transitions Jira → *In Progress* / assigns the GitHub issue.

One JSON line on stdout (narration on stderr):

```json
{"ok":true,"refType":"jira","key":"MD-1801","branch":"MD-1801-x","worktreePath":"/…","envCopied":[".env.local"],"transitioned":true}
{"ok":false,"error":"ambiguous-ref","ref":"42","hint":"use #N for a GitHub issue or PROJ-N for Jira"}
```

Read `worktreePath` from the result, then **continue with the judgment steps the script
does NOT do**: the cmux workspace (Step 4), the dev-server offer (Step 5), and the worker
spawn (Step 6). Pass `--no-transition` when you only want the worktree (e.g. the ticket is
already In Progress). Smoke the deterministic core with
`bash "$SKILL_DIR/scripts/test-start-ticket.sh"`.

The detailed steps below remain the reference (and the fallback when the script reports
`ambiguous-ref`, `wt-switch-failed`, or a non-blocking transition failure).

## Step 0: Detect ticket type

Inspect the user's input and pick the path:

| Input shape                                              | Path  | Key/ref extraction                                |
|----------------------------------------------------------|-------|---------------------------------------------------|
| `MD-1234`, `ABC-456`, `[A-Z]+-\d+`                       | Jira  | The whole match is the key                        |
| `https://facilitron.atlassian.net/browse/MD-1234`        | Jira  | Last path segment                                 |
| `#42` (and `git remote -v` shows a github.com remote)    | GH    | `42`; repo = the current repo's slug              |
| `owner/repo#42`                                          | GH    | `42`; repo = `owner/repo`                         |
| `https://github.com/owner/repo/issues/42`                | GH    | `42`; repo = `owner/repo` (parse the URL)         |

If the input is ambiguous (e.g., a bare number like `42` with no `#`), ask the user which they mean. If the input is `#42` but the cwd is **not** inside a github.com-remote'd repo, ask for the full `owner/repo#42` form.

For the rest of this skill: `<KEY>` is the Jira key (e.g. `MD-1658`), `<N>` is the GH issue number (e.g. `42`), and `<SLUG>` is the GH repo slug (e.g. `Facilitron/marketing-pages`).

## Step 1: Look up the ticket

### Jira path

```bash
acli jira workitem view <KEY> --fields '*all'
```

Present a brief summary: **title, status, assignee, description**.

Save the ticket URL for step 4: `https://facilitron.atlassian.net/browse/<KEY>`.

### GitHub path

```bash
# Current repo
gh issue view <N> --json number,title,state,labels,assignees,author,body

# Specific repo
gh issue view <N> --repo <SLUG> --json number,title,state,labels,assignees,author,body
```

Present a brief summary: **title, state, author, labels, body (truncated to ~5 lines)**.

Save the ticket URL for step 4: `https://github.com/<SLUG>/issues/<N>`. If the input was `#N` in cwd, derive `<SLUG>` via `gh repo view --json nameWithOwner --jq .nameWithOwner`.

## Step 2: Create the branch and worktree with wt

Determine the branch name from the ticket reference + summary/title.

**Jira path:**
- Format: `<KEY>-<slugified-summary>` (e.g., `MD-1658-add-bas-logo-to-product`)

**GitHub path:**
- Format: `issue-<N>-<slugified-title>` (e.g., `issue-185-improve-better-auth-ux`)
- The `issue-` prefix prevents the branch from looking like a Jira key (which would confuse `tron:git-commit`, `tron:jira`, and other Jira-aware skills downstream).

In both cases:
- Lowercase, hyphen-separated
- No conventional commit prefixes
- Keep it concise — trim to ~60 chars if the summary/title is long

Use `wt switch` to create the worktree. Always include `--yes` because Claude runs non-interactively and can't approve hook prompts:

```bash
wt switch -c <branch-name> --yes
```

The `-c` flag creates a new branch from the default branch. `wt` automatically places the worktree in a sibling directory based on the branch name.

Dependencies are handled automatically by `wt` post-create hooks. If hooks fail, mention it so the user can install deps manually. Also sanity-check `ls <worktree-path>/node_modules/ | head -1` — an empty `node_modules/` means the hook silently no-op'd and the dev server will fail with `command not found` (nuxt, vite, etc.); run the project's install command in the worktree before continuing.

**Common hook failure — `mise trust`.** On repos that use mise, the install hook fails on a fresh worktree with `Config files in .../.mise.toml are not trusted`. Each worktree is a new path mise hasn't seen. Recover with:

```bash
mise trust <worktree-path>/.mise.toml
(cd <worktree-path> && mise install && mise exec -- bun i)   # or the repo's install command
```

Then re-run the `node_modules/` sanity check above.

After `wt switch`, get the worktree's absolute path from `wt list` output — the worktree path follows a pattern like `<project>.<branch-name>` alongside the main checkout.

## Step 2.5: Carry over gitignored env files

`.env`, `.dev.vars`, `.env.local`, and similar secret files are gitignored, so `wt switch -c` does **not** copy them into the new worktree. Without them, the dev server typically boots but every request 500s with "X is required" config errors (e.g. `BETTER_AUTH_SECRET is required`).

Find the main checkout from `git worktree list` (its first entry is always the primary checkout, wherever the user keeps their repos) and copy any gitignored env files it has into the worktree. The set varies per repo — check what's actually there rather than guessing:

```bash
MAIN_CHECKOUT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
ls -1a "$MAIN_CHECKOUT" | grep -E '^\.(env|dev\.vars)' || true
# cp each match into the worktree root
```

For each match, `cp` it into the worktree root. Don't list them in the user-facing summary — this is plumbing.

## Step 3: Transition the ticket / take ownership

### Jira path

Move the ticket to "In Progress":
```bash
acli jira workitem transition --key <KEY> --status 'In Progress' --yes
```

If the transition fails (wrong status name, already in progress, etc.), mention it but don't block.

### GitHub path

GitHub issues have no formal "In Progress" status. The convention is:

1. **Always: assign yourself.**
   ```bash
   gh issue edit <N> --add-assignee @me                                      # current repo
   gh issue edit <N> --repo <SLUG> --add-assignee @me                        # other repo
   ```
2. **If the repo uses an `in-progress` (or similar) label:** also add it. Check first:
   ```bash
   gh label list --json name --jq '.[].name' | grep -iE 'in.progress|wip|active'
   ```
   If a matching label exists, `gh issue edit <N> --add-label "<label-name>"`.
3. **Don't try to move it on a GitHub Project board** unless the user explicitly asks — `gh project item-edit` requires the `project` scope (we have it) but board layouts are repo-specific and easy to misconfigure.

Skipping any of these is fine if it fails — just mention it and continue.

## Step 4: Set up the cmux workspace

**Skip this entire step when invoked by the `tron:task` orchestrator.** That skill drives every stage itself, so a dedicated cmux workspace just goes unused — jump to the dev-server offer (Step 5) and omit the `Workspace:` line from the final confirmation. Only do this cmux step when `tron:start-ticket` runs on its own.

Create a workspace with a two-pane layout — browser on the left showing the ticket, terminal on the right:

```
┌──────────┬──────────┐
│ browser  │          │
│ (ticket) │ terminal │
│          │          │
└──────────┴──────────┘
```

Run these commands in sequence:

### 4a. Create and rename the workspace

```bash
cmux new-workspace
cmux --json list-workspaces
```

Find the new workspace ref (highest-numbered), then rename it:

```bash
cmux rename-workspace --workspace <ref> "<branch-name>"
```

### 4b. Add the browser pane with the ticket URL

Use the URL you saved in Step 1.

**Jira:**
```bash
cmux --json new-pane --type browser --direction left --workspace <ref> --url "https://facilitron.atlassian.net/browse/<KEY>"
```

**GitHub:**
```bash
cmux --json new-pane --type browser --direction left --workspace <ref> --url "https://github.com/<SLUG>/issues/<N>"
```

Note the terminal pane's surface ref — after the browser is added on the left, the original terminal is the right pane. `cmux --json list-panes --workspace <ref>` shows it; you'll need its surface ref for Step 6.

### 4c. cd the terminal pane into the worktree

```bash
cmux send --workspace <ref> "cd <worktree-absolute-path>"
cmux send-key --workspace <ref> Enter
```

### 4d. Focus the terminal pane

```bash
cmux focus-pane --pane <terminal-pane-ref> --workspace <ref>
```

## Step 5: Offer to start the worktree's dev server

If the work is likely to need browser verification (UI changes, page edits, component tweaks, anything visual), offer to start a dev server from the worktree directory in the background.

This step exists because of a real pitfall: a dev server running in the **main** repo won't reflect edits made inside a **worktree**. They're separate working copies. If the user has a dev server already running and edits happen in the worktree, the browser keeps showing stale code and time gets wasted wondering why changes aren't appearing.

Offer it by default for code/UI tickets. Skip for clearly content-only work — toolkit items whose artifact is a PDF, news posts where verification happens after deploy, config-only changes. Use judgment.

Start it as a **background task of this orchestrator session** (not in the worktree pane — that pane is for the worker in Step 6) and capture the task ID so `close-worktree` can stop it later:

```bash
cd <worktree-absolute-path> && bun dev   # or the repo's dev command
# run_in_background: true
```

Tell the user the dev server is running and on which URL (the dev server prints its `Local: http://localhost:PORT/` once it boots; tail the log if needed to confirm the port). If you spawn a worker in Step 6, pass this URL into its kickoff.

When invoked by the `tron:task` orchestrator, still offer this step — unlike cmux, a worktree-scoped dev server is genuinely useful during orchestrator-driven UI work.

## Step 6: Offer to spawn a worker agent in the worktree pane

This is the autonomy step. Instead of leaving the terminal pane idle, launch a Claude worker *in that pane* to start the ticket while you stay the orchestrator in your own pane. Offer it for any real implementation/content ticket; skip for trivial one-liners the user clearly wants to do by hand, and **skip entirely when invoked by the `tron:task` orchestrator** (it drives the work itself and needs no separate worker).

The worker lands in the **right-side terminal surface** noted in Step 4b (already `cd`'d into the worktree). There are two launch variants — pick based on the work:

### Variant A — Shared-context teams worker (validated, preferred for substantial tickets)

Inherits **your full conversation** and enables agent teams, so the worker knows everything you've discussed and can fan out teammates into cmux splits for research/draft/review subtasks. Best for big or multi-part work (e.g. a 2,500-word pillar page).

```bash
cmux send --workspace <ref> --surface <terminal-surface> \
  "cmux claude-teams --resume \"$CLAUDE_CODE_SESSION_ID\" --fork-session"
cmux send-key --workspace <ref> --surface <terminal-surface> Enter
```

- `claude-teams` turns on agent teams + auto mode (the shim maps teammate spawns to cmux splits).
- `--resume "$CLAUDE_CODE_SESSION_ID"` forks **this** orchestrator session, so the worker shares your context.
- `--fork-session` gives it a new session ID — no transcript collision with your still-running session.
- Tradeoff: it inherits your *entire* context, including anything unrelated to the ticket. If the conversation is full of unrelated work, prefer Variant B.

### Variant B — Fresh independent worker (clean slate)

A brand-new session with no baggage, seeded only by a written kickoff. Best for well-scoped, standalone tickets where your current context isn't relevant.

```bash
cmux send --workspace <ref> --surface <terminal-surface> "claude --dangerously-skip-permissions"
cmux send-key --workspace <ref> --surface <terminal-surface> Enter
```

`--dangerously-skip-permissions` is the same flag cmux uses to launch agents, so the worker won't stall on permission prompts.

### Sequencing — confirm boot *before* sending the kickoff

The worker needs a moment to boot. If you send the kickoff immediately it gets typed mid-launch and lost. Read the pane back first, and only send the marching orders once the input prompt (`❯`) is visible:

```bash
cmux read-screen --workspace <ref> --surface <terminal-surface> --lines 30
```

Then send the kickoff and submit it (a heredoc keeps multi-line prompts clean):

```bash
cmux send --workspace <ref> --surface <terminal-surface> "$KICKOFF"
cmux send-key --workspace <ref> --surface <terminal-surface> Enter
```

**Kickoff content — plan-first by default.** Tell the worker: which ticket it owns, to read the full ticket (`acli`/`gh`) and the relevant CLAUDE.md, to investigate, and to **STOP and present a plan for the user's approval before editing/drafting anything**. For Variant A, also tell it to fan out teammates as useful. Only skip the plan-first pause if the user explicitly asked for full-send autonomy.

You remain the orchestrator: re-check the worker's progress any time with `cmux read-screen`.

## Step 7: Confirm

Keep it brief — the workspace, dev server, and worker are open and visible, so the user can see it worked. If you spawned a worker, note that it's running in its own pane and will pause for plan approval there.

**Jira example:**
```
Ticket CCAL-1002: "News Post featured image edit"
Status: In Progress
Workspace: CCAL-1002-news-post-featured-image-width
Dev server: http://localhost:4001 (background task <id>)
Worker: claude-teams (shared context) running in the worktree pane — will pause for your plan approval there.
When finished: wt merge or tron:close-worktree
```

**GitHub example:**
```
Issue acme-org/acme-app#185: "Improve better-auth UX and review our implementation"
Assignee: @your-handle
Workspace: issue-185-improve-better-auth-ux
When finished: wt merge or tron:close-worktree
```
