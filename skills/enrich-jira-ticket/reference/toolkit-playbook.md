# Playbook: marketing-pages toolkit items

Use this richer structure when the user says the work is in `marketing-pages` and the items are `/resources/toolkit` items (checklists, SOPs, templates) sourced from a Google Doc.

This playbook layers on top of the shared [ticket rubric](../../../tools/ticket/ticket-rubric.md)
base shape (see [description-template.md](description-template.md)), not in place of it: the
fenced machine header comes first (`Type: content`, `Deliverable type: toolkit`, and the
content section markers `Destination:`/`Format:`/`SEO target:`/`Draft:`), then this playbook's
richer sections follow.

## Contents

- Enriched description shape
- Toolkit slug handling
- Toolkit category mapping

## Enriched description shape

````markdown
# Publish toolkit item: <Title>

```
Done: Publish <Title> as a /resources/toolkit item
Type: content
Deliverable type: toolkit
Context: <link to the ticket's source Google Doc or Confluence spec>
Decision: <due date, sign-off owner, if known>
Destination: toolkit
Format: <sop|checklist|template>
SEO target: <primary keyword or search intent>
Draft: <google doc url>
```

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

## Toolkit slug handling

If the source gives `Slug: /my-item`, use `my-item`. If not, derive one from the title with lowercase hyphenation. Match the destination filename, public route, PDF filename, and image filename exactly.

## Toolkit category mapping

- Summary starts with `Checklist:` to `checklist`
- Summary starts with `SOP:` to `sop`
- Summary starts with `Template:` to `template`
