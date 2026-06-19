---
name: press-release
description: "Draft a Facilitron press release in standard PR format — headline, subhead, dateline, body with quotes, boilerplate, and media contact — from a brief or announcement. Use this skill when content/PR wants to announce something: 'draft a press release', 'write the PR for the Tickets launch', 'announcement for MCR-273', 'press release for the new district partnership', or media-outreach tickets. Produces a ready-to-review markdown draft in AP-style PR structure. Git-free — it drafts; publishing/distribution is a separate step."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
---

# /press-release — Press release drafter

Draft a clean, standard-format **press release** from an announcement brief. Git-free: produces a
review-ready markdown draft. Serves the MCR "Press Releases" and "Media Outreach" initiatives.

## Inputs
- The announcement: what, who, when, why it matters. Pull from the Jira ticket
  (`acli jira workitem view <KEY> --json`) and any Confluence brief (`tron:confluence`).
- Approved quotes (exec, partner, customer) and the official boilerplate. If the boilerplate isn't
  provided, use the standard Facilitron boilerplate and flag it for confirmation.

## Standard structure
```
FOR IMMEDIATE RELEASE

# <Headline — active, specific, no hype>
### <Subhead — the so-what in one line>

**<CITY, State> — <Month Day, Year>** — <Lead paragraph: the news in 1–2 sentences, most
newsworthy first (inverted pyramid).>

<Body paragraph 1: context + detail.>

"<Quote from a Facilitron exec>," said <Name>, <Title> at Facilitron.

<Body paragraph 2: customer/partner angle or proof point.>

"<Quote from customer/partner>," said <Name>, <Title>.

<Closing paragraph: availability, next steps, CTA.>

### About Facilitron
<Boilerplate paragraph.>

**Media Contact**
<Name> · <email> · facilitron.com
```

## Drafting rules
- Inverted pyramid: the news leads, detail follows.
- **No em dashes**; AP-ish style; third person; no marketing superlatives in the body.
- Don't fabricate quotes or numbers. Missing quote/stat → `> TODO:` and ask with **AskUserQuestion**
  for the few that matter.

## Output + handoff
Write to `/tmp/content/<slug>-press-release.md`. Offer:
- `tron:grill` for a credibility pass before it goes out.
- `tron:md-to-pdf` for a distributable PDF.
- Posting to the web newsroom → `tron:news-item` (needs a git user).
Confirm before any outward step. Summarize the angle + any `TODO:` gaps.
