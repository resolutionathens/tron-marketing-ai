---
name: site-audit
model: haiku
effort: low
description: "Run a site-wide Lighthouse audit (performance, SEO, accessibility, best practices) using unlighthouse, which crawls every page in a site and reports per-page scores plus aggregated insights. Use this skill ONLY for multi-page / whole-site crawls — when the user wants coverage across many pages, says things like 'run lighthouse across the site', 'audit the site', 'unlighthouse', 'check site performance', 'score the whole marketing site', 'site-wide health check', 'find pages with bad LCP/CLS', or 'run a site perf audit'. For a single page's on-page SEO use tron:seo-audit; for one URL's accessibility use tron:a11y-scan."
allowed-tools:
  - Task
scout:
  surface: developer
  effects: [report]
---

# /site-audit — Site-wide Lighthouse audit

This skill delegates the audit to the **`unlighthouse-runner`** subagent (runs on Haiku). Your job is to pick the site target and hand off — **don't run unlighthouse yourself.**

## What to do

1. **Pick the target + scope:** prod `https://www.facilitron.com`, staging, `http://localhost:3000` (dev server must already be running), or a section/page URL. Decide the scope and tell the runner which mode:
   - a **section** URL (e.g. `…/resources/guides`) → default (audits only that section)
   - a **single page** → `--page` (bounded to that one URL)
   - the **whole site** → `--full` (only when the user explicitly wants the entire origin)
   - pass `--desktop` / `--samples 3` / `--throttle` (realistic mobile CWV) only if the user asks.
2. **Delegate to `unlighthouse-runner`** (Task tool): "Run a Lighthouse audit on `<target>` (mode: `<section|--page|--full>`) and return the lowest-scoring pages plus the biggest-impact opportunities." The runner invokes the bundled deterministic script — it does **not** hand-assemble the `npx` command (that's how it once crawled the whole site by mistake).
3. **Relay the runner's summary.**

## Notes

- The runner runs the bundled `scripts/site-audit.sh` — it never assembles the `npx` command itself.
- First run is slow (downloads Chromium).
- unlighthouse's a11y score is a sanity check only — use `tron:a11y-scan` (axe/pa11y) for authoritative WCAG. Remind the user to gitignore `.unlighthouse/`.
- Pairs well with `tron:seo-report` (GSC + GA4 data) for a fuller SEO / real-user-CWV picture.
