---
name: enrich-jira-ticket
model: sonnet
effort: medium
description: Enrich existing Jira tickets with implementation-ready descriptions by reading the ticket and its parent and linked issues, pulling source links from comments and descriptions, extracting source metadata when possible, and writing a rich ADF description via acli. Use when the user says ticket enrichment, enrich these tickets, flesh out Jira tickets, add acceptance criteria, prep these tickets for dev, the link is in a comment, the context is on the parent or a linked ticket, or when a batch of CCAL/MCR/MD tickets needs structured context, source links, repo/path guidance, implementation notes, and acceptance criteria. Works for any ticket type — webdev and navigation changes, design/Figma implementation, landing pages, content tasks (/resources/toolkit, /resources/news, /resources/guides), and creative or SEO work. Jira-write skill. It edits ticket descriptions only after the user clearly asks for enrichment or confirms a preview.
allowed-tools:
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

# Enrich Jira Ticket

Turn thin Jira tickets into implementation-ready tickets. This skill reads an existing ticket along with its parent and linked issues, finds the real source material wherever it lives, drafts a structured description, converts it to Atlassian Document Format, and writes it back to Jira with `acli`.

Use this for one ticket or a batch when the work is known but the ticket description is empty, vague, or missing the context and links a developer needs. It is type-agnostic: a webdev sub-task, a Figma-implementation ticket, a landing page, an SEO change, or a content item all enrich the same way. It does **not** implement the ticket, create branches, commit code, or move ticket status — Jira enrichment only.

## Where the source material lives

A thin ticket rarely holds its own context. Look in this order and merge what you find:

1. **The ticket itself** — description and comments (plain links and smart-card `inlineCard`/`blockCard` URLs).
2. **Linked issues** — especially a `blocks` / `is blocked by` design or spec ticket. These commonly hold the Figma file, the page being replaced, the asset location, and reviewer notes. Read their description and comments too.
3. **The parent** — an epic or campaign that states the overall goal and the "why". Pull its summary and description for the context line.

When the same link or fact appears in more than one place, keep one copy and prefer the most specific source.

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

Fetch ticket basics. Use `--fields '*all'` so `parent` and `issuelinks` come back (the bare `--json` omits them):

```bash
acli jira workitem view <KEY> --fields '*all' --json
acli jira workitem view <KEY> --fields comment --json
```

Discover the parent key and every linked-issue key, then read each one the same way:

```bash
acli jira workitem view <KEY> --fields '*all' --json \
  | jq -r '
      .fields.parent.key // empty,
      (.fields.issuelinks[]? | (.outwardIssue.key // .inwardIssue.key))
    ' \
  | sort -u
# then, for each KEY above:
acli jira workitem view <RELATED_KEY> --fields summary,description,comment --json
```

Extract comment and description URLs, including regular link marks and smart-card `inlineCard` URLs:

```bash
acli jira workitem view <KEY> --fields description,comment --json \
  | jq -r '
      .. | objects |
      (.attrs.href? // .attrs.url? // empty)
    ' \
  | sort -u
```

Extract visible text from the description and comments when the link is not obvious:

```bash
acli jira workitem view <KEY> --fields description,comment --json \
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

### 2. Read the ticket, its parent, and its linked issues

For the target ticket capture:

- Key
- Summary
- Status
- Assignee
- Existing description state
- Parent key, and linked-issue keys with their link type (`blocks`, `is blocked by`, `relates to`)

Then read the parent and each linked issue (see [Where the source material lives](#where-the-source-material-lives)) and capture from them:

- Summary and description — the parent usually carries the goal, the linked design/spec ticket usually carries the source links
- All source links found in their descriptions and comments
- Comment author and date if useful for provenance

Prefer `--json` and `jq` over screen-scraping formatted output.

### 3. Identify the work type

Infer from the summary, source, and user context. Common Facilitron patterns:

- Webdev or navigation changes (add to a dropdown, footer, header, menu) belong in the relevant app repo and need component, route, and placement notes.
- A `blocks` / `is blocked by` link to a Figma or design ticket means design-driven implementation: build to match the linked Figma file, using the assets it names.
- Landing page work usually belongs in `pages/**` and needs route, SEO, and component notes.
- Blog, cluster article, or news item means `content/resources/news/<slug>.md`.
- Guide or pillar means a bespoke Vue page under `/resources/guides` plus guide index registration.
- `Checklist:` / `SOP:` / `Template:` with `/resources/toolkit` means a toolkit item — see [reference/toolkit-playbook.md](reference/toolkit-playbook.md).

When the user states the repo or destination type, trust that over inference.

### 4. Pull source metadata

Identify the source type from the links you gathered and capture whatever the implementer will need. A ticket often has more than one source (a spec plus a design, say) — capture each. What each type carries (Figma, page being replaced, asset location, Google Doc, Confluence spec, GitHub PR/issue/path, error link, chat/recording) is catalogued in [reference/source-types.md](reference/source-types.md).

If a source is not directly accessible, still enrich the ticket with its URL and note that the implementer should use it as the reference.

### 5. Draft the enriched description

Use the base shape in [reference/description-template.md](reference/description-template.md) — it also has a full worked example for a Figma-driven navigation ticket. Keep it practical and implementation-ready: add only the sections a ticket needs (a `## Source SEO fields` section for content/SEO work), and never include empty sections.

When the destination repo is known, emit the `Destination repo:` and `Destination path or route:` lines under `## Sources` **verbatim**: the literal label text and backtick-wrapped value, exactly as shown in the template. Do not paraphrase them into a different heading (e.g. `## Repo / implementation guidance (marketing-pages)`) or fold the repo name into prose elsewhere instead. These are not freeform prose the model rephrases; they are a fixed, machine-parsed line. tron-os's dispatch router (`lib/triage.ts`) greps the literal `Destination repo:` marker to route work to the correct repo, and a paraphrased heading will not match it.

## Playbooks

- **marketing-pages toolkit items** (`/resources/toolkit` checklists, SOPs, templates sourced from a Google Doc) use a richer schema-bound structure. See [reference/toolkit-playbook.md](reference/toolkit-playbook.md).

## Quality rules

- Use direct, concrete instructions. The ticket should be enough for a developer to start without hunting through comments, the parent, or a linked ticket.
- Preserve the source link in the enriched description even if it already exists in a comment or on a linked ticket.
- Keep descriptions scannable with headings and bullets.
- Do not paste the full source document into Jira unless the user asks. Link to the source and summarize the implementation requirements.
- Do not invent fields that are not supported by the destination schema.
- No em dashes in prose you draft.
- For rich descriptions, always use `tools/md-to-adf` with `--description-file` — never pass raw markdown to `acli --description` (it renders literally). Mechanics and caveats: [tools/md-to-adf/usage.md](../../tools/md-to-adf/usage.md).

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
