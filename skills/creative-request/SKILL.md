---
name: creative-request
model: sonnet
effort: medium
description: "Intake a Facilitron creative/design request and turn it into a review-ready design brief + asset plan. Use this skill when a designer is starting a creative ticket — a swag/merch item (hats, tees, totes, pins, towels, lanyards, badges), event collateral or signage (posters, banners, backdrops, napkins, menus), a Figma product page, a onesheet, or any MCR 'Design Request'. Trigger on 'start this design ticket', 'work up a brief for MCR-123', 'what do I need to design here', 'spec this creative request', 'kick off the design for the FU6 backdrop', or pasting a design/creative Jira ticket. Pulls the ticket + any linked Confluence/Figma brief, pins down deliverable specs (dimensions, format, brand tokens, deadline), and produces a brief + checklist; routes the actual asset export to tron:figma-to-imagekit / tron:gen-image. Git-free — does not branch, commit, or open PRs."
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - WebFetch
---

# /creative-request — Creative request intake → design brief

Turn a raw MCR creative/design ticket into a **review-ready design brief and asset plan** a designer
can act on, without losing the thread between the Jira ticket, the brief, and the final asset.

This skill is **git-free**: it reads Jira/Confluence/Figma and writes a brief. It does not create
branches, commit, or open PRs. When it's time to _produce_ the asset, it routes to
`tron:figma-to-imagekit` (export from Figma → ImageKit CDN) or `tron:gen-image` (net-new image).

## When to use

- Starting any MCR **Design Request**, swag/merch item, event collateral/signage piece, Figma
  product page, or onesheet.
- You have a ticket key (e.g. `MCR-296`) or a pasted ticket and need to know _exactly_ what to make.

## When NOT to use

- Pure asset export from a finished Figma design → use `tron:figma-to-imagekit` directly.
- Generating a net-new image from references → use `tron:gen-image` directly.
- Checking a finished asset against brand → use `tron:brand-check`.

## Workflow

### 1. Pull the ticket

Fetch the ticket and its hierarchy (a swag/collateral item is usually a Story/Task under an Epic,
sometimes with its own Design → Approval → Order → Deliver sub-tasks):

```bash
acli jira workitem view <KEY> --json
```

Read: summary, description, issue type, parent (Epic/Initiative), assignee, due date, attachments,
and any links. Note which **Marketing Theme / Initiative** it rolls up to (Brand & Creative, Events
& Conferences, Supply Acquisition…) — that sets the brand context.

### 2. Resolve the brief source

Creative tickets usually point at one of:

- **A Confluence brief** — pull it with `tron:confluence` (or the plugin's
  `tools/confluence/fetch-confluence.sh`).
- **A Figma file/frame** — read it with the Figma MCP (`get_design_context`, `get_metadata`,
  `get_screenshot`) to see what already exists.
- **Nothing but the summary** — common for swag (e.g. "Surf Hat"). Then the spec comes from the
  deliverable type + brand defaults, and you confirm gaps with the requester (Step 4).

### 3. Determine the deliverable spec

Pin down, for the specific deliverable type:

| Deliverable                                                               | Spec to lock                                                                                                                                                           |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Swag / merch (hat, tee, tote, pin, towel, sticker…)                       | print method (embroidery/screen/DTG), garment/item color, logo lockup + 1-color vs full-color, placement + physical size, Pantone/brand colors, vendor template if any |
| Event signage/collateral (poster, banner, backdrop, popup, napkin, menu…) | finished dimensions + bleed, orientation, resolution (print = 300dpi), CMYK vs RGB, mount/finish, event branding (FU6, White Lotus)                                    |
| Figma product page / web UI                                               | target route, breakpoints, design-system components + `tron-` Tailwind tokens, image export targets                                                                    |
| Onesheet / PDF                                                            | page size (US Letter), print vs screen, brand template, export via `tron:md-to-pdf`                                                                                    |

Always capture: **deadline** (ticket due date / event date), **approver**, and **where the final
asset lands** (ImageKit folder, marketing-pages route, or print vendor).

### 4. Fill gaps with the requester

For anything ambiguous or missing (brand color, exact size, print method, approver), use
**AskUserQuestion** with concrete options rather than guessing. Keep it to the few decisions that
actually change the artifact.

### 5. Write the brief

Write a `brief.md` (default to `/tmp/creative/<KEY>-brief.md`, or a path the user gives) with:

```markdown
# <KEY> — <deliverable> creative brief

- **Rolls up to:** <Theme / Initiative / Epic>
- **Deliverable:** <type, qty, finished spec>
- **Brand:** <palette / tron- tokens / logo lockup / event branding>
- **Specs:** <dimensions, bleed, resolution, color space, print method>
- **Deadline:** <date> • **Approver:** <name> • **Lands at:** <ImageKit folder / route / vendor>
- **Source brief:** <Confluence/Figma link>

## Checklist

- [ ] Design drafted (Figma / source)
- [ ] Brand check (tron:brand-check) — palette, type, logo, contrast
- [ ] Internal review / approval (<approver>)
- [ ] Asset exported (tron:figma-to-imagekit / tron:gen-image / tron:md-to-pdf)
- [ ] Handoff (print vendor / marketing-pages / ImageKit) + ticket updated
```

### 6. Route production + post the brief

- For a multi-step production item (swag, event collateral), offer `tron:board-scaffold` to set up
  the standard Design → Approval → Order → Delivered sub-task chain under the ticket.
- When the design exists in Figma → `tron:figma-to-imagekit` to export to the CDN.
- Net-new imagery → `tron:gen-image`.
- Print PDF → `tron:md-to-pdf`.
- Offer to post a short brief summary to the ticket with `tron:jira-comment` (succinct, prose, no
  em dashes) so the requester sees the plan. Posting is the user's call — confirm first.

## Output

A saved `brief.md` plus a short chat summary: deliverable, key specs, deadline/approver, the asset
route chosen, and the open checklist items.
