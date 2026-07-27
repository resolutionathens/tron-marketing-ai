---
name: creative-request
model: sonnet
effort: medium
fallback:
  cost: medium
  skip_when: "Use tron:creative-request only when starting a new design ticket. If user already has a spec, route directly to the production skill."
  stage_skips:
    - stage: "Spec & fill gaps"
      skip_when: "User provides a complete design spec with all dimensions, format, and brand tokens"
    - stage: "Route production"
      skip_when: "User only wants the brief, not routing to production"
description: "Intake a Facilitron creative/design request and turn it into a review-ready design brief + asset plan — swag/merch, event collateral and signage, a Figma product page, a onesheet, or any MCR 'Design Request'. Use for 'start this design ticket', 'spec this creative request', 'what do I need to design here', or pasting a design/creative Jira ticket. Pulls the ticket plus any linked Confluence/Figma brief and pins down dimensions, format, brand tokens, and deadline; routes the actual asset export to tron:figma-to-imagekit / tron:gen-image. Git-free."
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Prep a creative brief"
  blurb: "Reads a design ticket and its Figma/Confluence links, then produces a review-ready brief and asset plan."
  when: "A creative ticket landed and you want the brief written before design starts."
  category: drafting
  effects: [draft]
  inputs:
    - key: brief
      label: "Brief"
      type: textarea
      required: true
      help: "What to design and why — the creative ask in your words."
    - key: references
      label: "References"
      type: text
      required: false
      placeholder: "Links or ticket keys for inspiration / source assets"
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