---
name: ticket-lint
model: sonnet
effort: low
description: "Self-assess a Jira ticket (or a whole board) against the shared ticket rubric and report the gaps in plain language, including the verdict Scout triage would give it. Use for 'lint this ticket', 'is MD-1234 good enough', 'why can't triage scope my ticket', or the bulk 'lint my board' / 'which of my tickets are too thin'. Read-only: it reports gaps and offers to hand thin tickets to tron:jira-source-discovery / tron:jira-ticket-enricher or tron:create-ticket; it does not edit tickets itself."
allowed-tools:
  - Bash
  - Read
scout:
  surface: true
  title: "Check ticket readiness"
  blurb: "Shows what a Jira ticket needs before it can be routed and started."
  when: "You want to know whether a ticket is ready for someone to pick up."
  category: tickets
  effects: [report]
  inputs:
    - key: ticket
      label: "Ticket key or JQL"
      type: text
      required: true
      placeholder: "MD-1234 or project = MD AND statusCategory != Done"
---

# Ticket Lint (self-assess)

Tell a user exactly why a ticket is or is not actionable, in the same terms triage uses. Triage
(MD-2104) can flag that a ticket is too thin to scope, but the person who owns the ticket needs to know
*what to add*. This skill scores a ticket against the shared
[ticket rubric](../../tools/ticket/ticket-rubric.md) and reports the concrete gaps plus the verdict
**"as written, Scout sees: `<verdict>`"** — not a vague "add a description."

Read-only. It reports; it does not edit tickets. When a ticket is thin, it offers to hand off to
`tron:jira-source-discovery` / `tron:jira-ticket-enricher` (fill an existing ticket) or points at `tron:create-ticket` (for new ones).

The rubric, markers, and verdict ladder live in one file:
[tools/ticket/ticket-rubric.md](../../tools/ticket/ticket-rubric.md). This skill is a thin front end over
the deterministic `tools/ticket/rubric-lint.sh`, so its verdict matches what triage and `tron:create-ticket`
compute for the same ticket.

## Fast path (scripted)

The parse + verdict is one deterministic script — it fetches the ticket, parses the rubric markers, and
emits JSON. You never read raw ticket JSON.

```bash
LINT="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/ticket/rubric-lint.sh"

# Single ticket
bash "$LINT" --key MD-1234
# → {key, verdict, type, prefix_ok, missing:{spine,section,recommended}, present}
```

### Bulk: lint a whole board or query

Fetch the keys with one JQL search, then lint each and group by verdict:

```bash
LINT="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/ticket/rubric-lint.sh"
JQL='assignee = currentUser() AND statusCategory != Done'   # or "project = MD AND ..."

acli jira workitem search --jql "$JQL" --fields key --json \
  | jq -r '.[].key // .issues[].key' \
  | while read -r k; do bash "$LINT" --key "$k"; done \
  | jq -s 'group_by(.verdict) | map({verdict: .[0].verdict, count: length,
                                     keys: (map(.key))}) | sort_by(.verdict)'
```

The default "my thin tickets" query is `assignee = currentUser() AND statusCategory != Done`. Adjust the
JQL to the board or filter the user names (`project = MCR AND ...`). For a large board, delegate the loop
to a subagent so only the grouped summary lands in the main context.

## Reporting

Translate the JSON into what the owner should do. For a single ticket:

- Lead with the verdict in triage's voice: **"As written, Scout sees: `none: needs human direction`."**
- Then the concrete gaps, most-blocking first:
  - `missing.spine` — the fields that make triage give up. "Add a `Done:` line naming the deliverable."
  - `missing.section` — the work-type specifics. "Add `Acceptance criteria:` and `Affected paths:`."
  - `missing.recommended` — `Decision:` (due date, sign-off owner) and optional `Intent:` (the desired user
    or system outcome). Flag either only as advisory: an absent or placeholder `Intent:` never lowers an
    otherwise actionable verdict.
- Name what is already good (`present`) so the fix feels small.
- End with the remedy: offer `tron:jira-source-discovery` + `tron:jira-ticket-enricher` to fill it in, or note the rubric template.

For a **board**, report the grouped counts first (how many `high` / `medium` / `low` / `none`), then list
the thin ones (`none` and `low`) with their single biggest gap each, so the user can fix a queue in one
pass. Do not dump every ticket's full JSON.

## What the verdicts mean

Straight from the rubric ladder ([the verdict mapping](../../tools/ticket/ticket-rubric.md#the-verdict-mapping)):

| Verdict                       | What to tell the owner                                                   |
| ----------------------------- | ------------------------------------------------------------------------ |
| `none: needs human direction` | Triage can't tell what the work is. Missing `Done:` or `Deliverable type:`. |
| `low: needs enrichment`       | Work class is unclear. A spine marker (`Type`/`Context`) is missing.     |
| `medium: routable but thin`   | Triage can route it, but the work-type specifics are missing.            |
| `high: actionable`            | Good to go. Nothing required is missing.                                  |

## Quality rules

- Use the verdict strings from the script verbatim; do not reword them (they are the contract triage shares).
- Facilitron voice in the prose you write back to the user: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
- Read-only: never edit a ticket from this skill. Hand off to `tron:jira-source-discovery` / `tron:jira-ticket-enricher` for that.
- If `rubric-lint.sh --key` fails (acli not authed, bad key), report the error plainly; do not guess a
  verdict from the summary alone.
