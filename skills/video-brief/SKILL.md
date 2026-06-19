---
name: video-brief
description: "Turn a video request or ticket into a production-ready brief — purpose, audience, key message, script/voiceover, and a shot list — so an editor can go straight to work. Use this skill when video wants to plan a piece: 'brief the support video for X', 'script the DevFees feature video', 'plan the FU recap reel', 'shot list for the webinar cutdown', or a CCAL Video ticket. Produces a brief + script + shot list and points downstream to the production chain (Rough Cut → GFX → Color → Sound → Deliverables) and to remotion-narrated-film for generated/narrated explainers. Git-free — it plans; editing happens in the NLE."
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - Skill
  - WebFetch
---

# /video-brief — Video brief, script & shot list

Turn a video request into a **brief an editor can act on** without back-and-forth. Git-free: it
plans (brief + script + shot list); the edit happens in the editor. Most video work lives on the
**CCAL** board (issue type `Video`, with the Rough Cut → GFX → Color → Sound → Deliverables chain).

## When to use
- Planning a support-video, product-feature video, event recap/cutdown, webinar edit, or YouTube piece.
- You have a CCAL/MCR ticket or a one-line ask and need the brief, script, and shot list.

## Inputs (gather what exists)
- **Ticket** — `acli jira workitem view <KEY> --json` for scope, links, deadline, parent campaign
  (e.g. "All Videos 2026", "Support Videos - 2026").
- **Source material** — existing footage/recording (webinar, demo), a Confluence brief
  (`tron:confluence`), or a product flow to capture.

## Pin down the spec
| Field | Lock |
|---|---|
| Purpose / CTA | what the viewer should know/do after |
| Audience | renters / district admins / athletic directors / internal |
| Format & length | support clip (≤2m), feature (~60s), recap reel, webinar cutdown; platform + aspect (16:9 YouTube, 9:16 social, 1:1) |
| Source | net-new shoot, screen capture, existing webinar/recording, stills |
| Deadline / deliverables | due date, where it ships (YouTube, site, social) |

## Output: brief + script + shot list
Write `/tmp/video/<slug>-brief.md`:

```markdown
# <title> — video brief
- **Purpose / CTA:** …   **Audience:** …   **Length/format:** … (aspect …)
- **Source:** …   **Deadline:** …   **Ships to:** …

## Script / VO
[Scene 1] <on-screen> — "<voiceover line>"
[Scene 2] …

## Shot list
1. <shot — framing, b-roll/screen capture, on-screen text/lower-third>
2. …

## Graphics / assets
- Lower-thirds, title/end cards, captions; source brand assets via the designer
  (tron:figma-to-imagekit / tron:gen-image).
```

## Rules
- Match Facilitron voice: plain, confident, **no em dashes** in on-screen copy.
- Don't pad — every shot earns its place against the length budget.
- Use **AskUserQuestion** only for the few unknowns that change the cut (length, platform, CTA).

## Handoff
- Standard post chain (Rough Cut → GFX/Lower Thirds → Color → Sound → Deliverables) → the manager's
  `tron:board-scaffold` can file those sub-tasks.
- **Generated/narrated explainer** (kinetic typography + TTS + screen recordings) → the global
  `remotion-narrated-film` skill, fed by this script.
- Publishing the finished cut → `tron:video-publish`. Confirm before posting anything to a ticket.
