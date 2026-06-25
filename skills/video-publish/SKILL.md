---
name: video-publish
model: sonnet
effort: low
description: "Build the publishing kit for a finished video — SEO title, description with timestamped chapters, tags, thumbnail brief, end-screen/CTA, and the per-platform cutdown specs (aspect ratios + length for YouTube/IG/FB/LI). Use this skill when video is ready to ship: 'publish kit for the DevFees webinar', 'YouTube title + description for this video', 'chapters for the recording', 'what aspect ratios do I need for socials', or 'edit & share' tickets. Git-free — produces the metadata + specs; the upload happens in YouTube/the social tools."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
---

# /video-publish — Video publishing kit

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

- Titles/descriptions are real SEO surface — front-load the keyword, write for humans. **No em dashes.**
- Chapters must map to actual timestamps; don't invent them — pull from the transcript/brief.
- Accessibility: always note captions/subtitles. Don't fabricate metrics or claims.

## Handoff

Write `/tmp/video/<slug>-publish.md`. For social cutdowns, hand the copy to `tron:social-post`
(per-platform variants). Offer to drop the title/description on the ticket via `tron:jira-comment`
(confirm first). The actual upload/scheduling is done by the owner in YouTube / the social tools.
