---
name: onesheet
model: opus
effort: high
description: "Draft a Facilitron product / feature onesheet — a single-page sell sheet (headline, value props, proof points, how-it-works, CTA) structured for a branded PDF. Use for 'draft a onesheet for Streaming', 'product one-pager for Tickets', 'sell sheet for MCR-265', or 'product summary flyer'. Produces structured markdown ready for tron:md-to-pdf. Git-free — drafts the content; PDF render and asset work are separate steps."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Draft a onesheet"
  blurb: "Builds a one-page sell sheet — headline, value props, proof points, CTA — ready to become a branded PDF."
  when: "Sales or an event needs a single-page product summary."
  category: drafting
  effects: [draft]
  inputs:
    - key: product
      label: "Product / feature"
      type: text
      required: true
    - key: highlights
      label: "Highlights"
      type: textarea
      required: false
      help: "Key benefits or points to lead with (optional)."
---

# /onesheet — Product onesheet drafter

## Durable delivery gate

Resolve the durable destination before drafting the onesheet. Follow
[the durable deliverable contract](../../tools/content/durable-deliverables.md): select Drive or Confluence for the text, capture review/owner/handoff metadata, work in a uniquely created scratch directory, publish through the matching publisher skill, return the complete success block, and clean scratch on success and failure. `tron:md-to-pdf` separately resolves the final PDF's Drive or durable local destination. Neither skill writes repository content or performs Git operations.

Draft a tight one-page **sell sheet** for a Facilitron product or feature, structured so it renders
cleanly to a branded PDF. Git-free. Serves the MCR "Onesheets" initiative.

## Inputs

- The product/feature (Works, Tickets, Streaming, DevFees…) and target audience (district admins,
  renters, athletic directors). Pull context from the Jira ticket + `tron:confluence`.
- Proof points: metrics, customer names, integrations. Real ones only.

## Structure (fits one page)

```markdown
# <Product> — <one-line positioning>

> <Subhead: the core benefit in a sentence.>

## Why <Product>

- <Value prop 1 — benefit, not feature>
- <Value prop 2>
- <Value prop 3>

## How it works

1. <Step>
2. <Step>
3. <Step> (keep to 3)

## Proof

<1–2 metrics or a short customer quote.>

## Get started

<CTA + contact / URL>
```

## Drafting rules

- One page. Ruthless: 3 value props, 3 steps, 1 proof block.
- Benefits over features. Facilitron voice ([tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md))
  and the brand voice, stance, and proof set ([tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md)).
  No unsupported claims (flag gaps with `> TODO:`); pull figures from the proof set rather than
  inventing them.
- Use **AskUserQuestion** only for audience + the single primary CTA if unclear.

## Handoff

Draft `$WORK/<slug>-onesheet.md` (slug = kebab-case of the title), publish the text to the resolved
durable destination, then render with **`tron:md-to-pdf`**, which separately resolves the branded
PDF's durable destination.
If it needs a hero/visual, route imagery through `tron:gen-image` or `tron:figma-to-imagekit`
(designer). Confirm before producing the final PDF. Summarize the positioning + any `TODO:` gaps.
