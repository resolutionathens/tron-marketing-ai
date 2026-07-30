---
name: jira-ticket-enricher
model: sonnet
effort: medium
fallback:
  cost: low
  skip_when: "Use tron:jira-ticket-enricher only when source material has been gathered. Run tron:jira-source-discovery first if the ticket has no known context."
  stage_skips:
    - stage: "Self-check against rubric"
      skip_when: "User confirms the draft is complete and accurate"
description: "Take a Jira ticket with its discovered sources and write an enriched, implementation-ready description, using the shared ticket rubric to produce machine-readable markers. Use after tron:jira-source-discovery has gathered the context: 'write the enriched description for MD-1234', 'draft the ticket from these sources'. Jira-write skill — it edits ticket descriptions only after the user confirms."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
scout:
  surface: developer
  effects: [jira]
  inputs:
    - key: ticket
      label: "Ticket key"
      type: text
      required: true
      placeholder: "MD-1234"
    - key: sources
      label: "Source metadata"
      type: textarea
      required: false
      help: "Source metadata from jira-source-discovery, or paste links directly"
---

# /jira-ticket-enricher — Jira ticket enricher

Take a Jira ticket and its discovered sources, then draft and write an enriched, implementation-ready description. This is a Jira-write skill — it edits ticket descriptions only after the user confirms.

## When to use

- After `tron:jira-source-discovery` has gathered context
- You have source links and want them turned into a rubric-compliant description
- You need to write enriched descriptions for one ticket or a batch

## Authorization rule

- If the user explicitly asks to enrich tickets, you may write the descriptions after drafting them.
- If the user only asks you to look, triage, or inspect, show a preview and ask before editing.
- If source links or destination assumptions are ambiguous, ask before writing.

## Fast path

```bash
mkdir -p /tmp/tron-enrich-jira-ticket
```

### 1. Draft the enriched description

Use the base shape in `reference/description-template.md` — it has a full worked example. The base shape is the rubric's fenced machine header (spine + the section markers for the ticket's `Type`) followed by human prose. Add only the prose sections a ticket needs, and never include empty sections. For a `marketing-pages` `/resources/toolkit` item sourced from a Google Doc, layer `reference/toolkit-playbook.md` on top of that base shape.

Fill the machine header from the sources you gathered or were given: `Done`, `Type`, `Deliverable type`, `Context`, `Decision`, and the `Type`'s section markers. Do not invent a value for a marker you cannot ground in a real source.

When the destination repo is known, also emit the `Destination repo:` line under `## Sources` verbatim — the literal label text and backtick-wrapped value. Do not paraphrase it. tron-os's dispatch router greps this marker to route work.

The rubric itself is the shared [`tools/ticket/ticket-rubric.md`](../../tools/ticket/ticket-rubric.md) — the single source of truth for the spine, the per-type section markers, and the verdict ladder.

### 2. Self-check against the rubric before writing

```bash
TICKET_DIR="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/ticket"
bash "$TICKET_DIR/rubric-lint.sh" --file /tmp/tron-enrich-jira-ticket/<KEY>.md \
  --summary "<the ticket's current summary>" | jq '{verdict, missing}'
```

A `medium: routable but thin` verdict is acceptable when a genuine detail is still unknown. After writing to Jira, verify the live ticket:

```bash
bash "$TICKET_DIR/rubric-lint.sh" --key <KEY> | jq '{verdict, missing}'
```

### 3. Convert to ADF and update Jira

```bash
ADF="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/md-to-adf/md-to-adf.mjs"
node "$ADF" < /tmp/tron-enrich-jira-ticket/<KEY>.md > /tmp/tron-enrich-jira-ticket/<KEY>.adf.json
acli jira workitem edit --key <KEY> --description-file /tmp/tron-enrich-jira-ticket/<KEY>.adf.json --yes
```

### 4. Verify

```bash
acli jira workitem view <KEY> --fields summary,description --json \
  | jq -r '.fields.summary, (.fields.description.content[0].content[0].text // "description present")'
```

## Quality rules

- Use direct, concrete instructions. The ticket should be enough for a developer to start without hunting through comments, the parent, or a linked ticket.
- Preserve the source link in the enriched description even if it already exists in a comment or on a linked ticket.
- Keep descriptions scannable with headings and bullets.
- Do not paste the full source document into Jira unless the user asks. Link to the source and summarize.
- Do not invent fields that are not supported by the destination schema.
- Facilitron voice in the prose you draft: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
- Always use `tools/md-to-adf` with `--description-file` — never pass raw markdown to `acli --description`.