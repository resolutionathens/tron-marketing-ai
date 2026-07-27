---
name: keyword-research
model: sonnet
effort: medium
description: "Research and cluster keywords for a topic, product, or page — grouping by search intent (informational / commercial / transactional), mapping clusters to target pages, and flagging gaps and quick wins. Use when SEO wants keyword work or content gap analysis: 'keyword research for facility rentals', 'build search keyword clusters for B2B', 'run a content gap analysis', 'what should this landing page target'. Pulls real query data from Search Console where possible. Git-free — produces a keyword map / brief."
allowed-tools:
  - Bash
  - Read
  - Write
  - Skill
  - WebFetch
scout:
  surface: true
  title: "Research keywords"
  blurb: "Finds and clusters the searches people actually make around a topic, mapped to the pages that should win them."
  when: "Planning content or a landing page and deciding what it should target."
  category: seo
  effects: [draft]
  inputs:
    - key: seed
      label: "Seed topics"
      type: textarea
      required: true
      help: "Seed keywords / topics to research and cluster."
---

# /keyword-research — Keyword research + clustering

Build a **keyword map** for a topic or page: clusters by intent, mapped to target URLs, with gaps and
quick wins. Git-free: outputs a brief that feeds `tron:landing-page-seo` and content drafting.

## Method

1. **Seed** — start from the product/topic, competitor pages, and the page's current rankings.
2. **Real data first (when you can reach it)** — pull existing queries (impressions/position) from
   Search Console via `/tron-report`; queries on page 2 (positions 11–20) are the quick-win pool.
   **Fallback if GSC is unreachable** (the `/tron-report` CLI and seo.facilitron.work are behind
   Cloudflare Access — many non-technical users can't reach them): skip the quick-win pull and build
   the map from the **expand** step alone (step 3), **but say so** — flag that the "Quick wins" section
   is empty for lack of GSC data and that `est. difficulty`/`current pos` columns are estimates, not
   measured. Ask whoever has GSC access (or the SEO lead) to paste the page-2 query list to fill it in.
3. **Expand** — related terms, questions (People-Also-Ask style), modifiers (location, "for schools",
   "for districts"), long-tail.
4. **Cluster by intent:**
   | Intent | Example | Maps to |
   |---|---|---|
   | Informational | "how to rent a school gym" | guide / blog |
   | Commercial | "facility rental software" | product / comparison |
   | Transactional | "book <district> facilities" | landing / booking |
5. **Map** — one primary keyword + a cluster per target page; avoid two pages targeting the same term
   (cannibalization).

## Output

```markdown
# Keyword map — <topic/page>

## Primary targets

| page | primary kw | intent | est. difficulty | current pos |
|------|------------|--------|-----------------|-------------|

## Clusters

Grouped supporting terms per page.

## Quick wins

Page-2 queries to push (pos 11–20).

## Gaps

Intents/terms with no page yet → content ideas.
```

Write `/tmp/seo/keyword-map-<slug>.md`. Hand quick wins to `tron:landing-page-seo`; hand content
gaps to the content role (`tron:case-study` / `tron:guide-item`). Summarize the primary targets +
top 3 quick wins.
