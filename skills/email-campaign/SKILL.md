---
name: email-campaign
model: opus
effort: high
description: "Draft a Facilitron marketing or lifecycle email — newsletter (Facility Forward), district launch announcement, onboarding sequence, or product-update email — with subject-line options, preview text, and a structured body with a clear CTA. Use when content wants an email or newsletter: 'draft the Facility Forward newsletter', 'write the district launch email', 'onboarding email sequence'. Produces review-ready copy. Git-free — drafts copy; sending happens in the ESP."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Draft an email"
  blurb: "Writes a newsletter, launch, or announcement email — subject-line options, preview text, body, and CTA."
  when: "You need email copy ready to paste into the ESP."
  category: drafting
  effects: [draft]
  inputs:
    - key: kind
      label: "Email type"
      type: text
      required: true
      placeholder: "newsletter · launch · onboarding · announcement"
    - key: goal
      label: "Goal & key points"
      type: textarea
      required: true
---

# /email-campaign — Email & newsletter drafter

## Durable delivery gate

Resolve the durable destination before drafting the email. Follow
[the durable deliverable contract](../../tools/content/durable-deliverables.md): select Drive or Confluence, capture review/owner/handoff metadata, work in a uniquely created scratch directory, publish through the matching publisher skill, return the complete success block, and clean scratch on success and failure. This skill never writes repository content or performs Git operations.

Draft review-ready email copy for Facilitron's lifecycle and newsletter programs. Git-free: produces
copy; sending lives in the ESP. Serves the MCR Email & Lifecycle initiatives (Facility Forward
newsletter, District Launch Emails, Onboarding Emails, announcements).

## Pick the email type (sets the shape)

| Type                          | Goal                           | Shape                                                                     |
| ----------------------------- | ------------------------------ | ------------------------------------------------------------------------- |
| Newsletter (Facility Forward) | recurring value + roundup      | 3–5 short blocks, each with link; light intro; one primary CTA            |
| District launch announcement  | activate a newly-live district | warm intro, what's now available, how to start, support link              |
| Onboarding (sequence)         | drive first value              | 1 idea per email, single CTA, sequenced (welcome → setup → first booking) |
| Product update / announcement | feature awareness              | headline benefit, what's new, who it's for, CTA                           |

## Inputs

- The brief / roundup items (Jira ticket + `tron:confluence`).
- Audience (renters / districts / admins) and the single primary action you want.

## Output (per email)

```markdown
## <internal name> — <type>

**Subject lines (pick one):**

1. <≤45 chars, benefit-led>
2. <curiosity / specific>
3. <plain / direct>
   **Preview text:** <≤90 chars, complements the subject, no repeat>

**Body:**
<Greeting + one-sentence hook.>
<1–N short blocks. For a newsletter, each block = bold mini-head + 1–2 lines + link.>

**Primary CTA:** <button label> → <url>
```

## Drafting rules

- Facilitron voice: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md) and
  [tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md), whose register table gives
  the person, CTA rule, and hard nos for email. Short sentences, one job per email.
- Subject ≤45 chars where possible; preview text never repeats the subject.
- For a sequence, keep each email to one idea and show the send cadence (e.g. Day 0 / 2 / 5).
- Don't invent product claims or dates. Use **AskUserQuestion** for audience + primary CTA if unclear.

## Handoff

Draft `$WORK/<slug>-email.md` (slug = kebab-case of the title), publish it to the resolved durable
destination, and return the success metadata. Offer `tron:grill` for a copy pass. Note: the copy is pasted
into the ESP (Customer.io / HubSpot / etc.) by the owner; this skill stops at approved copy.
