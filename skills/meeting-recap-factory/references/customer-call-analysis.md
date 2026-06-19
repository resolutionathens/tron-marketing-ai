# Call Analysis Layer

The conditional analysis section added to a recap. It runs in two variants depending on who was in the room.

## When It Runs

- **External variant** — the meeting has at least one external attendee (email domain ≠ `@facilitron.com`):
  a prospect, customer, partner, agency, or vendor. Adds the full **Customer / Partner Call Analysis** below.
- **Internal variant** — all attendees are `@facilitron.com`. Adds the lighter **Internal Call Analysis**.

**Skip entirely** when: the meeting was a pure status check / standup with no decisions or signal, the
recording is under ~5 minutes, or the user asks to skip analysis.

## External Variant — Customer / Partner Call Analysis

Insert between **Discussion Notes** and **Risks & Blockers**:

```markdown
## Customer / Partner Call Analysis

**Who:** {external party / org, from the attendee list}
**Relationship:** {Prospect | Customer | Partner | Agency | Vendor — inferred or asked}
**Temperature:** {Cold | Cool | Neutral | Warm | Hot} — *rationale: {1-2 sentences}*

### Patterns Surfaced
- **Needs:** {explicit needs they described}
- **Wants:** {requests / improvements they asked for}
- **Asks:** {direct asks of us — commitments, follow-ups, materials, demos}
- **Concerns:** {risks, frustrations, or objections they raised}

### Expecting From Us
{Action items from the table above that the external party is waiting on — these need follow-up even if our
internal priorities shift.}
```

### Temperature Calibration

Score on **signals of behavior**, not tone — a polite contact can be Cold, a blunt one can be Hot.

| Score | Signals |
|---|---|
| **Cold** | Disengaged, brief, mentioning alternatives or churn, frustrated, scaling back |
| **Cool** | Asking about competitors, unresolved escalations, a new contact who's reset expectations |
| **Neutral** | Standard transactional conversation, no strong signal either way |
| **Warm** | Asking about more (expansion, advanced use, additional sites), open to being a reference |
| **Hot** | Volunteering as a case study / quote, advocating, expanding, eager to go public |

A warm/hot contact is a natural case-study or testimonial candidate — worth flagging to whoever owns
customer marketing.

## Internal Variant — Internal Call Analysis

```markdown
## Internal Call Analysis

**Momentum:** {Hot | Warm | Neutral | Cool | Cold} — team energy / progress signal
**Patterns Surfaced:**
- **Concerns raised:** {risks, blockers, friction}
- **Decisions deferred:** {items the team didn't commit to, and why}
- **Cross-team asks:** {asks from one person/team to another that could fall through the cracks}
```

## Privacy & Sensitivity

- Keep the analysis in the recap; if a recap is shared externally, the analysis section (temperature,
  internal read of the relationship) is **internal-only** — strip it from any externally-shared copy.
- If the external party makes a sensitive disclosure (legal, financial, personal), flag it for human review
  and keep it out of the structured fields — note it plainly in Discussion Notes only if relevant.
