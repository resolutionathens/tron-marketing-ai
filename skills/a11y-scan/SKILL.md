---
name: a11y-scan
model: haiku
effort: low
description: "Run automated accessibility (WCAG) scans against a URL or sitemap using pa11y and axe-core. Use this skill when the user wants to check accessibility, audit a11y compliance, find WCAG violations, scan for accessibility issues, or says things like 'a11y scan', 'pa11y', 'axe', 'check accessibility', 'wcag check', 'audit accessibility', 'accessibility audit', 'find a11y issues', or 'is this page WCAG compliant'. Highly relevant to the ongoing WCAG 2.1 AA audit work (April 2026 ADA Title II deadline) — use whenever new pages or templates need verification, or when triaging Confluence pages from Taras."
allowed-tools:
  - Task
---

# /a11y-scan — Accessibility scan (pa11y + axe)

This skill delegates the scan to the **`a11y-scan-runner`** subagent (runs on Haiku to keep cost low). Your job is to resolve the target and hand off — **don't run the scanners yourself.**

## What to do

1. **Resolve the target:** a single URL (→ axe, most accurate), a sitemap or many pages (→ pa11y-ci), or a local dev page at `localhost:3000` (the user must already have `bun run dev` running — confirm if scanning local). Default WCAG level: **2.1 AA**.
2. **Delegate to `a11y-scan-runner`** (Task tool): "Run a WCAG 2.1 AA accessibility scan on `<target>`. Return findings grouped by issue type with severity counts."
3. **Relay the runner's report.** If it says axe/pa11y aren't installed, surface `npm install -g pa11y pa11y-ci @axe-core/cli`.

## Notes
- Pair axe (accuracy) + pa11y-ci (breadth) for important pages.
- Always keep the runner's "automated scanning catches ~30–40% of WCAG issues" caveat — a clean scan ≠ compliant. Keyboard nav, screen-reader, cognitive load, and link-text-in-context still need manual review.
- For an ongoing audit (Taras Confluence pages), scan the corresponding live URL and link findings to specific WCAG criteria for the log.
- Designers can pair this with **`tron:brand-check`** (palette/token/logo + contrast) for a full pre-handoff QA pass.
