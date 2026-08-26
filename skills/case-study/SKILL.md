---
name: case-study
model: opus
effort: high
description: "Draft a Facilitron customer / district case study from raw inputs (interview notes, metrics, a Confluence brief, a Jira ticket) into the standard Challenge, Solution, Results structure. Use when content wants a case study or success story: 'draft a case study for Redondo Beach USD', 'turn these interview notes into a case study', or pasting district/customer notes plus outcomes. Produces a structured markdown draft with pull-quote and metrics, and hands web publishing to the repo-local guide-item / news-item skills after opening a marketing-pages worktree, or to tron:md-to-pdf for a download. Git-free — it drafts; it does not branch, commit, or publish to the content tree."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Draft a case study"
  blurb: "Turns interview notes, metrics, or a brief into a Challenge → Solution → Results customer story with a pull quote."
  when: "You have raw material from a district win and need it shaped into a publishable story."
  category: drafting
  effects: [draft]
  inputs:
    - key: subject
      label: "Customer / district"
      type: text
      required: true
    - key: notes
      label: "Notes & metrics"
      type: textarea
      required: true
      help: "Raw notes, quotes, and numbers to build the case study from."
---

# /case-study — Customer / district case study drafter

## Durable delivery gate

Resolve the durable destination before drafting the case study. Follow
[the durable deliverable contract](../../tools/content/durable-deliverables.md): select Drive or Confluence, capture review/owner/handoff metadata, work in a uniquely created scratch directory, publish through the matching publisher skill, return the complete success block, and clean scratch on success and failure. For a website handoff, the published URL is the approved source consumed by the repo-local `guide-item` or `news-item` skill after the marketing-pages worktree is added; this skill never writes the repository or performs Git work.

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

- Marketing voice: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md) and
  [tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md). The district is the
  protagonist, not Facilitron.
- Lead with the outcome; back every claim with a metric or a quote.
- If a key metric or quote is missing, flag it with `> TODO:` rather than inventing it. Use
  **AskUserQuestion** for the few facts that change the story.

## Output + handoff

Draft `$WORK/<slug>-case-study.md` with this content stub, then publish it to the resolved durable
destination:

```markdown
---
title: "<District> cut scheduling time 60% with Facilitron"
summary: "<one-line>"
customer: "<district>"
metrics: ["60% less admin time", "$X recovered", "N facilities"]
---
```

Then offer the handoff:

- Publish to the web → first use `tron:start-ticket` to create, or `tron:open-worktree` to reopen, a
  marketing-pages worktree and add that directory to the session. The repo-local skills only appear
  in the listing after that directory is added; then invoke bare `guide-item` (long-form) or
  `news-item` (article). These need a git user; the draft is the input.
- Downloadable PDF → `tron:md-to-pdf`.
- Quality pass → `tron:grill` (stress-test claims) before publish.

Confirm before any publish step. End with a short summary: angle, the metrics used, any `TODO:` gaps.
