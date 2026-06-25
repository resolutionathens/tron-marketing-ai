# Toolkit item schema & conversion reference

Reference material for `tron:toolkit-item`. Load this when authoring the destination
markdown — front-matter options, the page chrome the slug renderer supplies, the two
MDC components, the per-category skeleton, and the source-to-toolkit conversion rules.
The workflow steps and judgment calls stay in `SKILL.md`.

## Contents

- Front matter
- What the slug page renders for you — do NOT author these
- Components used in toolkit bodies
- Structure by category
- Source-to-toolkit conversion rules
- Internal-link reference

## Front matter

Write the destination file at `content/resources/toolkit/<slug>.md` with this front matter:

```yaml
---
title: <Title from source, sentence case or title case>
date: <today's date in YYYY-MM-DD>
description: <1–2 sentence summary; shown in the hero AND used as the default meta description>
image: <slug>.webp
category: sop | checklist | template
download: <slug>.pdf
meta_title: <optional SEO <title> override; keep under ~60 chars>
meta_description: <optional SEO meta override; distinct from description, keyword-rich, ~150–160 chars>
---
```

Schema source: `content.config.ts` `toolkit` collection.

- **Required:** `title`, `description`, `date`, `category` (a Zod enum — `sop`,
  `checklist`, `template`; invalid values fail the Nuxt build).
- **Optional:** `image`, `download`, `meta_title`, `meta_description`. The two
  `meta_*` fields override `title`/`description` for the page `<title>` and meta tags
  only (`[...slug].vue` falls back to `title`/`description` when they're absent) — set
  them when you want SEO copy that differs from the on-page hero. Most recent items do;
  check a sibling for the house style.

## What the slug page renders for you — do NOT author these

The patterns below come from the existing toolkit items and the slug renderer
(`pages/resources/toolkit/[...slug].vue`). The page is mostly chrome you must not
duplicate in the markdown body:

- **Hero** (`SectionHeroProduct`) shows an **eyebrow** = the category label (auto from
  `category`: `sop` → "Standard Operating Procedure", `checklist` → "Checklist",
  `template` → "Template"), then the `title`, the `description`, and a **Download PDF**
  button (when `download:` is set). So: don't repeat the title as an `#` H1, don't
  restate the category in the title, and don't write a download link in the body.
- A **second Download PDF button** auto-renders after the body, followed by a
  **social-share** row.
- A **"Schedule a Demo" CTA** (`SectionBasicCta`) closes every page — don't author
  your own closing CTA.
- **SEO** — Article JSON-LD and meta tags are emitted automatically from front matter.
- The body renders inside Tailwind **`.prose`** at `max-w-6xl`, so plain markdown
  (headings, tables, lists, bold) is styled automatically — no wrapper classes.

## Components used in toolkit bodies

Only two MDC block components appear in toolkit items — **`::checklist-group`** and
**`::faq`**. Everything else is plain markdown (`##`/`###` headings, paragraphs, `-`
bullets, pipe tables). `::image-text` and `::fImg` are **news-article** components —
do not use them here.

- **`::checklist-group`** (`components/content/ChecklistGroup.vue`) — wraps plain
  `- item` bullets; CSS draws the checkbox via `::before`. Use one group per logical
  checklist section (e.g. one per room or area). Never write `- [ ]` inside it
  (double box — see pitfalls in `SKILL.md`).
- **`::faq`** (`components/content/Faq.vue`) — `faqItems: [{question, answer}, …]`;
  renders its own "FAQ" heading and emits FAQPage JSON-LD. Don't add a `## FAQ`
  heading above it.

## Structure by category

Every page opens with a 1–2 paragraph intro (no heading), then follows a consistent
skeleton:

- **`sop`** → `## What is <X>?` → `## Procedure: How to <X>` with numbered
  `### 1. … ### N.` steps → optional `## Compliance & Regulatory Standards` →
  `::faq`. SOPs use numbered steps — no `::checklist-group`, no tables.
- **`checklist`** → `## What Is / What Does <X> Include?` → a `## … Checklist`
  (often "…by Facility Area") section holding several `### <Area> Checklist`
  subsections, **each wrapping a `::checklist-group`** → usually a "Why it matters"
  or "Tips" section. Checklists typically have **no** `::faq`; a frequency table is
  optional.
- **`template`** → `## What Is <X>?` → `## Free <X> Templates` (or `## <X> Template`)
  presenting one or more **markdown tables** (e.g. `### Template 1/2/3`) →
  `## What to Include` / `## How to Use` → `::faq`. Templates are table-driven, not
  checklist-driven.

(The PDF, by contrast, carries only the actionable section — the procedure steps, the
checklist body, or the fillable grid. See step 3 in `SKILL.md`.)

## Source-to-toolkit conversion rules

Apply these when reformatting the raw source into the body:

- Open with a 1–2 paragraph intro. The hero on the slug page already shows title +
  description, so don't repeat the H1.
- Use `## Section` and `### Subsection` headings.
- Wrap checklist items in `::checklist-group` blocks. Inside the block use plain
  `- item` bullets — the `ChecklistGroup.vue` component renders each `<li>` with a
  CSS-drawn checkbox. The `tron:md-to-pdf` build script also auto-converts those
  bullets into task-list checkboxes for the PDF.
- Don't manually write `- [ ]` syntax inside `::checklist-group` — the website renders
  both the CSS box and the `<input type=checkbox>`, producing a double-box.
- Drop the source's "Choose your format / PDF / Excel" trailing section. The slug page
  auto-renders a Download PDF button when the front matter has a `download` field — in
  two places (hero and bottom of body). You don't author either; they come from the
  `download:` field.
- Don't put empty fillable grids in the web markdown. Empty pipe-table cells render as
  faint ghost lines on the page — the fillable grid belongs in the PDF only. On the
  web, use a populated descriptive table (e.g. a `Field | Purpose` table) or
  underscore-style bullets instead.
- Drop any "Version Control" table the source contains (a single-row "v1.0 / Initial
  SOP creation" entry is noise on a public marketing page — git history is the source
  of truth, and old toolkit items have already had it removed).

## Internal-link reference

Verify each internal link before saving — this is the #1 build-breaking pitfall.
Common landing pages:

| Want to link to                   | Correct path                                      | Notes                                                                                                |
| --------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Facilitron Works product          | `/product/works`                                  | has `index.vue`                                                                                      |
| Scheduling & Reservations product | `/product/facilitron-scheduling-and-reservations` | the directory `/product/scheduling-and-reservations/` has **no index page** — linking there is a 404 |
| Building Automation Systems       | `/product/scheduling-and-reservations/bas`        | exists                                                                                               |
| Facilitron FIT                    | `/product/facilitron-fit`                         |                                                                                                      |
| Other toolkit items               | `/resources/toolkit/<slug>`                       |                                                                                                      |

When unsure, run `find pages -type f -name "*.vue" | grep -i <keyword>` against the
marketing-pages repo to confirm. Convert any `https://www.facilitron.com/...` URLs in
the source to relative paths.
