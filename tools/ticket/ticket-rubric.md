# Ticket rubric — the shared spec (rubric-version: 1)

The one rubric behind three consumers:

1. **`tron:create-ticket`** — enforces this rubric on new tickets.
2. **Scout triage** (`tron-os`, MD-2104) — scores an existing ticket against these same signals.
3. **`tron:ticket-lint`** — checks a ticket (or a whole board) against this rubric and reports the gaps.

A ticket that follows this rubric is high-confidence *by construction*, because the rubric's required
fields are exactly what triage keys on: deliverable / definition of done, work type, context link, and
the decision/owner. Templated in, high-confidence out.

This file is a **cross-repo contract** (like `WORKER_CONTRACT.md`). The `rubric-version` above is bumped
when the marker set or the verdict mapping changes; `tron-os` triage reads the same version. If you change
a marker key or the verdict table here, the `repoForSummaryPrefix`-style fixtures on the SCOUT side must
change too, and vice versa. Keep the deterministic parser (`tools/ticket/rubric-lib.sh`) in lockstep with
the marker table below — the parser is the executable form of this spec and its `test-rubric-lint.sh`
sibling is the regression net.

## Contents

- [Why machine-readable markers](#why-machine-readable-markers)
- [Marker syntax](#marker-syntax)
- [The spine (every ticket)](#the-spine-every-ticket)
- [Work-type sections](#work-type-sections)
- [The verdict mapping](#the-verdict-mapping)
- [The template body](#the-template-body)
- [Adding a work type later](#adding-a-work-type-later)

## Why machine-readable markers

Triage can *infer* work type and deliverable from prose, but inference is exactly what makes a thin ticket
"needs human direction." The fix is to write the signals as deterministic `Key: value` markers so triage
parses them instead of guessing. This is the concrete bridge from *templated* to *high-confidence*: the
markers below are the contract, the prose around them is for the human.

## Marker syntax

- One marker per line, at the start of the line: `Key: value`.
- Keys are matched **case-insensitively** and the trailing colon is required.
- A marker counts as **present** only when it has a non-empty value that is not a bare placeholder
  (`TBD`, `TODO`, `???`, `<...>`, `-`, `n/a` all count as empty). "Present but empty" is a gap, not a pass.
- `Acceptance criteria:` may be a single line or introduce a bullet list beneath it; either counts as present.
- `Repo:` is satisfied *either* by the marker *or* by a valid summary `PREFIX:`
  (see [tools/jira/conventions.md](../jira/conventions.md)) — engineering tickets should carry both, but the
  prefix alone satisfies the routing requirement.
- **The whole marker block goes in one fenced code block** at the top of the description (the "machine
  header"), then the human prose sections follow. This is not cosmetic: `acli` stores descriptions as ADF,
  and md-to-adf collapses ordinary consecutive lines into one space-joined paragraph (and turns bare URLs
  into smart-link nodes that split the value off its `Key:`). A fenced code block preserves one marker per
  line with literal URLs, so triage and `tron:ticket-lint` parse the same markers `tron:create-ticket` wrote.
  Repeat any link you want clickable as a normal link in the prose below.

## The spine (every ticket)

| Marker             | Meaning                                                        | Required |
| ------------------ | ------------------------------------------------------------- | -------- |
| `Done:`            | One line naming the concrete deliverable (definition of done) | yes      |
| `Type:`            | `engineering` \| `design` \| `content`                        | yes      |
| `Deliverable type:`| Fine-grained deliverable class (see table below)              | yes      |
| `Context:`         | Link to the brief / Figma / folder / draft that grounds it    | yes      |
| `Decision:`        | Due date, sign-off owner, and any hard constraints            | recommended |

`Deliverable type:` is the finer-grained signal triage routes on. Allowed values by `Type`:

| `Type`      | `Deliverable type:` values                          |
| ----------- | --------------------------------------------------- |
| engineering | `pr`, `page`, `bugfix`, `config`, `script`          |
| design      | `figma`, `image`, `pdf`, `brand-asset`              |
| content     | `news`, `guide`, `toolkit`, `case-study`, `pdf`     |

## Work-type sections

Each `Type` adds a small section. Its markers are **required for a high verdict** but their absence only
drops the ticket to `medium: routable but thin` rather than to `none: needs human direction`. The spine is
what separates "we know what this is" from "we don't."

### engineering

| Marker                 | Meaning                                                         |
| ---------------------- | -------------------------------------------------------------- |
| `Repo:`                | Target repo key (also stamp the summary `PREFIX:`)             |
| `Acceptance criteria:` | Bullet list of checkable outcomes                              |
| `Affected paths:`      | Files / routes / components the work touches                  |

### design

| Marker        | Meaning                                             |
| ------------- | --------------------------------------------------- |
| `Figma:`      | Figma file / frame URL                              |
| `Format:`     | Output format and dimensions                        |
| `Brand refs:` | Palette / `tron-` tokens / logo guidance to follow  |
| `Lands:`      | Where the asset lands (page, CDN folder, deck)      |

### content

| Marker        | Meaning                                                   |
| ------------- | --------------------------------------------------------- |
| `Destination:`| `news` \| `toolkit` \| `guide` (the `/resources` surface) |
| `Format:`     | Article / checklist / SOP / template / PDF                |
| `SEO target:` | Primary keyword or search intent                          |
| `Draft:`      | Link to the source draft (Google Doc, Confluence)         |

## The verdict mapping

`rubric-lib.sh` computes the verdict deterministically from marker presence; it mirrors what Scout triage
reports. This is the exact ladder `tron:ticket-lint` surfaces as "as written, Scout sees: …".

| Verdict (canonical string)       | Condition                                                                 |
| -------------------------------- | ------------------------------------------------------------------------- |
| `none: needs human direction`    | `Done:` **or** `Deliverable type:` missing (triage can't tell what it is) |
| `low: needs enrichment`          | Both above present, but another **spine** marker missing (`Type`/`Context`) |
| `medium: routable but thin`      | Full spine present, but one or more of the `Type`'s section markers missing |
| `high: actionable`               | Full spine **and** every section marker for the `Type` present            |

These four strings are the contract: `rubric-lib.sh` emits them verbatim and `tron:ticket-lint` surfaces
them as "as written, Scout sees: `<verdict>`". Do not reword them without bumping `rubric-version`.

`Decision:` is recommended, not required: its absence never lowers the verdict below `high`, but the lint
still flags it so due dates and sign-off owners do not silently go missing.

## The template body

`tron:create-ticket` writes this shape: the machine header (fenced marker block) first, then the human prose.
Include only the section markers for the ticket's `Type`. Worked example for an **engineering** ticket:

````markdown
# Swap the BAS logo across the footer

```
Done: Replace the legacy BAS logo in the footer sitewide
Type: engineering
Deliverable type: pr
Context: https://figma.com/file/abc?node-id=1:2
Decision: 2026-07-20; Ian signs off; keep the current footer layout
Repo: marketing-pages
Affected paths: components/Footer.vue
Acceptance criteria:
- new logo renders in the footer sitewide
- old asset is removed from the bundle
```

## Context

Part of the rebrand rollout. The footer still shows the legacy mark. Build to the
[Figma frame](https://figma.com/file/abc?node-id=1:2).
````

Swap the section markers for the ticket's `Type`:

```
# design
Figma: <url>
Format: <format + dimensions>
Brand refs: <palette / tokens / logo>
Lands: <where the asset lands>

# content
Destination: <news | toolkit | guide>
Format: <article | checklist | SOP | template | PDF>
SEO target: <primary keyword / intent>
Draft: <source draft url>
```

## Adding a work type later

Social is deliberately out of scope for now (MD-2105). The spine is designed so a new `Type` slots in
without reworking it:

1. Add the `Type` value and its `Deliverable type:` values to the tables above and bump `rubric-version`.
2. Add a work-type section with its required markers.
3. Add the `Type` and its section markers to `TYPE_SECTIONS` in `rubric-lib.sh`, and a case to
   `test-rubric-lint.sh`.
4. Mirror the change in the `tron-os` triage fixtures.

Nothing in the spine or the verdict ladder changes — only the section table grows.
