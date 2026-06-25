# Worker spawn & tmux session management

Reference for `tron:start-ticket` Steps 4 and 6 — setting up the tmux session and
launching a Claude worker agent inside it. The main SKILL.md keeps the workflow spine;
this file holds the mechanical detail.

## Contents

- Step 4: Set up the tmux session
- Step 6: Offer to spawn a worker agent in the tmux session

## Step 4: Set up the tmux session

**Skip this entire step when invoked by the `tron:ship-ticket` orchestrator.** That skill drives every stage itself, so a dedicated tmux session just goes unused — jump to the dev-server offer (Step 5) and omit the `Session:` line from the final confirmation. Only do this tmux step when `tron:start-ticket` runs on its own.

Create a detached tmux session rooted in the worktree (the terminal you'll work in / spawn a worker in), and open the ticket in the user's default browser:

```
┌─────────────────────┐
│   tmux: terminal    │   + ticket opens in your default browser
│   (in the worktree) │
└─────────────────────┘
```

Run these commands in sequence:

### 4a. Create the session

tmux session names can't contain `.` or `:`, so sanitize the branch name first:

```bash
SESSION="$(printf '%s' '<branch-name>' | tr '.:' '--')"
tmux new-session -d -s "$SESSION" -c "<worktree-absolute-path>"
```

The session starts detached, with one shell already `cd`'d into the worktree. If a session with that name already exists, reuse it or pick a suffixed name.

### 4b. Open the ticket in the default browser

Use the URL you saved in Step 1 (`open` on macOS, `xdg-open` on Linux):

**Jira:**

```bash
open "https://facilitron.atlassian.net/browse/<KEY>"
```

**GitHub:**

```bash
open "https://github.com/<SLUG>/issues/<N>"
```

### 4c. Attach (the user does this)

The session is detached so the skill stays non-blocking. Tell the user to attach when ready:

```bash
tmux attach -t "$SESSION"
```

Don't attach from inside the skill — Claude runs non-interactively and attaching would block.

## Step 6: Offer to spawn a worker agent in the tmux session

This is the autonomy step. Instead of leaving the session idle, launch a Claude worker _in its pane_ to start the ticket while you stay the orchestrator in your own session. Offer it for any real implementation/content ticket; skip for trivial one-liners the user clearly wants to do by hand, and **skip entirely when invoked by the `tron:ship-ticket` orchestrator** (it drives the work itself and needs no separate worker).

The worker lands in the tmux session created in Step 4 (already `cd`'d into the worktree). All commands target the session by name (`-t "$SESSION"`). There are two launch variants — pick based on the work:

### Variant A — Shared-context worker (preferred for substantial tickets)

Inherits **your full conversation**, so the worker knows everything you've discussed. Best for big or multi-part work (e.g. a 2,500-word pillar page).

```bash
tmux send-keys -t "$SESSION" \
  "claude --resume \"$CLAUDE_CODE_SESSION_ID\" --fork-session" Enter
```

- `--resume "$CLAUDE_CODE_SESSION_ID"` forks **this** orchestrator session, so the worker shares your context.
- `--fork-session` gives it a new session ID — no transcript collision with your still-running session.
- Need parallelism? The worker can fan out its own subagents normally (the Agent tool); there's no special multiplexer wiring to set up.
- Tradeoff: it inherits your _entire_ context, including anything unrelated to the ticket. If the conversation is full of unrelated work, prefer Variant B.

### Variant B — Fresh independent worker (clean slate)

A brand-new session with no baggage, seeded only by a written kickoff. Best for well-scoped, standalone tickets where your current context isn't relevant.

```bash
tmux send-keys -t "$SESSION" "claude --dangerously-skip-permissions" Enter
```

`--dangerously-skip-permissions` lets the worker run without stalling on permission prompts.

### Sequencing — confirm boot _before_ sending the kickoff

The worker needs a moment to boot. If you send the kickoff immediately it gets typed mid-launch and lost. Read the pane back first, and only send the marching orders once the input prompt (`❯`) is visible:

```bash
tmux capture-pane -t "$SESSION" -p | tail -30
```

Then send the kickoff and submit it:

```bash
tmux send-keys -t "$SESSION" "$KICKOFF" Enter
```

**Kickoff content — plan-first by default.** Tell the worker:

- **Which ticket it owns** — the key/ref and a one-line summary
- To read the full ticket (`acli`/`gh`) and the relevant CLAUDE.md before touching anything
- To investigate and then **STOP and present a plan for the user's approval before editing or drafting anything** — skip this pause only if the user asked for full-send autonomy

Also include these standing instructions in every kickoff:

**Out-of-scope follow-up work:** if the worker discovers work that falls outside this ticket's scope (an unrelated bug, a deferred refactor, a TODO it's intentionally leaving), it must **not** fold it in (scope creep) and must **not** just drop a comment (evaporates). Instead, the moment it finds the out-of-scope work it should file a new Jira ticket using `tron:jira`. Rules: (a) derive the ticket summary prefix from the target repo — SCOUT → tron-os, TRON-PLUGIN → tron-marketing-ai, SUPPORT → facilitron-support, PAGES → marketing-pages, LLLP → marketing-dynamic-landing-pages, MABE → mabe-nuxt, UI → facilitron-ui — never guess; (b) dedup first (`acli jira workitem search` for matching open tickets); (c) label `auto-followup` and link back to the originating ticket; (d) cap at 3 per run.

**Marker discipline:** when the PR is open the worker should post a retro comment using `tron:git-pr`'s built-in retro step (Step 9). The retro format uses `<!-- tron-retro -->` as its first line, followed by a `### Retro` heading. Any out-of-scope work **not** already filed as a Jira ticket goes in the retro as a `FOLLOW-UP:` line (one per line) — the OS harvests these into tickets as a safety net. For any other status or progress comment posted on the PR, end the comment body with `<!-- tron-note -->` so the OS can distinguish worker notes from human review feedback.

You remain the orchestrator: re-check the worker's progress any time with `tmux capture-pane -t "$SESSION" -p`.
