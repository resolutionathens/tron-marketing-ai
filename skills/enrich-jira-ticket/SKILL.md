---
name: enrich-jira-ticket
model: sonnet
effort: medium
description: Enrich existing Jira tickets with implementation-ready descriptions by reading the ticket, pulling source links from comments, extracting source metadata when possible, and writing a rich ADF description via acli. Use when the user says ticket enrichment, enrich these tickets, flesh out Jira tickets, add acceptance criteria, prep these tickets for dev, the link is in a comment, or when a batch of CCAL/MCR/MD tickets needs structured context, source links, repo/path guidance, implementation notes, and acceptance criteria. Especially useful for marketing-pages content tasks such as /resources/toolkit, /resources/news, /resources/guides, landing pages, and creative or SEO implementation tickets. Jira-write skill. It edits ticket descriptions only after the user clearly asks for enrichment or confirms a preview.
allowed-tools:
  - Bash
  - AskUserQuestion
---

# Enrich Jira Ticket

Turn thin Jira tickets into implementation-ready tickets. This skill reads existing tickets, finds the real source material, usually in comments, drafts a structured description, converts it to Atlassian Document Format, and writes it back to Jira with `acli`.

Use this for one ticket or a batch when the work is known but the ticket description is empty, vague, or missing the links a developer needs.

## What this skill does

- Fetches each Jira ticket summary, status, assignee, description, and comments.
- Extracts source links from both plain links and Jira smart cards in comments.
- Resolves obvious key typos when safe, for example `CCLA-1976` might be `CCAL-1976` if the first key fails and the neighboring keys match.
- Pulls source metadata when available, especially Google Docs `export?format=txt` fields like `Meta Title`, `Meta Description`, and `Slug`.
- Drafts a structured Jira description with context, source links, destination paths, implementation notes, and acceptance criteria.
- Converts markdown to ADF with the bundled `tools/md-to-adf` helper so Jira renders headings, bullets, links, and code correctly.
- Updates the Jira description with `acli jira workitem edit --description-file`.

It does **not** implement the ticket, create branches, commit code, or move ticket status. It is Jira enrichment only.

## Authorization rule

Editing Jira descriptions is shared state.

- If the user explicitly asks to enrich tickets, like "these need ticket enrichment" or "enrich CCAL-123", you may write the descriptions after drafting them.
- If the user only asks you to look, triage, or inspect, show a preview and ask before editing.
- If source links or destination assumptions are ambiguous, ask before writing.

## Fast path

For a batch, create a temp working directory and keep one markdown draft and one ADF file per ticket:

```bash
mkdir -p /tmp/tron-enrich-jira-ticket
```

Fetch ticket basics:

```bash
acli jira workitem view <KEY> --json
acli jira workitem view <KEY> --fields comment --json
```

Extract comment URLs, including regular link marks and smart-card `inlineCard` URLs:

```bash
acli jira workitem view <KEY> --fields comment --json \
  | jq -r '
      .. | objects |
      (.attrs.href? // .attrs.url? // empty)
    ' \
  | sort -u
```

Extract visible text from comments when the link is not obvious:

```bash
acli jira workitem view <KEY> --fields comment --json \
  | jq -r '.. | objects | select(has("text")) | .text'
```

For a public or accessible Google Doc, fetch plain text for metadata:

```bash
DOC_ID="<google-doc-id>"
curl -L "https://docs.google.com/document/d/${DOC_ID}/export?format=txt" -o /tmp/tron-enrich-jira-ticket/<KEY>.txt
```

Convert the description draft to ADF and update Jira:

```bash
ADF="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/md-to-adf/md-to-adf.mjs"
node "$ADF" < /tmp/tron-enrich-jira-ticket/<KEY>.md > /tmp/tron-enrich-jira-ticket/<KEY>.adf.json
acli jira workitem edit --key <KEY> --description-file /tmp/tron-enrich-jira-ticket/<KEY>.adf.json --yes
```

## Workflow

### 1. Normalize the ticket list

Parse all keys the user gave. If a key fails, do not silently skip it. Check for obvious transposition or project-key typos only when the context supports it.

Example: if the user gives `CCAL-1971`, `CCAL-1972`, `CCAL-1974`, `CCLA-1976`, and `CCAL-1977`, try `CCAL-1976` after `CCLA-1976` fails and report the correction.

### 2. Read each ticket and comments

For every ticket capture:

- Key
- Summary
- Status
- Assignee
- Existing description state
- All source links found in comments
- Comment author and date if useful for provenance

Prefer `--json` and `jq` over screen-scraping formatted output.

### 3. Identify the work type

Infer from the summary, source, and user context. Common Facilitron patterns:

- `Checklist:` with `/resources/toolkit` means toolkit category `checklist`.
- `SOP:` with `/resources/toolkit` means toolkit category `sop`.
- `Template:` with `/resources/toolkit` means toolkit category `template`.
- Blog, cluster article, or news item means `content/resources/news/<slug>.md`.
- Guide or pillar means a bespoke Vue page under `/resources/guides` plus guide index registration.
- Landing page work usually belongs in `pages/**` and needs route, SEO, and component notes.

