---
name: jira
model: haiku
effort: low
description: "Look up, search, and interact with Jira tickets using the acli CLI. Use this skill whenever the user references a Jira ticket key (e.g., MD-1234, PROJ-456, ABC-78), mentions Jira, asks about work items, issues, or tickets, wants to search for tasks, or needs to transition or assign a ticket. Also trigger when the user says things like 'what's the status of that ticket', 'look up the issue', 'check my board', or references any KEY-NUMBER pattern that looks like a Jira identifier. To post a progress or status comment on a ticket use tron:jira-comment."
allowed-tools:
  - Bash
scout:
  surface: false
  inputs:
    - key: query
      label: "JQL or ticket key"
      type: text
      required: true
---

# Jira Interaction via acli

Use the `acli` CLI tool (locate it with `command -v acli`) to interact with Jira.
Auth is `acli`'s own per-user OAuth session, not a brokered token — see
[tools/jira/broker-status.md](../../tools/jira/broker-status.md) for why.

## Auto-trigger behavior

When a Jira ticket key appears in conversation (matches the pattern `[A-Z]+-\d+`, like MD-1660 or PROJ-123), immediately fetch its details without waiting to be asked. This is the core value of this skill — proactive lookup saves the user a round trip.

## Commands

### Viewing tickets

```bash
# Full ticket details (default for lookups)
acli jira workitem view <KEY> --fields '*all'

# Structured data for parsing
acli jira workitem view <KEY> --json

# Just comments
acli jira workitem view <KEY> --fields comment
```

When presenting a ticket, surface the most useful info first: **summary, status, assignee, and description**. Skip noisy metadata unless the user asks for it.

### Searching

```bash
acli jira workitem search --jql '<JQL query>'
```

Common JQL patterns:

- `project = MD AND status = "In Progress"` — active work
- `assignee = currentUser() AND status != Done` — my open tickets
- `text ~ "search term"` — full-text search
- `updated >= -7d AND project = MD` — recently touched

### Modifying tickets

```bash
# Add a comment
acli jira workitem comment create --key <KEY> --body '<comment text>'

# Transition (e.g., To Do -> In Progress -> Done)
acli jira workitem transition --key <KEY> --status '<status name>' --yes

# Assign
acli jira workitem assign <KEY> --assignee '<user>'

# Create a new ticket
acli jira workitem create --project <PROJECT> --type <type> --summary '<summary>' --description '<description>'
# Add --assignee '@me' when the ticket is prefixed SCOUT: or TRON-PLUGIN: (see "Creating tickets" below)
```

### Rich descriptions (markdown → ADF)

**Rule:** any description more than a line or two, or with any markdown formatting, must go through the bundled `tools/md-to-adf` helper and `--description-file` — never pass raw markdown to `-d`/`--description` (it renders literally). Invocation, the acli plain-text gotcha, and the code-mark caveat: [tools/md-to-adf/usage.md](../../tools/md-to-adf/usage.md).

## Creating tickets

When creating a ticket in the MD project, prefix the summary per
[tools/jira/conventions.md](../../tools/jira/conventions.md) — the repo/prefix table there is
canonical (it mirrors the `repoForSummaryPrefix` test fixture in the SCOUT repo). If the target
repo isn't clear from context, ask the user which repo the ticket is for rather than guessing.

Tickets prefixed `SCOUT:` or `TRON-PLUGIN:` are the user's own OS/plugin work — self-assign them
on creation with `--assignee '@me'`:

```bash
acli jira workitem create --project <PROJECT> --type <type> --summary '<summary>' --description '<description>' --assignee '@me'
```

Every other prefix stays unassigned unless the user says otherwise.

## Presentation guidelines

- Lead with the ticket summary as a heading, then status and assignee
- Format description text cleanly — Jira descriptions often have markup that needs tidying
- When showing search results, use a compact table or list format
- Use `--json` when you need to extract specific fields programmatically
- If a command fails, check that `acli` is on PATH (`command -v acli`) and report the error clearly

## When to delegate to a subagent

Running `acli` is cheap; the question is what comes back and what you do with it. Default to **inline** — most Jira work doesn't benefit from a subagent.

**Delegate (Haiku/Sonnet) only when:**

- **Batch triage** — a `search` returns many tickets and you need them ranked, filtered, or grouped. Fan out the triage so the raw JSON for 20+ tickets never lands in the main context.
- **Inform-only on a noisy ticket** — `--fields '*all'` pulls a wall of metadata but the user just wants status + description. A subagent can distill and return the few useful fields.

**Never delegate when:**

- It's a **single-field lookup** (status, assignee) — the payload is tiny and subagent overhead dominates.
- The main thread is **reading the ticket to act on it** (e.g. `tron:start-ticket`, `tron:news-item` consuming the ticket) — you need those fields _in_ the main context, and a summarizing subagent strips exactly what you came for.
- It's a **write** (comment, transition, assign) — fast, stateful, and the user should see it happen in the main thread.
