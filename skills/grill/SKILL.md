---
name: grill
model: opus
effort: high
description: "Critical-interrogation pass on a piece of marketing content or a brief before it ships — surfaces hidden assumptions, vague claims, missing edge cases, and the pushback a reviewer or customer will have. Use when the user says '/grill', 'grill this', 'grill me on this', 'stress-test this', 'poke holes in', 'red-team this', 'what am I missing', 'pressure-test the copy', or pastes a draft and asks for tough questions before publish. Output is a Grill Memo with prioritized findings and concrete fixes. This finds weakness; it does not check mechanics — pair with /prose-lint (prose), /link-check (links), and /code-review (code)."
allowed-tools:
  - Read
  - Grep
  - Glob
  - AskUserQuestion
scout:
  surface: true
  title: "Stress-test a draft"
  blurb: "Interrogates a draft or brief for weak claims, hidden assumptions, and the pushback a reviewer will have — before they have it."
  when: "Something important is about to ship and you want the hard questions first."
  category: qa
  effects: [report]
  inputs:
    - key: draft
      label: "Draft to stress-test"
      type: textarea
      required: true
      help: "Paste the draft (or a path to it) whose claims to pressure-test."
---

# /grill — Critical Interrogation Pass

Take an existing piece of content and find every weak spot before a reviewer or customer does. `/grill` asks the harder question — _is this argument sound, specific, and complete?_ Mechanical checks belong to `/prose-lint`, `/link-check`, `/code-review`.

## When to use / NOT use

| Use when | Don't use when |
|----------|---------------|
| Before publishing any content | No draft yet — use `/brainstorm` first |
| Before sending a brief to stakeholders | Only want style/terminology — use `/prose-lint` |
| Anytime a draft "feels fine" but you want a real critique | Only want a link audit — use `/link-check` |

## Pipeline

### Step 1 — Identify artifact type

Detect from path: news article (`content/resources/news/`), guide (`pages/resources/guides/`), toolkit item (`content/resources/toolkit/`), landing-page copy (`pages/**/*.vue`), campaign brief, email/social, ideation note. If ambiguous, ask the user.

### Step 2 — Apply the Grill-Me framework (4 dimensions)

Use the per-type checklist from `reference/grill-me.md`:

| Dimension | What it surfaces |
|-----------|-----------------|
| **🔍 Assumption Audit** | Claims stated as fact with no source — "districts want X," "best practice," uncited stats |
| **🎯 Specificity Check** | Vague language pretending to be precise — "streamline," "powerful," benefits with no proof point |
| **⚠️ Edge Case Sweep** | Missing angles — persona the piece ignores, objection it never answers, empty/failure state in a how-to |
| **👁️ Reviewer Lens** | What would each reviewer push back on? Walk SEO, brand/voice, legal/compliance, target persona |

### Step 3 — Prioritize findings

| Severity | Action |
|----------|--------|
| 🔴 **Blocker** | Will cause rework or rejection. Fix before publish. |
| 🟡 **Concern** | Should address but won't block. Address if time allows. |
| 🟢 **Polish** | Minor sharpening, optional. Backlog. |

### Step 4 — Produce the Grill Memo

Save to `/tmp/grill-<slug>.md`. This skill writes the memo only — it does not edit the artifact.

```markdown
# Grill Memo — {Name}
**Verdict:** {Ship-ready | Needs Iteration | Pull Back}
**Artifact:** {path}

## TL;DR
{2 sentences: most important weakness + recommended next step}

## 🔴 Blockers
1. **{Title}** — **What's wrong:** {finding} **Why it matters:** {impact} **Recommended fix:** {proposal} **Where:** {section}

## 🟡 Concerns
- {issue} — {rationale}

## 🟢 Polish
- {minor sharpening}

## What I Did NOT Find Issues With
{Keeps critique calibrated.}

## Next Step
{Right skill to move to.}
```

### Verdict rules

| Verdict             | Threshold                                              |
|---------------------|--------------------------------------------------------|
| **Ship-ready**      | 0 blockers, ≤3 concerns                                |
| **Needs Iteration** | 1+ blockers or 4+ concerns                             |
| **Pull Back**       | Fundamental framing issue — reframe with `/brainstorm` |

## Anti-patterns

❌ Generic critiques — every finding must cite a specific section. ❌ Surface every micro-imperfection in the polish bucket. ❌ Skip "What I Did NOT Find Issues With." ❌ Duplicate mechanical gates (style nits = Vale's job, broken links = lychee's job). ❌ Edit the artifact — produce the memo; the human applies fixes. For very long artifacts, parallelize by section via subagents.