---
name: seo-report
description: "Build a periodic SEO performance report from Google Search Console + GA4 — clicks, impressions, average position, top queries/pages, and month-over-month deltas — as a shareable summary (with optional district/segment breakdown). Use this skill when SEO wants a report: 'build the monthly SEO report', 'GSC report for dfp', 'how did search traffic do last month', 'district-level traffic report', 'SEO report for MCR-353', or B2B SEO reporting tickets. Wraps the global /tron-report (Search Console) and the GA4 analytics MCP. Git-free — produces a report deliverable."
allowed-tools:
  - Bash
  - Read
  - Write
  - Skill
  - WebFetch
---

# /seo-report — GSC + GA4 SEO report

Produce a periodic **SEO performance report** for sharing (the MCR monthly SEO report, B2B SEO
reporting, district-level traffic). Git-free: outputs a markdown/PDF deliverable.

## Data sources
- **Search Console** — run the global **`/tron-report`** skill (saves a Search Console report to the
  Desktop). Use it for clicks / impressions / CTR / position + top queries + top pages.
- **GA4** — use the analytics MCP (`run_report`, `run_realtime_report`, `get_property_details`) for
  sessions, engaged sessions, conversions, and channel/landing-page breakdowns. For **district-level**
  traffic, segment by the landing-page path or the district dimension (cf. MCR-335 tracking setup).

## Structure
```markdown
# SEO report — <period> (vs <prior period>)
## Headline
- Clicks <N> (<±%>) · Impressions <N> (<±%>) · Avg position <N> (<±>) · Sessions <N> (<±%>)
## Top queries        | query | clicks | impr | pos | Δpos |
## Top pages          | page  | clicks | impr | Δ   |
## Movers             gains / losses worth noting
## Segments           (district / B2B / product) if requested
## Recommendations    3–5 next actions tied to the data
```

## Rules
- Always show the **comparison** (MoM or vs same period last year) — a report without a delta is noise.
- Round sensibly; call out the *why* behind big movers, don't just list numbers.
- Don't fabricate — if a data source is unavailable, say so and report what you have.

## Output
Write `/tmp/seo/seo-report-<period>.md`. Offer `tron:md-to-pdf` for a branded PDF, or note the
Desktop CSV from `/tron-report`. For the "report to carousel" workflow (MCR-353), export the key
tiles as the slide inputs. Summarize headline numbers + the top recommendation.
