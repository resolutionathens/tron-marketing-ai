---
name: spotlight
description: "Draft a Facilitron spotlight social post — a new-hire, people, district, facility, or customer spotlight — in the house structure (who/what + a human angle + quote + CTA), with per-platform variants for IG/FB/LI. Use this skill when social wants a spotlight: 'new hire spotlight for X', 'district spotlight for Conejo Valley', 'facility spotlight', 'team member spotlight', 'spotlight post for <name>', or a CCAL spotlight ticket (the New Hire Spotlights / District Spotlights campaigns). Git-free — produces the copy; scheduling happens in the social tools."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
---

# /spotlight — Spotlight post drafter

Draft a Facilitron **spotlight** — the most common recurring social format (new-hire, people,
district/facility, customer) — in the house structure, with IG/FB/LI variants. Git-free. Serves the
CCAL "New Hire Spotlights" and "Facility/District Spotlights" campaigns.

## Pick the spotlight type
| Type | Angle |
|---|---|
| New hire / team | welcome + role + a personal note (fun fact / what they're excited about) |
| People (partner, leader, customer champion) | who they are + their impact + a quote |
| District / facility | the partnership + outcome + a representative quote or stat |
| Customer success | challenge → result, human-first (pairs with `tron:case-study`) |

## Inputs (real facts only)
- Subject name/title, the key facts (role, district, tenure, a quote, a fun fact), and the photo.
- Pull from the ticket + any intake form / Confluence. Missing quote or fact → `> TODO:` and ask via
  **AskUserQuestion**; never invent a person's quote or details.

## Structure (per platform)
```markdown
## Spotlight — <name / district>
**Type:** <new-hire | people | district | facility>  ·  **CTA:** <follow / learn more → url>

### LinkedIn   (lead — spotlights perform best here)
<Warm intro naming the person/place + role. The human angle. "<approved quote>." Close + CTA.>
[image: headshot/facility 1:1 · alt: …]   #FacilitronFamily (3 tags)

### Instagram
<Shorter, warmer, visual-first; same quote trimmed; line breaks.>
[image: 4:5 · alt: …]   (5–8 on-brand hashtags)

### Facebook
<Conversational version; link in post.>
[image: 1:1 · alt: …]
```

## Rules
- Human-first and genuine, not corporate. **No em dashes.** Get names/titles exactly right.
- Never fabricate a quote, role, or fact — flag gaps and confirm.
- Always include alt text and the photo spec.

## Handoff
Write `/tmp/social/<slug>-spotlight.md`. For non-spotlight posts use `tron:social-post`; for a
deeper customer story use `tron:case-study`. Imagery via the designer; scheduling by the owner.
