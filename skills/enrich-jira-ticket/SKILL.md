---
name: enrich-jira-ticket
model: haiku
effort: low
fallback:
  cost: low
  skip_when: "Use tron:enrich-jira-ticket only when a ticket needs enrichment. If you only need source discovery, use tron:jira-source-discovery. If you only need to write a description from known sources, use tron:jira-ticket-enricher."
description: "Enrich existing Jira tickets with implementation-ready descriptions by discovering source context and writing a rubric-compliant description. This is a thin orchestrator that delegates to tron:jira-source-discovery (source discovery) and tron:jira-ticket-enricher (description writing). Use when the user says 'enrich these tickets', 'flesh out Jira tickets', 'add acceptance criteria', 'prep these tickets for dev'. For source discovery only, use tron:jira-source-discovery directly. For description writing from known sources, use tron:jira-ticket-enricher directly."
allowed-tools:
  - Skill
  - Bash
  - AskUserQuestion
scout:
  surface: true
  title: "Get a ticket dev-ready"
  blurb: "Fleshes out thin tickets with background, source links, acceptance criteria, and implementation notes — pulled from parents, links, and comments."
  when: "A ticket is just a title and someone needs to actually build it."
  category: tickets
  effects: [jira]
  inputs:
    - key: tickets
      label: "Ticket key(s)"
      type: text
      required: true
      placeholder: "MD-1234, MD-1235"
---

# /enrich-jira-ticket — Ticket enrichment orchestrator

Turn thin Jira tickets into implementation-ready tickets. This skill is a thin orchestrator: it delegates to `tron:jira-source-discovery` (source discovery) and `tron:jira-ticket-enricher` (description writing) in sequence.

## When to use

- A ticket has a thin or empty description
- You need to enrich one ticket or a batch
- The work type is known but the ticket description is missing context, links, or acceptance criteria

For source discovery only, use `tron:jira-source-discovery` directly. For description writing from known sources, use `tron:jira-ticket-enricher` directly.

## Authorization rule

Editing Jira descriptions is shared state.

- If the user explicitly asks to enrich tickets, you may write the descriptions after drafting them.
- If the user only asks you to look, triage, or inspect, show a preview and ask before editing.
- If source links or destination assumptions are ambiguous, ask before writing.

## Workflow

### 1. Discover sources

Delegate to `tron:jira-source-discovery` via the Skill tool with the ticket key(s). This returns structured metadata: work type, source links, parent goal, and existing-page search results.

### 2. Enrich the ticket

Pass the discovered sources to `tron:jira-ticket-enricher` via the Skill tool. This drafts the enriched description, self-checks against the rubric, converts to ADF, and writes to Jira.

### 3. Verify

Confirm the enriched ticket is live and lints correctly.

## Quality rules

- No em dashes in prose you draft (Facilitron voice).
- Always use `tools/md-to-adf` with `--description-file` — never pass raw markdown to `acli --description`.