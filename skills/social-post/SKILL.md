---
name: social-post
model: opus
effort: high
description: "Draft a Facilitron social post from a topic, asset, or link — a master caption plus per-platform variants for Instagram, Facebook, and LinkedIn, each with the right length, hashtags, CTA, and image/aspect note. Use for 'draft a social post for X', 'IG/FB/LI copy for the Summer Summit recap', 'caption for this', or a CCAL Social Post ticket. For people/district/facility spotlights use tron:spotlight. Git-free — produces copy; scheduling happens in the social tools."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Draft social posts"
  blurb: "Writes a master caption plus Instagram, Facebook, and LinkedIn variants from a topic, link, or asset."
  when: "Something's worth posting and you want platform-ready copy."
  category: drafting
  effects: [draft]
  inputs:
    - key: topic
      label: "Topic, link, or asset"
      type: textarea
      required: true
---

# /social-post — Social post + per-platform variants

## Durable delivery gate

Resolve the durable destination before drafting the social copy. Follow
[the durable deliverable contract](../../tools/content/durable-deliverables.md): select Drive or Confluence, capture review/owner/handoff metadata, work in a uniquely created scratch directory, publish through the matching publisher skill, return the complete success block, and clean scratch on success and failure. This skill never writes repository content or performs Git operations.

Draft a Facilitron social post as a **master caption + IG / FB / LI variants** — matching the
`IG:` / `FB:` / `LI Panel:` sub-task pattern the CCAL board uses. Git-free: produces copy; scheduling
happens in the social tools. For spotlights (new-hire / district / facility / people), use
`tron:spotlight`.

## Inputs

- The subject: an event, link, asset, milestone, or topic. Pull context from the ticket
  (`acli jira workitem view <KEY> --json`) and any linked brief (`tron:confluence`).
- The single primary CTA + destination (registration, blog, site, profile).

## Output (master + variants)

```markdown
## <internal name> — social post

**Master message:** <one-line core idea> · **CTA:** <action → url>

### Instagram

<caption — warm, visual-first; line breaks; 1 CTA. Hashtags (5–10, on-brand) on their own lines.>
[image/video: 1:1 or 4:5 · alt text: …]

### Facebook

<caption — slightly longer ok, link in post; 1–2 hashtags max.>
[image/video: 1:1 or 16:9 · alt text: …]

### LinkedIn

<caption — professional, lead with the insight/value; minimal hashtags (3).>
[image/video: 1:1 or 16:9 · alt text: …]
```

## Rules

- Facilitron voice: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md) and
  [tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md), whose register table gives
  the person, CTA count, and hard nos for a social post.
- Tailor per platform — don't paste the same caption three times. IG is visual + hashtags, FB is
  conversational + link, LI is professional + insight-led.
- Always include **alt text** for the image. Don't invent facts, names, dates, or stats.
- Use **AskUserQuestion** only for the primary CTA / audience if unclear.

## Handoff

Draft `$WORK/<slug>-post.md` (slug = kebab-case of the title), publish it to the resolved durable
destination, and return the success metadata. Source imagery from the designer (`tron:gen-image` /
`tron:figma-to-imagekit`); video cutdowns from `tron:video-publish`. The per-platform sub-tasks can
be filed via the manager's `tron:board-scaffold`. Scheduling is done by the owner in the social tools.
