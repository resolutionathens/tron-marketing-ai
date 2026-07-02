# News Item — Component palette

The full MDC component reference for a `/resources/news` article. The page anatomy and
components below come from the existing cluster articles and the slug renderer
(`pages/resources/news/[...slug].vue`) — follow them rather than re-reading sibling
articles each time. `school-facilities-maintenance-news-and-updates.md` is a clean
concrete example if you want one.

## Contents

- What the slug page renders for you — do NOT author these
- Front matter
- Body — assembling from the transformer's markdown
- Inline images — `::image-text` vs `::fImg`
- FAQ section
- Other MDC blocks available

## What the slug page renders for you — do NOT author these

- **Hero** (`SectionHeroProduct`): an **eyebrow** built from the category label + the
  publish date (e.g. "Best Practices · April 24, 2026", auto from `categories` + `date`),
  then the `title` and `description`, over the `blog-featured/<image>` hero image. So
  don't repeat the title as an `#` H1, and don't write the date or category into the body.
- A **social-share** row after the body, and a **"Schedule a Demo" CTA**
  (`SectionBasicCta`) closing every article — don't author your own closing CTA.
- **SEO** — meta tags and Article JSON-LD (`useArticleSchema`, using the `blog-featured`
  image and `author`) are emitted automatically from front matter. The news schema has
  **no** `meta_title`/`meta_description` (unlike toolkit) — `title`/`description` are it.
- The body renders inside Tailwind **`.prose`** at `max-w-6xl`, so plain markdown is
  styled automatically — no wrapper classes.

## Front matter

Schema source: `content.config.ts`, the `news` collection. `title` and
`description` are required; everything else is optional but use this shape:

```yaml
---
title: <Title — the ticket summary minus the "Cluster:" prefix>
author: Facilitron
featured: false
date: <today, YYYY-MM-DD>
description: <1–2 sentence SEO meta description; work in the primary keyword>
image: <slug>.webp
categories:
  - b2b
  - best-practices
---
```

`image:` is just the filename — `[...slug].vue` prefixes `blog-featured/`. Common
`categories` values: `b2b`, `best-practices`, `facilitron-university`,
`in-the-news`. A cluster/how-to article is almost always `b2b` + `best-practices`.

## Body — assembling from the transformer's markdown

The storage-format → markdown conversion (attribute stripping, macros, inline-comment
markers, `<hr>`s, heading normalization) is owned by the **`confluence-transformer`
agent** — SKILL.md Stage 1 delegates `body.html` to it. Don't re-derive or second-guess
those rules here; assemble the article from the agent's returned `<markdown>` block plus
the `<images>` list. Orchestrator-side concerns only:

- **Don't repeat the title as an H1** — the news hero already renders title +
  description.
- The agent appends a `## Recently commented` section collecting inline-comment
  snippets. That's review material for you, not article body: resolve any unfinished
  thought it surfaces (e.g. a bare path meant to become a link), then drop the section.
- **Internal links — verify each one before saving.** This is the top build/UX
  pitfall; SKILL.md Stage 3 runs `content.sh rewrite-links` + `check-link`. One-line
  rule: `/product/scheduling-and-reservations/` has **no index page** — link to
  `/product/facilitron-scheduling-and-reservations` (full table:
  `tools/content/internal-links.md`, linked from SKILL.md).

## Inline images — `::image-text` vs `::fImg`

Look at each Confluence `<ac:image>`'s `ac:layout` attribute — it tells you which
component to use:

- **`wrap-left` / `wrap-right`** → the image is meant to sit _beside_ its
  paragraph(s). Use `::image-text` (`components/content/ImageText.vue`), a 2-col
  layout that stacks on mobile. The adjacent prose becomes the slot body:

  ```markdown
  ::image-text{src="blog-posts/<slug>/<name>.webp" alt="<real description>" position="right"}
  The paragraph(s) that Confluence floated next to this image go here and
  render in the text column beside it.
  ::
  ```

  `position` matches the Confluence side (`wrap-left` → `position="left"`,
  `wrap-right` → `position="right"`). Pull in the section's paragraph(s) that the
  image visually pairs with — usually the one or two right after the heading.

  **Balance the columns.** The text column should roughly fill the image's
  height. A tall portrait image next to a single short sentence leaves an
  awkward empty gap — when that happens, pull the _following_ heading and its
  paragraph into the slot too (a `### Subsection` heading renders fine inside
  the slot). Conversely, don't overstuff a short landscape image with five
  paragraphs. Judge it by the rendered result, not a fixed rule.

- **`center`, full-width, or no meaningful wrap** → use `::fImg`
  (`components/content/FImg.vue`), an ImageKit-backed `<NuxtImg>` that renders
  full-width and centered:

  ```markdown
  ::fImg
  ---
  src: "blog-posts/<slug>/<name>.webp"
  format: "webp"
  alt: "<real description>"
  ---
  ::
  ```

  Optional `width` (string, e.g. `"450"`) and `classProp` override sizing.

For both: `src` is the ImageKit path **without** the leading slash or CDN base,
and `alt` is required for WCAG compliance (the marketing site has an active
accessibility mandate) — write a genuine description of the photo, never reuse the
`pexels-...` source filename.

## FAQ section

If the draft ends with an FAQ, render it with `::faq` (`components/content/Faq.vue`)
— it also emits FAQPage schema.org JSON-LD, which a plain markdown list wouldn't:

```markdown
::faq
---
faqItems: [{question: "...", answer: "..."}, {question: "...", answer: "..."}]
---
::
```

`Faq.vue` renders its own "FAQ" heading (default `title` prop), so **don't** add a
`## FAQ` markdown heading above it — that produces a duplicate title on the page.

## Other MDC blocks available

Beyond `::image-text`, `::fImg`, and `::faq`, the block a cluster/how-to article most
often wants is:

- **`::quote`** (`components/content/Quote.vue`) — a pull quote; front matter `quote`,
  `quotee`, optional `position`/`location`. Use it for a customer or expert quote
  mid-article.

These exist for other news types and are usually NOT needed for a cluster article —
reach for them only if the draft genuinely calls for it: **`::wistiaVideo`**
(`WistiaVideo.vue`; `src`/`title`/`description`) for Facilitron University webinar
recaps, **`::pr`** for in-the-news press posts, and `::div{.pl-6}` as a plain indent
wrapper. The bulk of a cluster article is still plain markdown (`##`/`###` headings,
paragraphs, lists) with `::image-text`/`::fImg` for visuals and `::faq` at the end.
