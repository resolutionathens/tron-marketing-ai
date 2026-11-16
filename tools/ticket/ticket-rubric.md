# Ticket rubric — the shared spec (rubric-version: 5)

## Contents

- [Pilot types (rubric-version 5)](#pilot-types-rubric-version-5)
- [Why machine-readable markers](#why-machine-readable-markers)
- [Marker syntax](#marker-syntax)
- [The spine (every ticket)](#the-spine-every-ticket)
- [Work-type sections](#work-type-sections)
- [The verdict mapping](#the-verdict-mapping)
- [The template body](#the-template-body)
- [Adding a work type later](#adding-a-work-type-later)

**Engineering and product tickets use the pilot template.** Since rubric-version 5 (MD-3405), a ticket whose
`Type:` is `product`, `engineering`, `bug`, `data` or `spike` is written and graded against
[pilot-template.md](pilot-template.md), the canonical copy of the Ticketing pilot template. See
[Pilot types](#pilot-types-rubric-version-5) below for how `rubric-lint.sh` grades them. Everything else
in this file (the marker spine, the work-type sections) applies to `design`, `content`, `campaign-asset`
and `cms` tickets, which grade exactly as they did in version 4.

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

## Pilot types (rubric-version 5)

`product`, `engineering`, `bug`, `data` and `spike` follow [pilot-template.md](pilot-template.md): a fenced
metadata header, then sections `## 1. Problem` to `## 7. Change log`. An engineering ticket's description is
for people, and its brief (the whole template) is the attachment `<KEY>-engineering.md`; a product ticket's
whole template is its description until kickoff. `rubric-lint.sh --key` grades the newest
`<KEY>-engineering.md` attachment when there is one, otherwise the description.

A pilot ticket is graded for its **stage**, which comes from its Jira status (`--key`), or from `--stage` or
`--status` for a file or stdin (default `created`):

| Stage   | Jira status                     | What it adds                                                                 |
| ------- | ------------------------------- | ---------------------------------------------------------------------------- |
| created | Backlog, To Do (and anything unrecognised) | `Done`, `Intent`, `Type`, `Deliverable type`, `Stakeholder`, `Context`, `Decision`; section 1 |
| ready   | Ready to Develop                | `Engineer` (not "not yet assigned"); two or more criteria numbered `AC1`, `AC2`… (not for a spike); the type's sections; no Open decision in section 6; the header's AC numbers match section 5's |
| kickoff | In Progress, In Development     | `Repo` (validated as above; a summary `PREFIX:` stands in for a missing one) and `Affected paths` (not for `Deliverable type: research`); section 7, the change log (not for a spike) |
| review  | Dev Review, In Review, QA, Done | nothing more                                                                 |

The sections each type needs from ready on: `bug` 1, 3, 4, 5; `data` 1, 2, 5; `spike` 1, 2, 6; `product`
and `engineering` 1 to 6. Section 7 (the change log) is required once development starts, from kickoff,
for every type but `spike`; Baton's check doesn't require it yet (SR-6185 brings it in line). A numbered
criterion is read without its number, so `AC1 CI is green` is a command gate like `CI is green`. `Deliverable type`
takes any real value for a pilot type (the template lists `pr`, `research`, `report`…).

The verdict ladder is the same four strings:

| Verdict                       | Pilot condition                                                                    |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| `none: needs human direction` | `Done:` missing or a question, or `Deliverable type:` missing                      |
| `low: needs enrichment`       | `Context:` or `Stakeholder:` missing                                               |
| `medium: routable but thin`   | Another field or section the stage requires is missing, or a rule is broken (`problem:` below) |
| `high: actionable`            | Everything the stage requires is present and no rule is broken                     |

The question and uncheckable-criterion rule (SR-6176) applies to pilot criteria at every stage: a criterion
that asks, names nothing to check, or only asserts a command result holds the ticket at `medium`. A product
ticket that names `Repo:` or `Affected paths:` before kickoff breaks a rule (`medium`); a product section that
names code (a file name or a call) only draws a warning.

`rubric-lint.sh` reports pilot gaps by name: `missing.spine` and `missing.section` hold field names
(`Stakeholder`, `Engineer`) and section names (`section 3. Pages & Roles`); broken rules and warnings go to
`issues`; `missing.recommended` is empty. The JSON also carries `template` (`pilot` or `rubric`), `stage`
(null for a marker-rubric type) and `source` (`description`, `attachment:<KEY>-engineering.md`, `file` or
`stdin`). Baton's `lib/ticket-rules/pilot.ts` mirrors these rules (SR-6185); Scout's vendored copy takes
rubric-version 5 in MD-3403.

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
  prefix alone satisfies the routing requirement. The prefix stands in only for a missing `Repo:`: a `Repo:`
  with a real value is still checked entry by entry, so `Repo: marketing-pages, TBD` is a gap even under a
  valid prefix.
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
| `Type:`            | `design` \| `content` \| `campaign-asset` \| `cms` here; `product` \| `engineering` \| `bug` \| `data` \| `spike` use the [pilot template](#pilot-types-rubric-version-5) | yes |
| `Deliverable type:`| Fine-grained deliverable class (see table below)              | yes      |
| `Context:`         | Link to the brief / Figma / folder / draft that grounds it    | yes      |
| `Decision:`        | Due date, sign-off owner, and any hard constraints            | recommended |
| `Intent:`          | One sentence naming the desired user or system outcome, not the selected implementation | recommended |

`Deliverable type:` is the finer-grained signal triage routes on. Allowed values by `Type`:

| `Type`      | `Deliverable type:` values                          |
| ----------- | --------------------------------------------------- |
| engineering | `pr`, `page`, `bugfix`, `config`, `script`, `research` (version 4; a pilot ticket takes any real value) |
| design      | `figma`, `image`, `pdf`, `brand-asset`              |
| content     | `news`, `guide`, `toolkit`, `case-study`, `pdf`     |
| campaign-asset | `image`, `pdf`, `print`, `merch`, `collateral`   |
| cms         | `page-edit`, `bugfix`, `content-update`              |

## Work-type sections

Each `Type` adds a small section. Its markers are **required for a high verdict** but their absence only
drops the ticket to `medium: routable but thin` rather than to `none: needs human direction`. The spine is
what separates "we know what this is" from "we don't."

### engineering

Since rubric-version 5 an engineering ticket is graded against the pilot template
([Pilot types](#pilot-types-rubric-version-5)). The `Repo:`, research and acceptance-criteria rules below
still apply to it: `Repo:` and `Affected paths:` from kickoff, criteria from creation.

| Marker                 | Meaning                                                         |
| ---------------------- | -------------------------------------------------------------- |
| `Repo:`                | Target repo key, or several separated by commas (also stamp the summary `PREFIX:`) |
| `Acceptance criteria:` | Bullet list of checkable, diff-reviewable outcomes             |
| `Affected paths:`      | Files / routes / components the work touches (not for `research`) |

`Repo:` names every repository the work lands in: `Repo: tron-coordinator, tron-coordinator-do` for work that
changes two. Each entry is a repo key or `owner/repo`, optionally with a note in parentheses; the lint checks each
entry's form, not that the repository exists. Free text after a key (`marketing-pages — footer`) no longer
counts: put notes in parentheses. Tools that read it (Facilitron's ticket coordinator searches
only these repositories for a ticket's work) treat each entry separately.

`Deliverable type: research` is engineering work that produces no pull request: a spike, an evaluation, a
comparison or a write-up. It still names the `Repo:` it concerns and has acceptance criteria (the questions
it settles, the write-up it produces), but no `Affected paths:`. Tools that look for a ticket's code skip a
research ticket rather than reporting missing work.

Acceptance criteria describe properties of the change, not process gates. Put commands and their
expected success in the verification prose below the machine header: a reviewer can inspect a diff to
settle “the command reports a stale pointer when the sync file is older than the manifest,” but cannot
settle “`bun run docs:check` exits 0,” “the suite passes,” or “CI is green” from the diff alone.
`rubric-lint.sh` treats those command-result-only criteria as invalid and tells the author to move the
verification into the description.

Each criterion names one thing a person or a browser test can check pass or fail: an address, a text, an
element's state, a response. A question (“shouldn't all staging pages be https?”, or one that opens like a
question, “is the page https”) and a criterion that names nothing to check (“it works”, “as expected”,
“none yet”) are invalid the same way, so the ticket can't grade `high: actionable`: keep the question for
the reviewer and state the outcome instead. A `Done:` that is a question counts as no `Done:`, and an
`Intent:` that is a question as no `Intent:` that still holds the ticket at `medium: routable but thin`. Quoted copy (“Need help?” or "Need help?") is what a page says, not a
question. Baton's drafts are graded by a mirror of these rules (SR-6176).

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

### campaign-asset

Campaign assets are leaf deliverables in a campaign tree. The parent campaign is first class because
it often carries more routing meaning than the leaf ticket's prose.

| Marker        | Meaning                                                       |
| ------------- | ------------------------------------------------------------- |
| `Campaign:`   | Parent campaign path or Jira key chain                         |
| `Asset:`      | Concrete leaf asset being produced                             |
| `Format:`     | File format, dimensions, material, or production specification |
| `Lands:`      | Folder, vendor handoff, channel, or other delivery destination |

### cms

CMS work edits an existing page in a hosted content system. It requires both the authenticated location
where the change is made and the public or preview location where another person can verify the result.

| Marker        | Meaning                                                        |
| ------------- | -------------------------------------------------------------- |
| `CMS:`        | Hosted system that owns the page, such as HubSpot              |
| `Edit URL:`   | Direct editor URL where the change is made; may be auth-gated   |
| `Verify URL:` | Public or preview URL where anyone can inspect the affected page |

### Locator markers

Locator markers are split by what they guarantee:

- **Resolvable locators:** `Figma`, `Draft`, `Edit URL`, and `Verify URL`. Their values point to something
  a person or agent other than the ticket author can open and inspect. A downstream locatability fail-safe
  may be cleared only by one of these markers with a URL value, or by another independently parsed URL.
- **Placement context:** `Campaign`, `Lands`, and `Destination`. These provide real routing context but do
  not guarantee an openable source or verification target, so they must never clear a locatability fail-safe.

The executable sets are separately queryable through `rb_resolvable_locator_markers` and
`rb_placement_context_markers` in `rubric-lib.sh`. A URL in `Context:` still grounds every ticket, but
`Context` remains part of the spine rather than either work-type set.

## The verdict mapping

`rubric-lib.sh` computes the verdict deterministically from marker presence; it mirrors what Scout triage
reports. This is the exact ladder `tron:ticket-lint` surfaces as "as written, Scout sees: …".

| Verdict (canonical string)       | Condition                                                                 |
| -------------------------------- | ------------------------------------------------------------------------- |
| `none: needs human direction`    | `Done:` missing, or `Deliverable type:` missing/invalid for the `Type` |
| `low: needs enrichment`          | Both above valid, but another **spine** marker missing/invalid (`Type`/`Context`) |
| `medium: routable but thin`      | Full spine present, but one or more of the `Type`'s section markers missing (or `Intent:` is a question) |
| `high: actionable`               | Full spine **and** every section marker for the `Type` present            |

These four strings are the contract: `rubric-lib.sh` emits them verbatim and `tron:ticket-lint` surfaces
them as "as written, Scout sees: `<verdict>`". Do not reword them without bumping `rubric-version`.

`Decision:` and `Intent:` are recommended, not required: their absence never lowers the verdict below
`high`, but the lint still flags them. Write `Intent:` only when source evidence establishes the outcome;
do not infer or invent it from a proposed implementation. It describes the outcome a user or system should
achieve, rather than the implementation selected to achieve it.

## The template body

For `product`, `engineering`, `bug`, `data` and `spike`, `tron:create-ticket` writes the
[pilot template](pilot-template.md) instead. For the other types it writes this shape: the machine header
(fenced marker block) first, then the human prose. Include only the section markers for the ticket's `Type`.
The engineering examples below show the version 4 marker block; since version 5 the same markers sit in the
pilot header, next to `Stakeholder`, `Engineer` and numbered criteria. Worked example of the version 4 shape:

````markdown
# Swap the BAS logo across the footer

```
Done: Replace the legacy BAS logo in the footer sitewide
Type: engineering
Deliverable type: pr
Context: https://figma.com/file/abc?node-id=1:2
Decision: 2026-07-20; Ian signs off; keep the current footer layout
Intent: Visitors can recognize the current BAS brand consistently across the site
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

A **research** ticket keeps `Repo:`, drops `Affected paths:`, and states what it settles:

```
Done: A write-up comparing Flue and Pi Durable for the coordinator, with a recommendation
Type: engineering
Deliverable type: research
Context: https://facilitron.atlassian.net/wiki/x/FgD9BgE
Repo: tron-coordinator, tron-coordinator-do
Acceptance criteria:
- the write-up compares crash recovery, streaming and approvals in both frameworks
- it recommends one, with what that choice costs
```

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

# campaign-asset
Campaign: <parent campaign path or Jira key chain>
Asset: <concrete leaf asset>
Format: <format / dimensions / material>
Lands: <folder / vendor / channel>

# cms
CMS: <hosted CMS name>
Edit URL: <direct editor URL, may require authentication>
Verify URL: <public or preview URL>
```

## Adding a work type later

The spine is designed so a new `Type` slots in without reworking it:

1. Add the `Type` value and its `Deliverable type:` values to the tables above and bump `rubric-version`.
2. Add a work-type section with its required markers.
3. Add the `Type` and its section markers to `rb_deliverable_types` and `rb_section_markers` in `rubric-lib.sh`, and a case to
   `test-rubric-lint.sh`.
4. Mirror the change in the `tron-os` triage fixtures.

Nothing in the spine or the verdict ladder changes — only the section table grows.
