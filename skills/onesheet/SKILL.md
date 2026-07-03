---
name: onesheet
model: sonnet
effort: medium
description: "Draft a Facilitron product / feature onesheet — a single-page sell sheet (headline, value props, proof points, how-it-works, CTA) structured for a branded PDF. Use this skill when content/product-marketing wants a onesheet, sell sheet, one-pager, or product summary flyer: 'draft a onesheet for Streaming', 'product one-pager for Tickets', 'sell sheet for MCR-265', 'product summary flyer for Streaming', or onesheet tickets. Produces structured markdown ready for tron:md-to-pdf. Git-free — drafts the content; PDF render + asset work are separate steps."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
---

# /onesheet — Product onesheet drafter

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
- Benefits over features. **No em dashes.** No unsupported claims (flag gaps with `> TODO:`).
- Use **AskUserQuestion** only for audience + the single primary CTA if unclear.

## Handoff

Write to `/tmp/content/<slug>-onesheet.md` (slug = kebab-case of the title), then render with **`tron:md-to-pdf`** for the branded PDF.
If it needs a hero/visual, route imagery through `tron:gen-image` or `tron:figma-to-imagekit`
(designer). Confirm before producing the final PDF. Summarize the positioning + any `TODO:` gaps.
