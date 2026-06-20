---
name: unlighthouse-audit
description: "Run a site-wide Lighthouse audit (performance, SEO, accessibility, best practices) using unlighthouse, which crawls every page in a site and reports per-page scores plus aggregated insights. Use this skill when the user wants a Lighthouse report, a performance audit, an SEO audit, a site-wide health check, Core Web Vitals data, or says things like 'run lighthouse', 'audit the site', 'unlighthouse', 'check site performance', 'check our SEO scores', 'score the marketing site', 'find pages with bad LCP/CLS', or 'run a perf audit'. Prefer this over single-page Lighthouse when the user wants coverage across multiple pages."
---

# Unlighthouse Site Audit

This skill delegates the audit to the **`unlighthouse-runner`** subagent (runs on Haiku). Your job is to pick the site target and hand off — **don't run unlighthouse yourself.**

## What to do

1. **Pick the target:** prod `https://www.facilitron.com`, staging, `http://localhost:3000` (dev server must already be running), or a section (`--urls-pattern '/resources/**'`). Pass through `--throttle` / `--desktop` / `--samples` only if the user asks.
2. **Delegate to `unlighthouse-runner`** (Task tool): "Run a site-wide Lighthouse audit on `<target>` in headless/static mode and return the lowest-scoring pages plus the biggest-impact opportunities."
3. **Relay the runner's summary.**

## Notes
- The runner runs headless (`--build-static --reporter csvExpanded`) and parses the CSV — it never uses the interactive UI (a subagent can't).
- First run is slow (downloads Chromium).
- unlighthouse's a11y score is a sanity check only — use `tron:a11y-scan` (axe/pa11y) for authoritative WCAG. Remind the user to gitignore `.unlighthouse/`.
- Pairs well with `tron:seo-report` (GSC + GA4 data) for a fuller SEO / real-user-CWV picture.
