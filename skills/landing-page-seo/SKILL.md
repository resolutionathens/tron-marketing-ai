---
name: landing-page-seo
model: sonnet
effort: medium
description: "Produce an on-page SEO optimization spec for a specific landing page against a target keyword set — recommended title/meta/H1, heading outline, content additions, internal links, schema, and CWV fixes — as a concrete change list a developer can implement. Use when SEO wants the prescriptive fix spec for a page: 'optimize the DFP landing page for search', 'on-page spec for dfp.facilitron.com', 'make this page rank for X'. To first DIAGNOSE a page's current state (findings, not a change spec) use tron:seo-audit; this skill produces the change spec that builds on tron:seo-audit + tron:keyword-research. Git-free."
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - WebFetch
  - Skill
scout:
  surface: true
  title: "Spec SEO fixes for a page"
  blurb: "Turns an audit into a concrete change list a developer can implement — title, headings, content, links, schema."
  when: "You know a page needs SEO work and want the exact to-do list."
  category: seo
  effects: [draft]
  inputs:
    - key: url
      label: "Landing page URL"
      type: text
      required: true
---

# /landing-page-seo — Landing-page optimization spec

Turn a target keyword set + a page into a **concrete on-page change list** a developer can implement.
Git-free: produces the spec; a git user makes the edits.

## Inputs

- The page (live URL and/or its repo source `.vue`/content file) and the **primary + supporting
  keywords** (from `tron:keyword-research`).
- Run `tron:seo-audit` first if you don't already have the page's current state.

## The spec (what to deliver)

```markdown
# On-page SEO spec — <page>

**Primary:** <kw> · **Supporting:** <kw, kw, kw>

| Element          | Current | Recommended                          |
| ---------------- | ------- | ------------------------------------ |
| Title            | <…>     | <≤60 chars, primary kw front-loaded> |
| Meta description | <…>     | <≤155 chars, benefit + kw, CTA>      |
| H1               | <…>     | <single, kw-aligned>                 |
| URL slug         | <…>     | <short, kw>                          |

## Heading outline

H2/H3 structure that covers the intent + supporting terms.

## Content additions

- <section to add / expand, with the gap it fills>

## Internal links

- Add link from <page> → <this page> with anchor "<kw>"

## Schema

- Add <Product/FAQ/Breadcrumb> JSON-LD: <fields>

## Technical / CWV

- <e.g. preload hero, lazy-load below fold> (from /site-audit)
```

## Rules

- Match **search intent** before keyword density. Don't keyword-stuff.
- One page = one primary keyword. Keep titles/metas within length budgets.
- Every recommendation is specific and implementable — no "improve content" hand-waves.

## Handoff

Write `/tmp/seo/onpage-spec-<slug>.md`. The implementation is a marketing-pages change — hand to a
git user (`tron:start-ticket` → edit → `tron:git-pr`) or file via `tron:board-scaffold`. Summarize
the title/meta/H1 changes + the single highest-impact fix.
