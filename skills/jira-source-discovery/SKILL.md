---
name: jira-source-discovery
model: haiku
effort: low
description: "Discover source material for a Jira ticket by reading the ticket, its parent, and linked issues — extracting source links, metadata, work type, and existing-page context. Use when you need the real context behind a thin ticket: 'find the source for MD-1234', 'what's the context behind this ticket', 'gather the linked issues and sources'. Pure read-only discovery — it returns structured metadata; it does not write to Jira. Pair with tron:jira-ticket-enricher to write the enriched description."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
scout:
  surface: developer
  effects: [local]
  inputs:
    - key: tickets
      label: "Ticket key(s)"
      type: text
      required: true
      placeholder: "MD-1234, MD-1235"
---

# /jira-source-discovery — Jira source discovery

Discover the real context behind a thin Jira ticket. This skill reads the ticket, its parent, and linked issues, extracts source links and metadata, identifies the work type, and searches for existing pages — all without writing to Jira.

## When to use

- A ticket has a thin or empty description and you need to find the source material
- You need to know which work type from the shared ticket rubric applies
- You need to discover linked Figma files, Confluence pages, Google Docs, or GitHub references
- You want to check whether a content/landing page already exists before enriching

## What it produces

Returns structured metadata as JSON:
```json
{
  "key": "MD-1234",
  "summary": "...",
  "workType": "engineering|design|content|campaign-asset|cms",
  "sources": [
    {"type": "figma|confluence|google-doc|github|...", "url": "...", "note": "..."}
  ],
  "parentGoal": "...",
  "existingPage": null
}
```

## Fast path

### 1. Normalize the ticket list

Parse all keys the user gave. If a key fails, do not silently skip it. Check for obvious transposition or project-key typos only when the context supports it.

### 2. Read the ticket, its parent, and linked issues

```bash
acli jira workitem view <KEY> --fields '*all' --json
acli jira workitem view <KEY> --fields comment --json
```

Discover the parent key and every linked-issue key:

```bash
acli jira workitem view <KEY> --fields '*all' --json \
  | jq -r '
      .fields.parent.key // empty,
      (.fields.issuelinks[]? | (.outwardIssue.key // .inwardIssue.key))
    ' \
  | sort -u
```

Then read each related key the same way. Capture:
- Key, summary, status, assignee, existing description state
- Parent key and linked-issue keys with their link type
- All source links from descriptions and comments
- Comment author and date if useful for provenance

### 3. Identify the work type

Infer from the summary, source, and user context. Common Facilitron patterns:

- Webdev or navigation changes → engineering
- A `blocks` / `is blocked by` link to a Figma or design ticket → design
- Landing page work in `pages/**` → engineering (page)
- Blog, cluster article, or news item → content (news)
- Guide or pillar → content (guide)
- `Checklist:` / `SOP:` / `Template:` with `/resources/toolkit` → content (toolkit)
- A leaf asset under a campaign hierarchy → campaign-asset
- Editing an existing page in HubSpot or another hosted CMS → cms

Return one of the canonical `Type` values defined in
[`tools/ticket/ticket-rubric.md`](../../tools/ticket/ticket-rubric.md); do not maintain a separate
work-type vocabulary in this skill.

When the user states the repo or destination type, trust that over inference.

### 4. Search for existing matching page

If the work type is a landing page, product page, or content item in the target repo, check whether a page matching the subject already exists. The search resolves that repo's pages and content roots from its own content profile rather than assuming a layout. See `reference/existing-page-search.md`.

### 5. Pull source metadata

Identify the source type from the links you gathered and capture what the implementer will need. See `reference/source-types.md` for the full catalog. Read a Google Doc through the authenticated `gws docs documents get` path, not a plain export — `reference/source-types.md` has the exact command and JSON extraction.

If a source is not directly accessible, still note its URL so the implementer can use it as a reference — but "not accessible" means every supported authenticated retrieval path for that source type failed, not that a first plain fetch came back empty. An authoritative source (the spec the work implements) that no authenticated path can read is a hard implementation gate, not a note to work around; see [WORKER_CONTRACT.md](../../WORKER_CONTRACT.md).

## Output

Report the structured findings. Do not write to Jira — that is `tron:jira-ticket-enricher`'s job.
