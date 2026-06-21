# Recap Template

The canonical recap shape produced by `meeting-recap`. Save the populated file locally; if a section
has no content, write "None" rather than dropping the heading.

```markdown
---
title: {Meeting title}
date: {YYYY-MM-DD}
attendees: [{Name (internal|external)}, ...]
external_attendees: {true | false}
created: {YYYY-MM-DD}
---

# {Meeting title} — Recap & Action Items ({Month Day, Year})

## TL;DR
{2-3 sentence summary of what the meeting was about and the most important outcome.}

## Action Items

| Action | Owner | Priority | Due | Status |
|---|---|---|---|---|
| {what needs to happen} | {who} | P0 / P1 / P2 | {date or "—"} | Open |

> Priority: **P0** = blocks something / time-critical, **P1** = important this cycle, **P2** = nice-to-have.

## Key Decisions
1. **{Decision}** — {the context and why it was decided this way}

## Discussion Notes
### {Topic}
- {point, with attribution where known}

## Risks & Blockers
- {risk or blocker, and who/what it affects}

## Next Steps
- {what happens next, and when the group reconvenes if applicable}
```

## Notes

- **Action Items is the load-bearing section.** Every action needs an owner; if the transcript doesn't name
  one, write `(unassigned)` rather than guessing.
- **Attribution:** only attribute a point to a person when the transcript supports it. Unattributed notes are
  fine — invented attribution is not.
- **External meetings** get an extra `## Customer / Partner Call Analysis` section inserted between
  Discussion Notes and Risks & Blockers — see `customer-call-analysis.md`.
