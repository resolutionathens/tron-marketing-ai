---
name: email-campaign
model: sonnet
effort: medium
description: "Draft a Facilitron marketing or lifecycle email — newsletter (Facility Forward), district launch announcement, onboarding sequence, or product-update email — with subject-line options, preview text, and a structured body with a clear CTA. Use this skill when content wants to write an email or newsletter: 'draft the Facility Forward newsletter', 'write the district launch email', 'onboarding email sequence', 'announcement email for the Tickets launch', or email/lifecycle tickets (MCR Email & Lifecycle theme). Produces review-ready email copy (multiple subject lines, preview text, body, CTA). Git-free — drafts copy; sending happens in the ESP."
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

- Facilitron voice: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md). Short sentences. One primary CTA per email (secondary links ok in a newsletter).
- Subject ≤45 chars where possible; preview text never repeats the subject.
- For a sequence, keep each email to one idea and show the send cadence (e.g. Day 0 / 2 / 5).
- Don't invent product claims or dates. Use **AskUserQuestion** for audience + primary CTA if unclear.

## Handoff

Write to `/tmp/content/<slug>-email.md` (slug = kebab-case of the title). Offer `tron:grill` for a copy pass. Note: the copy is pasted
into the ESP (Customer.io / HubSpot / etc.) by the owner; this skill stops at approved copy.
