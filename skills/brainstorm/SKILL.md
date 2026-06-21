---
name: brainstorm
model: opus
effort: high
description: "Collaborative one-question-at-a-time ideation for a marketing idea before you commit to producing it — a content topic, a campaign, positioning, a name, a new landing page. Use when the user says '/brainstorm', 'I have an idea', 'help me think through', 'noodle on this', 'workshop this idea', 'what should we do about', 'what content should we write on', or has a vague hypothesis with no plan yet. Asks one question at a time to surface assumptions, then writes a structured Ideation Note that becomes the input to the content pipeline. Does NOT produce the content itself — it produces the thinking. Output is one Ideation Note."
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
---

# /brainstorm — Collaborative Ideation Workshop

`/brainstorm` is for the fuzzy front end — when you have a hunch ("we should write something about X," "maybe
a campaign around Y") but haven't pinned down the audience, the angle, or whether it's even worth doing. It
runs *upstream* of the content pipeline: the output is an Ideation Note that a content skill
(`tron:news-item`, `tron:guide-item`, `tron:toolkit-item`) can then turn into a real page.

## When to use

- "I've been noodling on a campaign around back-to-school facility prep — what should we explore?"
- "We want to rank for {topic} — what's the content play?"
- "Search Console shows impressions on {query} but no clicks — what could we do about it?"
- Pre-production, when you don't yet have a clear angle or audience
- Greenfield exploration before committing time to a page or campaign

## When NOT to use

- You already have a clear, scoped idea → go straight to the content skill (`tron:news-item`, `tron:guide-item`, `tron:toolkit-item`)
- You have a *draft* and want it stress-tested → use `/grill`
- You want to gather the actual signals (search data) → run `/tron-report` (Search Console)

## Methodology — One Question at a Time

The whole point is to surface assumptions you didn't know you had. **Never dump a list of questions; ask
one, wait, integrate the answer, then ask the next.** A wall of questions short-circuits the discipline.

The conversation has 6 stages. Move to the next only after you've answered the current one.

### Stage 1 — Frame the Problem (not the solution)
Ask: "Before we talk about what to make, what's the problem or pattern you're noticing? What made you bring
this up today?"

Goal: get out of "let's write a blog post" mode and into "what's the actual gap" mode.

### Stage 2 — Identify the Audience
Ask: "Who is this for? Be specific — not 'customers' but 'a K-12 facilities director at a 20-school
district' or 'a parks & rec admin fielding community rental requests.'"

Goal: anchor on a real, specific reader. Generic audience → generic content.

### Stage 3 — Pressure-Test the Interest
Ask: "What does this audience do today instead? Are they actively searching for this, asking us about it, or
is this something we *think* they should care about? How do we know there's real pull?"

Goal: separate real demand (search volume, repeated questions, sales asks) from imagined demand.

### Stage 4 — Imagine the Outcome
Ask: "If we did nothing, what happens? If this lands perfectly, what changes — for the reader, and for us
(ranking, leads, brand, support deflection)?"

Goal: surface the actual delta this produces, not just "more content."

### Stage 5 — Risk & Constraint Check
Ask: "What could make this a bad idea or a weak piece? Thin angle, wrong funnel stage, claims we can't back,
something a competitor already owns, or effort that outweighs the payoff?"

Goal: write the risk list now, while it's cheap to redirect.

### Stage 6 — Inputs & Adjacency
Ask: "What should we look at *before* producing this? Search Console queries, GA behavior, competitor
content, the questions sales/support actually hear, an existing page we'd cannibalize or could update
instead?"

Goal: identify the discovery work (and decide whether a *new* page is even the right move vs. updating one).

## Anti-patterns

- ❌ Dump all 6 questions in one message — it short-circuits the discipline
- ❌ Jump to "here's the outline" before Stage 4 — this skill is about framing, not drafting
- ❌ Suggest angles that aren't grounded in the audience from Stage 2
- ❌ Skip the risk check on an exciting idea — that's where ideas quietly break
- ❌ Produce the content here — that's the content skill's job; this produces the Note

## Output: Ideation Note

After Stage 6, save to a working path: `/tmp/ideation-<slug>.md` (or alongside the user's notes if they
prefer).

```markdown
---
status: ideation
created: YYYY-MM-DD
audience: {specific persona/segment}
format: {article | guide | toolkit item | landing page | campaign | other}
ready_to_produce: false   # flip to true once discovery work below is done
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

## Compensating Actions

To undo this run: delete `/tmp/ideation-<slug>.md`. No external writes are made by this skill.

## Parallelization Note

This skill is conversational and sequential **by design — do not parallelize the 6 stages.** The entire value
is integrating each answer before asking the next question.

## Example Trigger Phrases

- "/brainstorm a campaign around summer facility maintenance"
- "Help me think through what content to write on energy rebates for schools"
- "Workshop a positioning angle for the new scheduling feature"
- "Noodle on whether we should target the parks & rec segment with a guide"
- "What should we do about the drop-off on the pricing page?"
