---
name: grill
description: "Critical-interrogation pass on a piece of marketing content or a brief before it ships — surfaces hidden assumptions, vague claims, missing edge cases, and the pushback a reviewer or customer will have. Use when the user says '/grill', 'grill this', 'grill me on this', 'stress-test this', 'poke holes in', 'red-team this', 'what am I missing', 'pressure-test the copy', or pastes a news/cluster article draft, a guide, a toolkit SOP, a landing-page section, a campaign brief, or an email and asks for tough questions before publish. Output is a Grill Memo with prioritized findings and concrete fixes. This finds weakness; it does not check mechanics — pair with /vale-prose-lint (prose), /lychee-link-check (links), and /code-review (code)."
allowed-tools:
  - Read
  - Grep
  - Glob
  - AskUserQuestion
---

# /grill — Critical Interrogation Pass

`/brainstorm` is open-ended ideation. `/grill` is the opposite: take an existing piece of content and find
every weak spot before a reviewer — or a customer — does. It is the substance critique that sits alongside
the mechanical gates: `/vale-prose-lint` catches style and terminology, `/lychee-link-check` catches broken
links, `/code-review` catches code bugs. `/grill` asks the harder question — *is this argument sound,
specific, and complete?*

## When to Use

- Before publishing a news/cluster article, guide, or toolkit SOP
- Before sending a campaign brief or messaging doc to a stakeholder
- Before a landing-page copy change goes to review
- Before an email or social post goes out
- Anytime a draft feels "fine" but you want a real critique, not a rubber stamp

## When NOT to Use

- You don't have a draft yet — use `/brainstorm` first
- You only want a style/terminology pass — use `/vale-prose-lint`
- You only want a link audit — use `/lychee-link-check`
- The artifact is code — use `/code-review`

> **`/grill` vs the gates:** `/grill` finds weakness in the *substance*. The gates check *mechanics*. Run
> `/grill` to make the argument stronger; run the gates to confirm it's clean. Most pieces want both.

## Prerequisites

- **Target artifact** — a file path (e.g. `content/resources/news/<slug>.md`) or pasted content
- **Grill-Me framework** — `references/grill-me.md` (the four dimensions + per-artifact checklists)

## Pipeline

### Step 1 — Identify Artifact Type

Detect the type from the path or content, then load that type's checklist from `references/grill-me.md`:

- News / cluster article (`content/resources/news/`)
- Guide (`content/resources/guides/`)
- Toolkit item — SOP / checklist / template (`content/resources/toolkit/`)
- Landing-page / product-page copy (`pages/**/*.vue` prose, hero/section copy)
- Campaign or messaging brief
- Email / social post
- Ideation Note (output of `/brainstorm`)

If the type is ambiguous, ask the user before grilling — the checklist is type-specific.

### Step 2 — Run the Grill-Me Framework

Apply the four dimensions from `references/grill-me.md`. Write findings down as you go — don't filter yet.

| Dimension | What It Surfaces |
|---|---|
| **Assumption Audit** | Claims stated as fact with no source — "districts want X," "everyone knows," "best practice," uncited stats |
| **Specificity Check** | Vague language pretending to be precise — "streamline," "powerful," "easy," benefits with no proof point or number |
| **Edge Case Sweep** | Missing angles — a persona the piece ignores, an objection it never answers, a claim that doesn't hold for part of the audience, an empty/failure state in a how-to |
| **Reviewer Lens** | What would each reviewer push back on? Walk SEO, brand/voice, legal/compliance, and the target persona (see framework) |

### Step 3 — Prioritize Findings

Sort into three buckets:

| Severity | Definition | Action |
|---|---|---|
| 🔴 **Blocker** | Will cause rework or a reviewer/customer to reject — wrong audience, unsupported claim, factual risk | Fix before publish |
| 🟡 **Concern** | Should address but won't block — a weak section, a thin proof point | Note and address if time allows |
| 🟢 **Polish** | Minor sharpening, optional | Backlog |

### Step 4 — Produce the Grill Memo

Save to a working path: `/tmp/grill-<slug>.md` (or alongside the artifact if the user prefers). This is a
read-and-critique skill — it writes the memo and nothing else; it does not edit the artifact.

```markdown
---
status: complete
created: YYYY-MM-DD
artifact_grilled: {file path or "pasted content"}
artifact_type: News article | Guide | Toolkit SOP | Landing copy | Brief | Email/Social
verdict: Ship-ready | Needs Iteration | Pull Back
---

# Grill Memo — {Artifact name}

**Verdict:** {Ship-ready | Needs Iteration | Pull Back}
**Artifact:** {path} ({type})

## TL;DR
{2 sentences: the most important weakness, and the recommended next step.}

## 🔴 Blockers
1. **{Issue title}**
   - **What's wrong:** {specific finding}
   - **Why it matters:** {who pushes back, what breaks downstream}
   - **Recommended fix:** {concrete proposal — not "rewrite this section"}
   - **Where:** {section / heading / line}

## 🟡 Concerns
- {issue} — {1-line rationale}

## 🟢 Polish
- {minor sharpening opportunity}

## What I Did NOT Find Issues With
{Brief callout of what's strong — keeps the critique calibrated and prevents nitpicking everything.}

## Next Step
- **Ship-ready:** run the mechanical gates (`/vale-prose-lint`, `/lychee-link-check`) and publish via the
  right content skill (`tron:news-item`, `tron:guide-item`, `tron:toolkit-item`).
- **Needs Iteration:** address blockers, then re-run `/grill` or move to the gates.
- **Pull Back:** the piece has a framing problem (wrong audience, wrong angle, missing premise) — return to
  `/brainstorm` to reframe before polishing.
```

### Step 5 — Verdict Rules

- **Ship-ready** = zero blockers, ≤3 concerns
- **Needs Iteration** = 1+ blockers OR 4+ concerns
- **Pull Back** = fundamental framing issue (wrong audience, wrong problem, unsupported premise) — recommend
  reframing upstream with `/brainstorm` rather than patching

## Anti-patterns

- ❌ Generic critiques — every finding must cite a specific section/line
- ❌ Surface every micro-imperfection — the polish bucket exists, but don't pad it
- ❌ Skip the "What I Did NOT Find Issues With" section — it forces calibrated critique
- ❌ Recommend solutions you haven't pressure-tested — propose direction, not a detailed rewrite
- ❌ Run on a draft that doesn't exist yet — that's `/brainstorm`'s job
- ❌ Duplicate the mechanical gates — don't flag style nits (Vale's job) or broken links (lychee's job); grill the *substance*
- ❌ Edit the artifact — `/grill` produces a memo; the human (or a content skill) applies the fixes

## Parallelization

For very long artifacts (a 3,000-word cluster article, a multi-section campaign brief), parallel dispatch by
section can help — spawn one subagent per major section to grill it, then an aggregator merges findings into
a single Grill Memo. Default to sequential for normal-sized drafts (single pass, faster for small inputs).

## Example Trigger Phrases

- "/grill the preventive-maintenance cluster article"
- "Grill me on this guide before I publish it"
- "Stress-test the new landing-page hero copy"
- "Poke holes in this campaign brief"
- "Red-team this email before it goes out"
- "What am I missing in this toolkit SOP?"
