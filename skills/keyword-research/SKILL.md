---
name: keyword-research
model: sonnet
effort: medium
description: "Research and cluster keywords for a topic, product, or page — grouping by search intent (informational / commercial / transactional), mapping clusters to target pages, and flagging gaps and quick wins. Use when SEO wants keyword work or content gap analysis: 'keyword research for facility rentals', 'build search keyword clusters for B2B', 'run a content gap analysis', 'what should this landing page target'. Pulls real query data from Search Console where possible. Draft-first — produces a keyword map / brief and leaves repository work to the target skill."
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

## Durable delivery gate

Resolve the durable destination before drafting the keyword map. Follow
[the durable deliverable contract](../../tools/content/durable-deliverables.md): select Drive or Confluence, capture review/owner/handoff metadata, work in a uniquely created scratch directory, publish through the matching publisher skill, return the complete success block, and clean scratch on success and failure. For a website handoff only, this skill may use `tron:start-ticket` or `tron:open-worktree` to add the marketing-pages worktree to the session. It never writes repository content or owns other Git work: it does not commit, push, or open a pull request; the repo-local publishing skill owns all repository work.

Build a **keyword map** for a topic or page: clusters by intent, mapped to target URLs, with gaps and
quick wins. Draft-first: outputs a brief that feeds `tron:landing-page-seo` and content drafting.

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

Draft `$WORK/keyword-map-<slug>.md`, publish it to the resolved durable destination, and return its
approved source URL for any website handoff. Hand quick wins to `tron:landing-page-seo`. For a guide
gap, first use `tron:start-ticket` to create, or `tron:open-worktree` to reopen, a marketing-pages
worktree and add it to the session. The repo-local skill only appears in the listing after that
directory is added; then invoke bare `guide-item`. Use `tron:case-study` for a case-study draft.
Summarize the primary targets + top 3 quick wins.
