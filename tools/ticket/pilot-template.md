# Pilot ticket template (rubric-version: 5)

From the [Ticketing pilot](https://facilitron.atlassian.net/wiki/spaces/MD/pages/4427612174/Ticketing+pilot) page, which
combines Olga Bronin's [template review](https://facilitron.atlassian.net/wiki/x/AQBaBgE) with the MD metadata header.

**This file is the canonical copy** of the pilot template (MD-3405, Ian, Nov 16 2026). It was copied from Baton's
tron-coordinator-do `skills/write-ticket/reference/template.md` at `e6c74b8`; from now on Baton mirrors this file
(SR-6185), not the other way round. The executable form is the pilot section of
[`rubric-lib.sh`](rubric-lib.sh) (`rb_pilot_*`), which `rubric-lint.sh` runs for the pilot types `product`,
`engineering`, `bug`, `data` and `spike`. Change the two together, and bump `rubric-version` here and in
[`ticket-rubric.md`](ticket-rubric.md). Design, content, campaign-asset and cms tickets keep the marker rubric in
`ticket-rubric.md`.

## Contents

- [Where it lives](#where-it-lives)
- [Stages](#stages)
- [Metadata header](#metadata-header)
- [Sections](#sections)
- [Rules](#rules)
- [Sections by type](#sections-by-type)

## Where it lives

An engineering ticket has two parts (SR-5935):

- **The description** is for people: Done, Intent, Stakeholder, Problem, Scope and the ACs in plain language, in the
  shape below. It keeps the `Stakeholder:` line because Baton reads it there to find who decides. Nothing about how.
- **The attachment `<KEY>-engineering.md`** is the brief: this whole template, header and all seven sections. The
  template check, Baton's inspection and Builder read it. With several attachments of that name, the newest is the brief.

```markdown
**Done:** <the observable end state>

**Intent:** <why it matters>

**Stakeholder:** <who decides, comma-separated>

### Problem
As a <role>, I need <capability> so that <outcome>.
Today: <what happens now>.

### Scope
In scope: <…>
Out of scope: <…>
At risk: <…>

### Acceptance criteria
- AC1 <plain language>
- AC2 <…>

The engineering brief (affected paths, decisions, test data, change log) is the attached engineering file.
```

A product ticket has no attachment until kickoff: the whole template is its description. So do tickets written before
SR-5935, which still check against their description. Builder only builds from an attachment, so one of those needs its
brief attached first.

## Stages

| Stage | Jira status | What it means |
|---|---|---|
| created | Backlog, To Do | Filed; the problem and who decides are known |
| ready | Ready to Develop | Product is done: ACs agreed, no Open decisions |
| kickoff | In Progress, In Development | The engineer has filled in the engineering detail |
| review | Dev Review, In Review, QA, Done | Code exists |

## Metadata header

A fenced code block, first in the brief (the attachment, or the description if there is none). Agents read this; one `Key: value` per line.

| Field | What it holds | Who supplies it | Required from |
|---|---|---|---|
| Done | The observable end state | Drafted from the source, stakeholder confirms | created |
| Intent | The reason: the problem or why it matters. Not the same as Done | Drafted from the source, stakeholder confirms | created |
| Type | `product` (written by product) or `engineering`, `bug`, `data`, `spike` | Derived, confirmed | created |
| Deliverable type | `pr`, `research`, `report`… | Derived, confirmed | created |
| Stakeholder | One or more people who decide and sign off, comma-separated | **Asked, never inferred** | created |
| Engineer | Who builds it; "not yet assigned" is fine until ready | **Asked** | ready |
| Context | Link to the source: PRD, Slack thread, Confluence, parent ticket | The source the user names | created |
| Decision | Who decided what, when; who signs off | Asked with the stakeholder | created |
| Acceptance criteria | `- AC1 …` bullets, two or more. Technical wording allowed after kickoff | Drafted, stakeholder confirms | ready |
| Repo | The repository | **Engineer, at kickoff** | kickoff |
| Affected paths | Files or folders the work touches | **Engineer, at kickoff** | kickoff |

## Sections

```
PR: [add PR]   Test Branch: [add link]   Branch: [add name]

## 1. Problem
As a <role>, I need <capability> so that <outcome>.
Today: <what happens now, who it hurts, how often or how much>.

## 2. Scope
In scope: <flows, pages, entry points that change>
Out of scope: <adjacent flows that do NOT change, named explicitly>
At risk: <existing behaviour that must keep working, only if a shared flow is touched>

## 3. Pages & Roles
| Page / entry point (path) | Roles that see or do this | Roles explicitly excluded |
|---|---|---|

## 4. Pre-conditions & Test Data
- Settings, flags or org config:
- Example record or environment link:
- Known environment limits:

## 5. Acceptance Criteria
Same numbers as the header. A change after Ready to Develop edits both and adds a change-log row.

**AC1** <the header's AC1 in plain language, for QA and product>

**AC2** <…>

## 6. Design, Links & Decisions
Figma: <frame>   PRD/Epic: <link>   Related: <tickets>
| Date | Decision or open question | Owner | Status |
|---|---|---|---|

## 7. Change log
| Date | Change | Added / Removed / Changed | Requested by | ACs affected |
|---|---|---|---|---|
```

The PR panel's placeholders may stay as they are: the check doesn't require them, and Baton records a ticket's pull
requests itself.

## Rules

1. **ACs live in two places with the same numbers.** The header is for agents, section 5 for people. After kickoff the
   header may be more technical, and section 5 may be a shorter summary; the two must not conflict.
2. **No Open decisions from ready on.** An unknown becomes a decisions row with an owner, never a placeholder.
3. **After Ready to Develop, every requirement change edits the header AC and section 5 and adds a change-log row.** A
   comment alone doesn't count.
4. **A product ticket says what and why, never how**: no Repo, Affected paths, file names, code, blast radius or fixes. A
   fix the PM suggests becomes an Open decision for the engineer.
5. **Kickoff fills in the brief, on the same ticket.** The description stays as product wrote it. No child ticket,
   except for work across several repos or engineers.
6. **Aim for under ~800 words** in sections 1–7. The header doesn't count.

## Sections by type

| Section | product / engineering | bug | data | spike |
|---|---|---|---|---|
| 1. Problem | Required | Required, as impact | Required: who consumes it, why | Required: the question |
| 2. Scope | Required | If needed | Required | Required: what not to investigate |
| 3. Pages & Roles | Required | Required: where seen, as whom | If needed | — |
| 4. Pre-conditions | Required | Required | If needed | — |
| 5. ACs | Required | Required: expected result | Required: columns, row counts | Deliverable instead |
| 6. Decisions | Required | If needed | If needed | Required |
| 7. Change log | Once dev starts | Once dev starts | Once dev starts | — |

Optional modules, added only when needed (from Olga's template): **Business rule & definitions** (logic, permissions,
money), **Copy** (exact UI, error or email text), **Data spec**, **Bug details** (steps, expected and why, actual,
evidence, impact), **Spike** (question, timebox, deliverable), **Migration / one-time script**. Put them after section 4.
