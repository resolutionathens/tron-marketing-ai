# Ideation Note template

The structured artifact `/brainstorm` produces after Stage 6. Save to a working path
(`/tmp/ideation-<slug>.md`, or alongside the user's notes if they prefer). The
`scripts/brainstorm.sh save` fast path writes this skeleton for you.

```markdown
---
status: ideation
created: YYYY-MM-DD
audience: { specific persona/segment }
format: { article | guide | toolkit item | landing page | campaign | other }
ready_to_produce: false # flip to true once discovery work below is done
---

# Ideation Note — {Short name of the idea}

## Trigger

{Why this came up — 1-2 sentences}

## Audience & Pull

- **Who:** {persona, specific}
- **What they do today:** {current behavior / workaround / search}
- **Evidence of pull:** {search data, repeated questions, sales asks — or "unproven, needs discovery"}

## Hypothesis

> If we {make X for audience Y}, then {outcome} — because {why}.

## Counter-factual

- **Do nothing:** {what happens}
- **Lands perfectly:** {what changes — for the reader and for us}
- **Delta:** {the actual change this produces}

## Risks & Constraints

- {risk 1}
- {risk 2}

## Discovery Work (before producing)

- [ ] {signal to gather — e.g. run /tron-report on {query}}
- [ ] {check: does an existing page already cover this? update vs. new}

## Open Questions

- {anything unresolved}

## Next Step

- Once discovery is done, hand to the right production skill for the idea:
  - **Web content** → `tron:news-item` (article), `tron:guide-item` (guide), `tron:toolkit-item` (SOP/checklist/template).
  - **Campaign / lifecycle** → `tron:email-campaign`, `tron:social-post`.
  - **Narrative / proof** → `tron:case-study`, `tron:press-release`.
  - **A new landing page** → `tron:landing-page-seo` (target keywords + on-page spec).
- Or run `/grill` to stress-test the hypothesis before committing.
```
