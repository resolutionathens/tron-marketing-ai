---
name: guide-item
model: opus
effort: high
description: 'Publish a new long-form guide to /resources/guides on the Facilitron marketing site from a Jira ticket whose description links a Confluence draft. A guide is a bespoke Vue PAGE built from section/display components (not a Nuxt-Content markdown file); this skill owns the full pipeline — Confluence fetch, image conversion to webp + ImageKit upload, page composition, guides-index registration, and SEO meta. Use this skill whenever the user wants to "start the guide", "create a new guide", "build out this guide", "turn this Confluence draft into a guide page", references a Jira "Guide" or "Pillar" ticket with a Confluence link. Even if they describe only one part, this skill owns the whole pipeline so the pieces stay consistent.'
allowed-tools:
  - Bash
  - Read
  - Write
  - Task
  - AskUserQuestion
scout:
  surface: developer
  effects: [publish, cdn]
  inputs:
    - key: topic
      label: "Guide topic"
      type: text
      required: true
    - key: notes
      label: "Notes"
      type: textarea
      required: false
---

# Facilitron Guide Item

Publish a new guide under `/resources/guides` — a **hand-composed Vue page** (not a Nuxt-Content markdown file), built from section/display components, plus a manual entry in the guides index.

## Checklist

```
- [ ] Preflight: confirm marketing-pages repo (content.sh check-repo)
- [ ] Stage 1: read ticket + fetch Confluence draft + images; confirm slug
- [ ] Stage 2: convert body images to webp + upload to guides/<slug>/; OG image; index card thumbnail
- [ ] Stage 3: compose pages/resources/guides/<slug>.vue from the guide palette
- [ ] Stage 4: append entry to guides array in index.vue
- [ ] Stage 5: verify renders, card shows, images + links resolve, prose-lint + a11y-scan
- [ ] Clean up: remove /tmp/guide-<slug> and dropped-in sources
```

## What gets produced

- `pages/resources/guides/<slug>.vue` — page composed from section components
- Body images at `guides/<slug>/<name>.webp` (via `<NuxtImg provider="imagekit">`)
- OG image at `og/og-<slug>.webp`
- Card thumbnail at `guides/guide-<NN>.webp` (next free number)
- New entry in `pages/resources/guides/index.vue`'s `guides` array
- Source files cleaned up

## Inputs

| Input | Source |
|-------|--------|
| Jira key | Branch name (`<KEY>-<slug>`) |
| Confluence draft + SEO keywords | Ticket description (inlineCard) |
| Images | Confluence draft, or ask for Figma/ImageKit source |
| Slug | Derived from title, lowercase-hyphenated. Confirm before uploading. |

## Shared helper (plugin tools)

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" slug "<title>"
bash "$C" rewrite-links pages/resources/guides/<slug>.vue
bash "$C" check-link /product/<path>

GENCARD="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/generate-card.sh"
```

## Preflight — marketing-pages repo guard

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh" check-repo | grep -q '"isMarketingPages":true' \
  || { echo "✋ NOT in marketing-pages — switch checkouts first." >&2; exit 1; }
```

## Stage 1 — Intake

```bash
acli jira workitem view <KEY> --json
# Extract Confluence URL + target keywords

TOOLS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools"
"$TOOLS/confluence/fetch-confluence.sh" <confluence-url> /tmp/guide-<slug>
```

Writes `/tmp/guide-<slug>/body.html` and referenced images in `/tmp/guide-<slug>/raw/`. Delegate the storage→markdown transform to the **`confluence-transformer` agent** — hand it the path to `body.html`. It returns `<markdown>…</markdown>` (extract the body) and `<images>…</images>` (one filename per line, document order). Keep the raw XML out of context.

## Stage 2 — Images

Convert body images to webp, upload to `guides/<slug>/`. Also upload OG image and generate the index card thumbnail.