When the user states the repo or destination type, trust that over inference.

### 4. Pull source metadata

When the source is a Google Doc and accessible, fetch its text export. Look near the top for fields such as:

- `Meta Title:`
- `Meta Description:`
- `Slug:`
- H1 title
- Purpose, Scope, Procedure, FAQ, or checklist sections

If the doc is not accessible, still enrich the ticket with the source URL and note that the implementer should use the linked doc as the copy source.

### 5. Draft the enriched description

Use this base shape. Keep it practical and implementation-ready.

```markdown
# <Action-oriented title>

## Context

<Short explanation of what this ticket is for and where the source lives.>

- Source content: [<Source label>](<url>)
- Destination repo: `<repo>`
- Destination file: `<path if known>`
- Public route: `<route if known>`
- Work type: `<type>`

## Source SEO fields

- Meta title: <title if known>
- Meta description: <description if known>
- Source slug: `<slug if known>`

## Implementation notes

1. <Concrete first step.>
2. <Schema, component, asset, PDF, or routing guidance.>
3. <QA or verification guidance.>

## Acceptance criteria

- <Expected file or page exists.>
- <The page or asset renders in the expected location.>
- <Links, downloads, images, or metadata work.>
- <Review criteria are satisfied.>
```

Do not include empty sections. If a ticket has no SEO fields, replace that section with the relevant source notes or omit it.

## Playbook: marketing-pages toolkit items

When the user says the work is in `marketing-pages` and all items are `/resources/toolkit` items, use this richer structure:

````markdown
# Publish toolkit item: <Title>

## Context

This ticket is ready for development. The source copy lives in <source>, linked from the ticket comment. Build it as a `/resources/toolkit` item in the `marketing-pages` repository.

- Source content: [Google Doc](<url>)
- Destination repo: `marketing-pages`
- Destination file: `content/resources/toolkit/<slug>.md`
- Public route: `/resources/toolkit/<slug>`
- Toolkit category: `<sop|checklist|template>`

## Source SEO fields

- Meta title: <meta title>
- Meta description: <meta description>
- Source slug: `/<slug>`

## Implementation notes

1. Convert the Google Doc into Nuxt Content markdown using the toolkit item schema.
2. Use the toolkit front matter fields below, updating `date` to the publish date:

```yaml
title: <Title>
date: YYYY-MM-DD
description: <description>
image: <slug>.webp
category: <sop|checklist|template>
download: <slug>.pdf
meta_title: <meta title>
meta_description: <meta description>
```

3. Keep the web page body focused on the public article content. Do not duplicate the page hero, title, download button, social share row, or closing demo CTA because the toolkit renderer supplies those.
4. Build the branded PDF from the actionable section only. For checklists, include the checklist groups. For SOPs, include the procedure steps. For templates, include the fillable template grid or structured template content. Upload it to ImageKit as `toolkit/downloads/<slug>.pdf`.
5. Create or source a toolkit card image, convert to WebP if needed, and upload it to ImageKit as `toolkit/<slug>.webp`.
6. Rewrite any `facilitron.com` links to relative internal paths and verify internal links before publish.

## Acceptance criteria

- `content/resources/toolkit/<slug>.md` exists and uses valid front matter with category `<sop|checklist|template>`.
- The page renders at `/resources/toolkit/<slug>` and appears on `/resources/toolkit` with the correct category card.
- The Download PDF button is visible and the PDF opens from ImageKit.
- The toolkit card image loads from ImageKit with an exact filename match.
- Link checks pass for the new markdown, with internal Facilitron paths verified against the site.
- The page has been reviewed for Facilitron voice, no raw Google Doc formatting, and no duplicate page chrome.
````

### Toolkit slug handling

If the source gives `Slug: /my-item`, use `my-item`. If not, derive one from the title with lowercase hyphenation. Match the destination filename, public route, PDF filename, and image filename exactly.

### Toolkit category mapping

- Summary starts with `Checklist:` to `checklist`
- Summary starts with `SOP:` to `sop`
- Summary starts with `Template:` to `template`

## Quality rules

- Use direct, concrete instructions. The ticket should be enough for a developer to start without hunting through comments.
- Preserve the source link in the enriched description even if it already exists in a comment.
- Keep descriptions scannable with headings and bullets.
- Do not paste the full source document into Jira unless the user asks. Link to the source and summarize the implementation requirements.
- Do not invent fields that are not supported by the destination schema.
- No em dashes in prose you draft.
- For rich descriptions, always use `tools/md-to-adf`. Never pass markdown directly to `acli --description`, because Jira will render the markdown literally.

## Verification

After editing, spot-check each ticket:

```bash
acli jira workitem view <KEY> --fields summary,description --json \
  | jq -r '.fields.summary, (.fields.description.content[0].content[0].text // "description present")'
```

Report back with:

- Tickets updated
- Any key corrections
- Any tickets skipped and why
- Where the draft files were saved if useful
