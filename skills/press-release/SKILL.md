---
name: press-release
model: opus
effort: high
description: "Draft a Facilitron press release in standard PR format — headline, subhead, dateline, body with quotes, boilerplate, and media contact — from a brief or announcement. Use for 'draft a press release', 'write the PR for the Tickets launch', 'press release for the new district partnership', or media-outreach tickets. Produces a ready-to-review markdown draft in AP-style PR structure. Git-free — it drafts; publishing and distribution are a separate step."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Draft a press release"
  blurb: "Writes an AP-style press release — headline, dateline, quotes, boilerplate — from an announcement brief."
  when: "There's news to announce and PR needs a first draft."
  category: drafting
  effects: [draft]
  inputs:
    - key: announcement
      label: "Announcement"
      type: textarea
      required: true
      help: "What's being announced — the news, the who/what/when."
---

# /press-release — Press release drafter

Draft a clean, standard-format **press release** from an announcement brief. Git-free: produces a
review-ready markdown draft. Serves the MCR "Press Releases" and "Media Outreach" initiatives.

## Inputs

- The announcement: what, who, when, why it matters. Pull from the Jira ticket
  (`acli jira workitem view <KEY> --json`) and any Confluence brief (`tron:confluence`).
- **Boilerplate + media contact are standing assets — source them, don't leave them blank.** Pull the
  approved "About Facilitron" boilerplate and the press/media-contact line from the press kit
  (`tron:confluence` "Press Kit" / newsroom page, or the live newsroom at
  `facilitron.com/resources/news`). If you can't reach it, fall back to the standing default below and
  flag it for confirmation — so the **only** real gaps left are the quotes:

  > **About Facilitron** — Facilitron is a facility scheduling, rental, and management platform that
  > helps school districts and public agencies open their spaces to the community, streamline
  > reservations and payments, and recover revenue. Learn more at facilitron.com. _(confirm — standing
  > boilerplate)_

- Approved quotes (exec, partner, customer). These are the genuine `TODO` — don't fabricate them.

## Standard structure

```
FOR IMMEDIATE RELEASE

# <Headline — active, specific, no hype>
### <Subhead — the so-what in one line>

**<CITY, State>, <Month Day, Year> —** <Lead paragraph: the news in 1-2 sentences, most
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
- Facilitron voice in body prose ([tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md))
  and the brand voice, stance, and proof set in
  [tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md). AP-ish style; no marketing
  superlatives in the body. The **dateline** em dash is the one documented exception to the
  no-em-dash rule. Keep the dash *inside* the bolded run (`**<CITY, State>, <Date> —**` or
  `**<CITY, State> — <Date>**`, both of which the corpus uses), because that is exactly what
  `TokenIgnores` exempts in the Vale pack. A second dash after the closing `**` is not exempt and
  will fail the lint.
- Don't fabricate quotes or numbers. Missing quote/stat → `> TODO:` and ask with **AskUserQuestion**
  for the few that matter.

## Output + handoff

Write to `/tmp/content/<slug>-press-release.md`. Offer:

- `tron:grill` for a credibility pass before it goes out.
- `tron:md-to-pdf` for a distributable PDF.
- Posting to the web newsroom → `tron:news-item` (needs a git user).
  Confirm before any outward step. Summarize the angle + any `TODO:` gaps.
