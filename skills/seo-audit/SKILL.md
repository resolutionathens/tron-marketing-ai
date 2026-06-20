---
name: seo-audit
model: sonnet
effort: medium
description: "Run an on-page + technical SEO audit of a page or URL — title/meta, heading structure, schema/structured data, canonical, internal links, image alt, indexability, and Core Web Vitals — and return prioritized findings + fixes against a target query set. Use this skill when SEO wants to audit a page: 'SEO audit dfp.facilitron.com', 'audit this landing page for search', 'why isn't this page ranking', 'on-page SEO check for MCR-332', or any SEO-audit ticket. Folds in /unlighthouse-audit (perf), /a11y-scan (a11y), and /lychee-link-check (links). Git-free — produces an audit + fix spec; the page edits are a separate git task."
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - WebFetch
  - Skill
---

# /seo-audit — On-page + technical SEO audit

Audit a page for search and return a **prioritized fix list** tied to its target keywords. Git-free:
it diagnoses; implementing fixes is handed to a git user.

## Inputs
- The URL (live or staging) and its **target query set** (from `tron:keyword-research` or the ticket).
- If auditing a source page in the repo, the route's `.vue`/content file (read it directly).

## What it checks
1. **Indexability** — robots/meta-robots, canonical, sitemap presence, status code.
2. **On-page** — title (length + keyword), meta description, single H1, heading hierarchy, keyword
   coverage + intent match, image `alt`, internal links in/out, URL slug.
3. **Structured data** — schema.org type present + valid for the page (Org, Product, FAQ, Article).
4. **Content** — depth vs intent, thin/duplicate, missing sections competitors cover.
5. **Performance / CWV** — defer to `/unlighthouse-audit` (LCP/CLS/INP) and fold the scores in.
6. **A11y + links** — `/a11y-scan` and `/lychee-link-check` for the page; surface SEO-relevant hits.

## Fetching the page
```bash
curl -sL --compressed -A "Mozilla/5.0" "<url>" -o /tmp/seo/page.html  # --compressed: marketing-pages are CloudFront gzip
# title / meta / h1 / canonical quick pull:
grep -ioE '<title>[^<]*</title>|<meta name="description"[^>]*>|<h1[^>]*>|rel="canonical"[^>]*' /tmp/seo/page.html | head
```
Use WebFetch for a rendered read when the page is JS-heavy.

## Output
A findings table, **ordered by impact × effort**:

| Area | Finding | Target | Severity | Fix |
|---|---|---|---|---|
| Title | 72 chars, keyword buried | "district facility rentals" | high | front-load keyword, ≤60 chars |
| Schema | no Product schema | — | medium | add Product/Offer JSON-LD |
| CWV | LCP 4.1s (hero image) | <2.5s | high | preload + resize hero |

End with the top 3 fixes and a one-line verdict. Offer to file them as Jira sub-tasks via
`tron:jira-comment` / the manager `tron:board-scaffold` (confirm first).
