---
name: keyword-research
description: "Research and cluster keywords for a topic, product, or page — grouping by search intent (informational / commercial / transactional), mapping clusters to target pages, and flagging gaps and quick wins. Use this skill when SEO wants keyword work: 'keyword research for facility rentals', 'find keywords for the Tickets page', 'what should this landing page target', 'build a keyword map for B2B', or keyword-strategy tickets (MCR-266, MCR-332). Pulls real query data from Search Console where possible. Git-free — produces a keyword map / brief."
allowed-tools:
  - Bash
  - Read
  - Write
  - Skill
  - WebFetch
---

# /keyword-research — Keyword research + clustering

Build a **keyword map** for a topic or page: clusters by intent, mapped to target URLs, with gaps and
quick wins. Git-free: outputs a brief that feeds `tron:landing-page-seo` and content drafting.

## Method
1. **Seed** — start from the product/topic, competitor pages, and the page's current rankings.
2. **Real data first** — pull existing queries (impressions/position) from Search Console via
   `/tron-report`; queries on page 2 (positions 11–20) are the quick-win pool.
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
## Primary targets        | page | primary kw | intent | est. difficulty | current pos |
## Clusters               grouped supporting terms per page
## Quick wins             page-2 queries to push (pos 11–20)
## Gaps                   intents/terms with no page yet → content ideas
```
Write `/tmp/seo/keyword-map-<slug>.md`. Hand quick wins to `tron:landing-page-seo`; hand content
gaps to the content role (`tron:case-study` / `tron:guide-item`). Summarize the primary targets +
top 3 quick wins.
