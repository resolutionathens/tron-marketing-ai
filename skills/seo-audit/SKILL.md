---
name: seo-audit
model: sonnet
effort: medium
description: "Run an on-page + technical SEO audit of a page or URL — title/meta, heading structure, schema/structured data, canonical, internal links, image alt, indexability, and Core Web Vitals — and return prioritized findings + fixes against a target query set. Use this skill when SEO wants to audit a page: 'SEO audit dfp.facilitron.com', 'audit this landing page for search', 'why isn't this page ranking', 'on-page SEO check for MCR-332', or any SEO-audit ticket. Folds in /site-audit (perf), /a11y-scan (a11y), and /link-check (links). Git-free — produces an audit + fix spec; the page edits are a separate git task."
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - WebFetch
  - Skill
scout:
  surface: true
  title: "Audit a page's SEO"
  blurb: "Checks one page's titles, headings, schema, links, and speed against a target search, with prioritized fixes."
  when: "A page isn't ranking and you want to know why."
  category: seo
  effects: [report]
  inputs:
    - key: url
      label: "Page URL"
      type: text
      required: true
    - key: queries
      label: "Target queries"
      type: text
      required: false
      help: "The search queries this page should rank for (optional)."
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
5. **Performance / CWV** — defer to `tron:site-audit` in its single-page mode (`--page`, bounded to
   the one URL) for LCP/CLS/INP, and fold the scores in.
6. **A11y + links** — `/a11y-scan` and `/link-check` for the page; surface SEO-relevant hits.

## Fast path — fetch + meta extraction (scripted)

The fetch and meta pull are deterministic — run the bundled script rather than hand-rolling curl/grep:

```bash
name=seo-audit
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/seo-audit.sh" ] || SKILL_DIR="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 5 -type d -path "*/skills/$name" 2>/dev/null | while read -r d; do [ -e "$d/scripts/seo-audit.sh" ] && echo "$d"; done | sort -V | tail -1 || true)"
[ -e "$SKILL_DIR/scripts/seo-audit.sh" ] || { echo "tron:$name: scripts/seo-audit.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }

bash "$SKILL_DIR/scripts/seo-audit.sh" "<url>"
# already have the HTML locally (or offline)? parse it without a fetch:
bash "$SKILL_DIR/scripts/seo-audit.sh" --html-file /tmp/seo/page.html "<url>"
```

One JSON line on stdout: status code + redirect chain, `robots_meta`, `canonical`, `title` (+ length),
`meta_description` (+ length), `h1s`/`h1_count`, and img-alt coverage. Narration goes to stderr;
exits 0 (parsed), 1 (fetch/read failure), 2 (usage).

Your judgment starts where the JSON ends: is the title's keyword front-loaded and ≤60 chars? Does
the canonical point where it should (watch redirect chains that end somewhere unexpected)? Is a
`noindex` intentional? Do the H1/heading hierarchy and alt coverage match the target query set?
Use WebFetch for a rendered read when the page is JS-heavy (the script sees only source HTML).

## Output

A findings table, **ordered by impact × effort**:

| Area   | Finding                  | Target                      | Severity | Fix                           |
| ------ | ------------------------ | --------------------------- | -------- | ----------------------------- |
| Title  | 72 chars, keyword buried | "district facility rentals" | high     | front-load keyword, ≤60 chars |
| Schema | no Product schema        | —                           | medium   | add Product/Offer JSON-LD     |
| CWV    | LCP 4.1s (hero image)    | <2.5s                       | high     | preload + resize hero         |

End with the top 3 fixes and a one-line verdict. Offer to file them as Jira sub-tasks via
`tron:jira-comment` / the manager `tron:board-scaffold` (confirm first).
