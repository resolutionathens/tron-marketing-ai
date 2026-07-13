# Description template — base shape and a worked example

## Base template

Use this base shape. Keep it practical and implementation-ready.

```markdown
# <Action-oriented title>

## Context

<Short explanation of what this ticket is for and the goal it serves. Pull the "why" from the parent epic or campaign when there is one.>

## Sources

- <Source label>: [<url or location>](<url>) — <one-line note on what it is>
- Destination repo: `<repo if known>`
- Destination path or route: `<path or route if known>`
- Work type: `<type>`

## Implementation notes

1. <Concrete first step.>
2. <Schema, component, asset, PDF, or routing guidance.>
3. <QA or verification guidance.>

## Acceptance criteria

- <Expected file, page, or change exists.>
- <The page or asset renders in the expected location.>
- <Links, downloads, images, or metadata work.>
- <Review criteria are satisfied.>
```

Add only the sections a ticket needs. For content/SEO work, add a `## Source SEO fields` section
with meta title, meta description, and slug. For a Figma-driven ticket, list the Figma file, the
page being replaced, and the asset location under `## Sources`. For a marketing-pages landing
page or content ticket, add the existing-page search result (match or no match) under
`## Sources` per [reference/existing-page-search.md](existing-page-search.md). Do not include
empty sections.

The `Destination repo:` and `Destination path or route:` lines are a fixed, machine-parsed
marker, not prose to paraphrase. When the repo is known, emit them exactly as written above:
literal label, backtick-wrapped value, under `## Sources`. Do not rename them into a heading
(e.g. `## Repo / implementation guidance (marketing-pages)`), reword the label, or move the repo
name into a sentence instead. tron-os greps this literal string to route dispatches to the
correct repo; anything else fails to match and falls back to a weaker heuristic.

## Worked example

For a webdev or navigation ticket sourced from a linked Figma design, the enriched description
looks like this:

```markdown
# Add Tickets to the product dropdown and footer

## Context

Part of migrating the Tickets landing page from HubSpot to facilitron.com (parent campaign MCR-321). Once the page exists, it needs entry points: an item in the Product dropdown and a link in the site footer.

## Sources

- Figma design: [Product Pages — Tickets](<figma url with node-id>) — build the page and nav entries to match (from linked MCR-346).
- Page being replaced: <hubspot url> — current Tickets content and layout reference.
- Assets: ImageKit `/product/ticketing` folder.
- Destination repo: `<app repo>`
- Work type: `navigation / webdev`

## Implementation notes

1. Add a Tickets entry to the Product dropdown component, matching the placement in the Figma design.
2. Add a Tickets link to the site footer in the product/links column.
3. Point both at the new Tickets route, not the HubSpot URL.

## Acceptance criteria

- Tickets appears in the Product dropdown and links to the new on-site Tickets page.
- Tickets appears in the footer and links to the same route.
- No remaining links point at the old HubSpot Tickets page.
```
