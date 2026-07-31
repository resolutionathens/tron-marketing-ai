---
name: video-publish
model: opus
effort: medium
description: "Build the publishing kit for a finished video — SEO title, description with timestamped chapters, tags, thumbnail brief, end-screen/CTA, and per-platform cutdown specs (aspect ratios and length for YouTube/IG/FB/LI). Use when video is ready to ship: 'publish kit for the DevFees webinar', 'YouTube title + description for this video', 'chapters for the recording'. Git-free — produces the metadata and specs; the upload happens in YouTube/the social tools."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Prep a video for publishing"
  blurb: "Builds the publishing kit for a finished video: title, description, chapters, tags, and a thumbnail brief."
  when: "The edit is done and it needs everything but the upload."
  category: drafting
  effects: [draft]
  inputs:
    - key: video
      label: "Video link or reference"
      type: text
      required: true
---

# /video-publish — Video publishing kit

## Durable delivery gate

Resolve the durable destination before drafting the publishing kit. Follow
[the durable deliverable contract](../../tools/content/durable-deliverables.md): select Drive or Confluence, capture review/owner/handoff metadata, work in a uniquely created scratch directory, publish through the matching publisher skill, return the complete success block, and clean scratch on success and failure. This skill never writes repository content or performs Git operations.

Produce everything that wraps a finished video for release — title, description, chapters, tags,
thumbnail brief, and the platform cutdown specs. Git-free: it writes the kit; the upload happens in
YouTube / the social schedulers. Serves the webinar-sharing + YouTube-series work.

## Inputs

- The video: working title, length, a 1–2 line summary of content, and (ideal) a rough transcript or
  the `tron:video-brief` script — used for chapters + keywords.
- Target platforms (YouTube primary; IG/FB/LI cutdowns) and the CTA/destination URL.

## The kit

```markdown
# <video> — publishing kit

## YouTube

- **Title:** <≤60 chars, keyword-led, no clickbait>
- **Description:**
  <2–3 line hook + what's covered.>
  Chapters:
  0:00 Intro
  m:ss <section>
  …
  <CTA + link> · <relevant Facilitron links>
- **Tags:** <comma-separated, on-topic>
- **Thumbnail brief:** <subject, text overlay (≤4 words), brand colors / tron- tokens>
- **End screen / cards:** <subscribe + 1 related video + CTA>

## Cutdowns

| Platform   | Aspect      | Length | Notes                                |
| ---------- | ----------- | ------ | ------------------------------------ |
| YouTube    | 16:9        | full   | captions on                          |
| IG/FB Reel | 9:16        | ≤60s   | hook in first 2s, burned-in captions |
| LinkedIn   | 1:1 or 16:9 | ≤90s   | professional framing                 |
```

## Rules

- Titles/descriptions are real SEO surface — front-load the keyword, write for humans. Facilitron voice ([tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md))
  and the brand voice ([tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md)). No
  clickbait titles and no keyword stuffing.
- Chapters must map to actual timestamps; don't invent them — pull from the transcript/brief.
- Accessibility: always note captions/subtitles. Don't fabricate metrics or claims.

## Handoff

Draft `$WORK/<slug>-publish.md` (slug = kebab-case of the title), publish it to the resolved durable
destination, and return the success metadata. For social cutdowns, hand the copy to `tron:social-post`
(per-platform variants). Offer to drop the title/description on the ticket via `tron:jira-comment`
(confirm first). The actual upload/scheduling is done by the owner in YouTube / the social tools.
