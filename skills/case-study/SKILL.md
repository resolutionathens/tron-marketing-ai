---
name: case-study
model: opus
effort: high
description: "Draft a Facilitron customer / district case study from raw inputs (interview notes, metrics, a Confluence brief, a Jira ticket) into the standard Challenge → Solution → Results structure, ready to publish or export. Use this skill when content wants to write a case study or success story: 'draft a case study for Redondo Beach USD', 'write up the success story', 'turn these interview notes into a case study', 'case study for MCR-264', or pasting district/customer notes + outcomes. Produces a structured markdown draft (with pull-quote + metrics) and hands publishing to tron:guide-item / tron:news-item (web) or tron:md-to-pdf (downloadable). Git-free — it drafts; it does not branch, commit, or publish to the content tree itself."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
---

# /case-study — Customer / district case study drafter

Turn raw inputs into a publish-ready **case study** in Facilitron's house structure, without losing
the source facts. Git-free: it writes a markdown draft and routes publishing to the right skill.

## When to use

- Writing a customer/district success story (the MCR "Case Studies" initiative).
- You have interview notes, metrics, or a brief and need a structured narrative.

## Inputs (gather what exists)

- **Jira ticket** — `acli jira workitem view <KEY> --json` for scope, links, due date.
- **Confluence brief / interview notes** — pull with `tron:confluence`.
- **Metrics** — booking volume, revenue, hours saved, utilization, time-to-launch. These are the spine.

### Secure the spine before drafting

The Results section _is_ the case study — a draft with an all-`TODO` Results block is a skeleton, not
a usable draft. So **before writing**, check whether the inputs already carry 3–4 quantified outcomes
and a named pull-quote. If they don't (MCR tickets usually don't — most are thin editorial tasks),
**ask for them first** with **AskUserQuestion**: the 3–4 headline metrics and the attributable
customer quote (speaker + title). Only fall back to `> TODO:` for a metric the user genuinely doesn't
have yet — never open with an empty Results block when one question would fill it.

## Structure (Facilitron case study)

1. **Header** — district/customer, region, size; one-line outcome.
2. **Challenge** — the situation before Facilitron (manual scheduling, lost revenue, no visibility).
3. **Solution** — what they adopted (Works, Tickets, Streaming…) and how.
4. **Results** — quantified outcomes, 3–4 metrics, with a customer pull-quote.
5. **Looking ahead** — short forward-looking close + CTA.

## Drafting rules

- Marketing voice: **no em dashes**, plain confident prose, no hype.
- Lead with the outcome; back every claim with a metric or a quote.
- If a key metric or quote is missing, flag it with `> TODO:` rather than inventing it. Use
  **AskUserQuestion** for the few facts that change the story.

## Output + handoff

Write to a draft path (default `/tmp/content/<slug>-case-study.md`) with front matter stub:

```markdown
---
title: "<District> cut scheduling time 60% with Facilitron"
summary: "<one-line>"
customer: "<district>"
metrics: ["60% less admin time", "$X recovered", "N facilities"]
---
```

Then offer the handoff:

- Publish to the web → `tron:guide-item` (long-form) or `tron:news-item` (article). These need a
  git user; the draft is the input.
- Downloadable PDF → `tron:md-to-pdf`.
- Quality pass → `tron:grill` (stress-test claims) before publish.

Confirm before any publish step. End with a short summary: angle, the metrics used, any `TODO:` gaps.
