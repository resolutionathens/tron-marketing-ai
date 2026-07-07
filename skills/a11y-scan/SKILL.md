---
name: a11y-scan
model: haiku
effort: low
description: "Run automated accessibility (WCAG) scans against a URL or sitemap using pa11y and axe-core. Use this skill when the user wants to check accessibility, audit a11y compliance, find WCAG violations, scan for accessibility issues, or says things like 'a11y scan', 'pa11y', 'axe', 'check accessibility', 'wcag check', 'audit accessibility', 'accessibility audit', 'find a11y issues', or 'is this page WCAG compliant'. Highly relevant to ongoing WCAG 2.1 AA compliance work — use whenever new pages or templates need verification, or when triaging Confluence pages from Taras."
allowed-tools:
  - Task
  - Bash
scout:
  surface: developer
  effects: [report]
---

# /a11y-scan — Accessibility scan (pa11y + axe)

This skill delegates the scan to the **`a11y-scan-runner`** subagent (runs on Haiku to keep cost low), which invokes a **deterministic bundled script**. Your job is to resolve the target and the script path, then hand off — **don't run the scanners yourself.**

## What to do

1. **Resolve the target:** a single URL (→ axe, most accurate), a sitemap or many pages (→ pa11y-ci), or a local dev page at `localhost:3000` (the user must already have `bun run dev` running — confirm if scanning local). Default WCAG level: **2.1 AA** (the script's default).
2. **Resolve the bundled script's absolute path.** Resolve the skill dir robustly — `$CLAUDE_SKILL_DIR` is not always exported into Bash:
   ```bash
   name=a11y-scan
   SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
   [ -e "$SKILL_DIR/scripts/a11y-scan.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/a11y-scan.sh" ] && echo "$d"; done | sort -V | tail -1)"
   [ -e "$SKILL_DIR/scripts/a11y-scan.sh" ] || { echo "tron:$name: can't find scripts/a11y-scan.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
   echo "$SKILL_DIR/scripts/a11y-scan.sh"   # → the absolute script path to hand the runner
   ```
3. **Delegate to `a11y-scan-runner`** (Task tool): "Run a WCAG 2.1 AA accessibility scan on `<target>` using the bundled script at `<absolute script path>` (pass `--sitemap` for a sitemap target / extra URLs for a multi-page scan). Return findings grouped by issue type with severity counts." The runner runs the script — it does **not** hand-assemble axe/pa11y command lines or a `.pa11yci.json`.
4. **Relay the runner's report.**

## Notes

- The script picks the engine per mode: one URL → axe (`--tags wcag2a,wcag2aa,wcag21a,wcag21aa`), many URLs / sitemap → pa11y-ci with a generated config. Both run via `npx -y` — no global install needed.
- Always keep the runner's "automated scanning catches ~30–40% of WCAG issues" caveat — a clean scan ≠ compliant. Keyboard nav, screen-reader, cognitive load, and link-text-in-context still need manual review.
- For an ongoing audit (Taras Confluence pages), scan the corresponding live URL and link findings to specific WCAG criteria for the log.
- Designers can pair this with **`tron:brand-check`** (palette/token/logo + contrast) for a full pre-handoff QA pass.
