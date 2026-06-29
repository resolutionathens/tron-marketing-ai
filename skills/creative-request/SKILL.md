---
name: creative-request
model: sonnet
effort: medium
description: "Intake a Facilitron creative/design request and turn it into a review-ready design brief + asset plan. Use this skill when a designer is starting a creative ticket — a swag/merch item (hats, tees, totes, pins, towels, lanyards, badges), event collateral or signage (posters, banners, backdrops, napkins, menus), a Figma product page, a onesheet, or any MCR 'Design Request'. Trigger on 'start this design ticket', 'work up a brief for MCR-123', 'what do I need to design here', 'spec this creative request', 'kick off the design for the FU6 backdrop', or pasting a design/creative Jira ticket. Pulls the ticket + any linked Confluence/Figma brief, pins down deliverable specs (dimensions, format, brand tokens, deadline), and produces a brief + checklist; routes the actual asset export to tron:figma-to-imagekit / tron:gen-image. Git-free."
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

# /creative-request — Creative intake → design brief

Turn a raw MCR creative/design ticket into a review-ready design brief and asset plan. Git-free — routes production to `tron:figma-to-imagekit` / `tron:gen-image` / `tron:md-to-pdf`.

## Workflow

### 1. Pull the ticket

```bash
acli jira workitem view <KEY> --json
```

Read: summary, description, issue type, parent Epic/Initiative, assignee, due date, attachments. Note the Marketing Theme it rolls up to.

### 2. Resolve the brief source

- **Confluence brief** → `tron:confluence` or `tools/confluence/fetch-confluence.sh`
- **Figma file/frame** → Figma MCP (`get_design_context`, `get_metadata`, `get_screenshot`)
- **Nothing but the summary** (common for swag) → spec comes from deliverable type + brand defaults

### 3. Determine the deliverable spec

| Deliverable | Lock down |
|------------|-----------|
| **Swag** (hat, tee, tote, pin, towel, sticker) | Print method (embroidery/screen/DTG), garment color, logo lockup + 1-color vs full-color, placement + physical size, Pantone/brand colors, vendor template |
| **Event signage/collateral** (poster, banner, backdrop, popup, napkin, menu) | Finished dimensions + bleed, orientation, resolution (300dpi print), CMYK vs RGB, mount/finish, event branding |
| **Figma product page / web UI** | Target route, breakpoints, design-system components + `tron-` tokens, image export targets |
| **Onesheet / PDF** | Page size (Letter), print vs screen, brand template, export via `tron:md-to-pdf` |

Always capture: deadline, approver, and where the final asset lands (ImageKit folder, route, or print vendor).

### 4. Fill gaps with the requester

Use `AskUserQuestion` with concrete options for anything ambiguous (brand color, exact size, print method, approver). Keep it to the few decisions that change the artifact.

### 5. Write the brief

Save to `/tmp/creative/<KEY>-brief.md`:

```markdown
# <KEY> — <deliverable> creative brief
- **Rolls up to:** <Theme / Initiative>
- **Deliverable:** <type, qty, finished spec>
- **Brand:** <palette / tron- tokens / logo lockup>
- **Specs:** <dimensions, bleed, resolution, color space, print method>
- **Deadline:** <date> • **Approver:** <name> • **Lands at:** <destination>
- **Source brief:** <Confluence/Figma link>

## Checklist
- [ ] Design drafted
- [ ] Brand check (tron:brand-check)
- [ ] Internal review / approval
- [ ] Asset exported (tron:figma-to-imagekit / tron:gen-image / tron:md-to-pdf)
- [ ] Handoff + ticket updated
```

### 6. Route production

- Multi-step production item (swag, event collateral) → offer `tron:board-scaffold` for sub-task chain
- Design in Figma → `tron:figma-to-imagekit`
- Net-new imagery → `tron:gen-image`
- Print PDF → `tron:md-to-pdf`
- Post brief summary to ticket → offer `tron:jira-comment`