- Guide-specific naming + paths: [`reference/images.md`](reference/images.md)
- Convert → upload → verify mechanics: [`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md)
- Card thumbnail: `"$GENCARD"` with `--folder guides --prefix guide` (auto-numbers `guide-NN.webp`); invocation + result parsing live in the "Generate an index/card thumbnail from references" section of the shared doc above

Run the image pipeline for all body images — no per-image subagents needed:

```bash
PIPE="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/image-pipeline.sh"
IMAGES=$(bash "$PIPE" --src /tmp/guide-<slug>/raw --dest guides/<slug>)
# IMAGES: {"section-name.webp": "https://ik.imagekit.io/facilitron/guides/<slug>/section-name.webp", ...}
```

The OG image has a specific output name — handle it directly:

```bash
TOWEBP="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/image/to-webp.sh"
IK="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/imagekit/imagekit.mjs"
bash "$TOWEBP" <hero-source>.png /tmp/og-<slug>.webp
node "$IK" upload /tmp/og-<slug>.webp --name og-<slug>.webp --folder og
```

## Stage 3 — Compose the page

Create `pages/resources/guides/<slug>.vue`. This is the **judgment core — do not delegate.** Mirror an existing guide like `preventive-maintenance-strategy.vue`.

**Structure:** hero → TOC → intro → 2-5 body sections → optional pull quote + dark "at a glance" → mid-page CTA → conclusion → FAQ.

**Component map:** prose → `BaseSection`; takeaways → `callout`; point lists → `alternative` grids; numbered processes → timeline pattern; FAQs → `SectionAccordion`.

**Wire `useDynamicMeta`** with title, keyword-rich description, route path, and full OG URL. Keep TOC `id`s in sync with `BaseSection id`s. Use `tron-` tokens only — no arbitrary Tailwind values.

See `reference/components.md` for the full palette — section skeleton, component props, draft-to-component mapping, `<script setup>` conventions, styling rules.

**Do NOT use** `::fImg`/`::image-text` (those are for content collections). Guides are Vue: use `<NuxtImg provider="imagekit">`. Only the OG image uses a full URL.

## Stage 4 — Register in the index

Guides are not auto-discovered. Append to `pages/resources/guides/index.vue`:

```ts
{ title: "<title>", description: "<card description>", image: "guides/guide-<NN>.webp", imageAlt: "", link: "/resources/guides/<slug>" }
```

## Stage 5 — Verify & clean up

1. **Served-HTML check:** Start a worktree-scoped dev server and confirm the page is served:
   ```bash
   DS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/dev-server.sh"
   [[ -f "$DS" ]] || { echo "dev-server.sh not found — set CLAUDE_PLUGIN_ROOT or run /plugin update" >&2; exit 1; }
   PORT="$(bash "$DS" start --route /resources/guides/<slug>)"
   curl -s "http://localhost:${PORT}/resources/guides/<slug>" | grep -oE '<title>[^<]*</title>'
   curl -s "http://localhost:${PORT}/resources/guides/<slug>" | grep -oc 'guides/<slug>'
   ```
2. **Index card:** Load `/resources/guides`, confirm new card shows.
3. **Images resolve:** Spot-check ImageKit URLs.
4. **Links:** Run `bash "$C" rewrite-links pages/resources/guides/<slug>.vue` (facilitron.com → relative), then `bash "$C" check-link` each internal path. Known trap: `/product/scheduling-and-reservations/` has no index page — use `/product/facilitron-scheduling-and-reservations`. Full path table: [`../../tools/content/internal-links.md`](../../tools/content/internal-links.md)
5. **Prose & a11y:** `tron:prose-lint`, `tron:a11y-scan`, grep for `—` (no em-dashes).
6. **Clean up:** Remove `/tmp/guide-<slug>` and dropped-in sources.

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Using `::fImg` instead of `<NuxtImg>` | Guides are Vue, not content collections |
| Forgetting the index entry | Page works at URL but never appears on `/resources/guides` |
| TOC anchor mismatch | `tocItems.id` must match `BaseSection id`; add `scroll-mt-36` |
| Duplicate H1 | Hero already renders title; don't open body with `#` |
| `content/QuoteSimple` vs `section/QuoteSimple` | Use `<SectionQuoteSimple>` for bgColor/borderBottom props |
| Arbitrary Tailwind values | Add `tron-` token to `tailwind.config.ts` instead |