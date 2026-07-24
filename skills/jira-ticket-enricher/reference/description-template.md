# Description template — base shape and a worked example

## Base template

The base shape is the shared [ticket rubric](../../../tools/ticket/ticket-rubric.md)'s machine
header: a fenced code block of `Key: value` markers (the spine plus the section markers for the
ticket's `Type`), exactly as `tron:create-ticket` writes it. Human prose sections follow, adding
enrich-only context the rubric doesn't carry (source links, richer implementation notes). Keep it
practical and implementation-ready.

````markdown
# <Action-oriented title>

```
Done: <one-line concrete deliverable>
Type: engineering | design | content | campaign-asset | cms
Deliverable type: <value from the rubric's table for this Type>
Context: <link to the brief / Figma / folder / draft that grounds it>
Decision: <due date, sign-off owner, hard constraints — if known>
<the section markers for this Type only — see the rubric's work-type tables>
```

## Context

<Short explanation of what this ticket is for and the goal it serves. Pull the "why" from the parent epic or campaign when there is one.>

## Sources

- <Source label>: [<url or location>](<url>) — <one-line note on what it is>
- Destination repo: `<repo if known>`
- Destination path or route: `<path or route if known>`

## Implementation notes

1. <Concrete first step.>
2. <Schema, component, asset, PDF, or routing guidance.>
3. <QA or verification guidance.>
````

Add only the sections a ticket needs. For content/SEO work, add a `## Source SEO fields` section
with meta title, meta description, and slug. For a Figma-driven ticket, list the Figma file, the
page being replaced, and the asset location under `## Sources`. For a marketing-pages landing
page or content ticket, add the existing-page search result (match or no match) under
`## Sources` per [reference/existing-page-search.md](existing-page-search.md). Do not include
empty sections.

The rubric's `Acceptance criteria:` marker (inside the fenced header, for engineering tickets)
is the ticket's acceptance criteria — do not duplicate it in a second prose section below.

### `Destination repo:` / `Destination path or route:` — kept alongside the rubric markers

These two lines under `## Sources` are enrich-only, not part of the rubric: they predate it and
`tron-os`'s dispatch router (`lib/triage.ts`) still greps the literal `Destination repo:` marker
to route work to the correct repo. The rubric's own `Repo:` marker (inside the fenced header,
engineering tickets only) is the rubric-lint-visible signal; `Destination repo:` is layered on top
for tron-os's existing grep. When the destination repo is known, emit both — the rubric's `Repo:`
marker in the header and `Destination repo:` under `## Sources` — exactly as shown above. Do not
paraphrase `Destination repo:` into a different heading (e.g. `## Repo / implementation guidance
(marketing-pages)`) or fold the repo name into prose elsewhere instead; it is a fixed,
machine-parsed line and a paraphrased heading will not match tron-os's grep.

`Destination path or route:` is a single backtick-wrapped value, not a list — when a ticket has
more than one affected path, that is what the rubric's own `Affected paths:` marker (inside the
fenced header, engineering tickets only) is for. For an **engineering** ticket, `Affected paths:`
already carries the path detail, so omit `Destination path or route:` entirely rather than
duplicate it. Emit `Destination path or route:` only for a **design** or **content** ticket, which
has no `Affected paths:` marker of its own, and give it one value (the single landing route or
path, not a list).

## Worked example

For a webdev or navigation ticket sourced from a linked Figma design, the enriched description
looks like this:

````markdown
# Add Tickets to the product dropdown and footer

```
Done: Add a Tickets entry to the Product dropdown and site footer
Type: engineering
Deliverable type: pr
Context: <figma url with node-id>
Decision: Ian signs off; no due date
Repo: <app repo>
Affected paths: components/ProductDropdown.vue, components/Footer.vue
Acceptance criteria:
- Tickets appears in the Product dropdown and links to the new on-site Tickets page
- Tickets appears in the footer and links to the same route
- No remaining links point at the old HubSpot Tickets page
```

## Context

Part of migrating the Tickets landing page from HubSpot to facilitron.com (parent campaign MCR-321). Once the page exists, it needs entry points: an item in the Product dropdown and a link in the site footer.

## Sources

- Figma design: [Product Pages — Tickets](<figma url with node-id>) — build the page and nav entries to match (from linked MCR-346).
- Page being replaced: <hubspot url> — current Tickets content and layout reference.
- Assets: ImageKit `/product/ticketing` folder.
- Destination repo: `<app repo>`

## Implementation notes

1. Add a Tickets entry to the Product dropdown component, matching the placement in the Figma design.
2. Add a Tickets link to the site footer in the product/links column.
3. Point both at the new Tickets route, not the HubSpot URL.
````
