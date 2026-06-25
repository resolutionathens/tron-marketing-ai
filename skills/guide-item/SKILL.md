---
name: guide-item
model: opus
effort: high
description: 'Publish a new long-form guide to /resources/guides on the Facilitron marketing site from a Jira ticket whose description links a Confluence draft. A guide is a bespoke Vue PAGE built from section/display components (not a Nuxt-Content markdown file); this skill owns the full pipeline — Confluence fetch, image conversion to webp + ImageKit upload, page composition, guides-index registration, and SEO meta. Use this skill whenever the user wants to "start the guide", "create a new guide", "build out this guide", "turn this Confluence draft into a guide page", "add a guide to /resources/guides", references a Jira "Guide" or "Pillar" ticket with a Confluence link, or says "publish this guide" / "get this guide on the site". Even if they describe only one part ("just do the images", "just scaffold the page"), this skill owns the whole pipeline so the pieces stay consistent.'
allowed-tools:
  - Bash
  - Read
  - Write
  - Task
  - AskUserQuestion
---

# Facilitron Guide Item

Publish a new guide under `/resources/guides` on the marketing-pages site, starting
from a Jira ticket that links a Confluence draft.

**A guide is NOT a content collection item.** News (`content/resources/news`) and
toolkit (`content/resources/toolkit`) items are markdown files rendered by a
`[...slug].vue` catch-all. Guides have **no collection, no schema, no catch-all** —
each guide is a hand-composed Vue page at `pages/resources/guides/<slug>.vue`, built
from the site's section/display components, plus a manual entry in the guides index.
The route is just the filename: `pages/resources/guides/preventive-maintenance-strategy.vue`
serves at `/resources/guides/preventive-maintenance-strategy`.

So this pipeline shares the _intake and image_ stages with `tron:news-item`,
but its core is **page composition**, not markdown authoring.

## What gets produced

- A Vue page at `pages/resources/guides/<slug>.vue` (layout `news`), composed from the
  standard guide palette, body converted from the Confluence draft
- Body images uploaded to ImageKit at `guides/<slug>/<name>.webp`, referenced via
  `<NuxtImg provider="imagekit" src="guides/<slug>/<name>.webp">`
- An OG image at `og/og-<slug>.webp` (passed to `useDynamicMeta`)
- A card thumbnail at `guides/guide-<NN>.webp` (next free number) for the index card
- A new entry appended to the `guides` array in `pages/resources/guides/index.vue`
- Local source files (Confluence download, dropped-in images) cleaned up

## Inputs you need

1. **Jira ticket key** — usually on the branch name (`<KEY>-<slug>`). Its description
   carries target SEO keywords and a Confluence inline-card link.
2. **Slug** — derive from the ticket/title, lowercase-hyphenated, descriptive
   (`preventive-maintenance-strategy`, `school-facility-management-best-practices`).
   The page filename, the `guides/<slug>/` image folder, the OG image name, and the
   index `link` all use it — confirm with the user before uploading anything.
3. **Hero/illustration images** — pulled from the Confluence draft, or reuse existing
   `product/...` illustrations. If the draft has none, ask whether to source from
   Figma/ImageKit or proceed with a `product/...` placeholder.

## Environment

`JIRA_API_TOKEN` lives in `~/.env` (1Password) and is
usually autosourced. If a command 401s or a token is unset, source them in the _same_
Bash call: `set -a; source ~/.env; set +a`.

## Workflow checklist

Copy this into your working notes and check items off as you go — it covers every stage.

```
- [ ] Preflight: content.sh check-repo confirms marketing-pages (stop if not)
- [ ] Stage 1: read the Jira ticket + capture target keywords
- [ ] Stage 1: fetch the Confluence draft + images; Sonnet subagent → markdown + image map
- [ ] Stage 1: confirm the slug with the user before uploading anything
- [ ] Stage 2: convert body images to webp + upload to guides/<slug>/
- [ ] Stage 2: upload the OG image to og/og-<slug>.webp
- [ ] Stage 2: generate the index card thumbnail and upload as guides/guide-<NN>.webp
- [ ] Stage 3: compose pages/resources/guides/<slug>.vue from the guide palette
- [ ] Stage 3: wire useDynamicMeta (title, description, path, OG URL)
- [ ] Stage 4: append the new entry to the guides array in index.vue
- [ ] Stage 5: verify it renders, the card shows, images + links resolve
- [ ] Stage 5: run the verification loop (prose-lint, a11y-scan, no em dashes)
- [ ] Stage 5: clean up /tmp/guide-<slug> and dropped-in sources
```

---

## Subagents & model tiers

Same principle as the other pipelines: push mechanical/large-payload work to cheaper
subagents, keep design judgment in the orchestrator.

- **Confluence → markdown (Sonnet).** Delegate the storage-format transform to a
  Sonnet subagent per the `tron:confluence` skill's faithful-markdown contract — it returns
  clean markdown + a per-image map (`{ filename, alt, ac:layout, order }`). Keeps the
  raw XML out of the orchestrator while you compose the page.
- **Image convert + upload (Haiku fan-out).** Once you've named each image
  (`guides/<slug>/<descriptive-name>.webp`), the download → webp → upload per image is
  independent and deterministic — fan out one Haiku subagent per image for guides with
  many illustrations. A batched Bash loop is fine for a few.
- **Never delegate the page composition** (Stage 3). Choosing components, section
  order, variants, and styling from the palette is the judgment core — it stays on the
  orchestrator (Opus).

---

## Shared scripted helpers

The deterministic backbone shared with `tron:toolkit-item` and `tron:news-item`
(repo guard, slug, the facilitron.com→relative link rewrite, internal-path
validation) plus the guide-card numbering is one wrapper:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" check-repo                          # marketing-pages guard (below)
bash "$C" slug "<title>"                       # the slug driving the .vue file + ImageKit folders
bash "$C" check-link /product/works            # verify an internal link before it 404s the prerender
# next free guide-card index (Stage 2) — feed the existing names in:
node "$IK" list --path guides --limit 50 | grep -oE 'guide-?[0-9]+\.webp' \
  | bash "$C" next-index --prefix guide --suffix .webp     # → {"ok":true,"next":"05"}
```

Each emits one JSON line. Smoke them with
`bash ${CLAUDE_PLUGIN_ROOT:-…}/tools/content/test-content.sh`. Page composition,
component choices, and card generation below stay judgment.

## Preflight — confirm you're in the marketing-pages repo

The `tron` plugin can be installed in any Facilitron repo, but this skill writes
marketing-pages pages (`pages/resources/guides/`). **Verify the checkout first and
stop if it doesn't match** — `content.sh check-repo` is the guard (worktrees of
marketing-pages still match — shared remote):

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh" check-repo \
  | grep -q '"isMarketingPages":true' \
  || echo "✋ NOT in the marketing-pages repo — switch to that checkout first."
```

If the guard fails, ask the user to switch to the marketing-pages checkout
before continuing — don't write files into the wrong repo.

## Stage 1 — Intake

Read the ticket and the Confluence draft.

```bash
acli jira workitem view <KEY> --json
```

The description's `inlineCard` attr holds the Confluence URL. Capture the target
keywords — they shape the title, the meta description, the H2s, and the TOC labels.

Fetch the page and its referenced images with this skill's bundled script (it
sources `~/.env`, writes the storage body and only the images the body references).
It's the same script `tron:news-item` uses — one shared copy lives in the plugin's
`tools/` dir, resolved via `CLAUDE_PLUGIN_ROOT` (falling back two levels up from the
skill's own `CLAUDE_SKILL_DIR`):

```bash
TOOLS="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools"   # plugin-level shared tools
"$TOOLS/confluence/fetch-confluence.sh" <confluence-url-or-page-id> /tmp/guide-<slug>
```

This writes `/tmp/guide-<slug>/body.html` and `/tmp/guide-<slug>/raw/<name>` per
referenced image, printing them in document order. Then hand `body.html` to a **Sonnet
subagent** for the storage→markdown transform (see Subagents). You compose the page
from the returned markdown + image map.

---

## Stage 2 — Images

Each image becomes a resized, slug-scoped webp uploaded to `guides/<slug>/`, plus an OG
image at `og/og-<slug>.webp` and an index card thumbnail at `guides/guide-<NN>.webp`. The
card thumbnail is **generated to match the existing index cards** (via `tron:gen-image`,
seeded with the current cards), not hand-picked.

Guide-specific naming, paths, and the OG/card destinations live in
[`reference/images.md`](reference/images.md); the shared convert → upload → verify
mechanics and the generate-from-references card workflow live in
[`../../tools/image/images-to-imagekit.md`](../../tools/image/images-to-imagekit.md).
Judgment that stays here: name each image descriptively (never the source filename),
reference body images by **relative provider path** (`guides/<slug>/<name>.webp`) and the OG
image as a full URL (Stage 3), and confirm names landed clean with
`node $IK list --path guides/<slug>`.

---

## Stage 3 — Compose the page

Create `pages/resources/guides/<slug>.vue`. Mirror an existing guide such as
`preventive-maintenance-strategy.vue` for the full pattern.

**This is the judgment core — do not delegate it.** Choosing components, section order,
variants, and styling from the palette is what keeps the orchestrator (Opus) on this stage.
Read the draft markdown + image map, then compose:

1. Open with the universal frame — hero, TOC, intro — then lay out 2–5 body sections that
   flex to the content, an optional pull quote and dark "at a glance" block, the mid-page
   CTA, conclusion, and FAQ.
2. Map each piece of draft content to the right component (prose → `BaseSection`, takeaways
   → `callout`, point lists → `alternative` grids, numbered processes → the timeline
   pattern, FAQs → `SectionAccordion`).
3. Wire `useDynamicMeta` with the title, keyword-rich description, route path, and the full
   OG URL. Keep every TOC `id` in sync with its `BaseSection id`, and use `tron-` tokens
   only — no arbitrary Tailwind values.

The full reference — section skeleton, the component palette with props, the
draft-to-component mapping, the `<script setup>` conventions, and the styling rules — lives
in [`reference/components.md`](reference/components.md). Follow it rather than re-reading
all four guides each time.

---

## Stage 4 — Register in the index

Guides are **not** auto-discovered. Append one entry to the `guides` array in
`pages/resources/guides/index.vue` (rendered via `LazyDisplayCard`):

```ts
{
  title: "<Guide title>",
  description: "<short card description>",
  image: "guides/guide-<NN>.webp",   // the card thumbnail uploaded in Stage 2
  imageAlt: "",
  link: "/resources/guides/<slug>",
}
```

`<NN>` is the next free number after the existing entries. The `image` is the flat
`guides/guide-NN.webp` thumbnail (provider path), distinct from the `guides/<slug>/`
body-image folder.

---

## Stage 5 — Verify & clean up

1. **Renders in this worktree's dev server.** Guides are real routes (not the catch-all),
   so a missing file is a hard 404 — but still confirm you're hitting THIS worktree's
   server (ports 4001/4002 are often bound by siblings). Grep the served HTML, not the
   status code:
   ```bash
   URL=http://localhost:<port>/resources/guides/<slug>
   curl -s "$URL" | grep -oE '<title>[^<]*</title>'     # must contain the guide title
   curl -s "$URL" | grep -oc 'guides/<slug>'            # > 0 — body image srcs present
   ```
   If it's the wrong server, start this worktree's on a free port (see the `tron:news-item`
   skill's Stage 4 for the exact dev-server incantation). Have the user confirm the hero,
   TOC anchors, all sections, images, and FAQ render.
2. **Index card** — load `/resources/guides`, confirm the new card shows with its
   thumbnail and links to the guide.
3. **Images resolve** — spot-check `https://ik.imagekit.io/facilitron/guides/<slug>/<name>.webp`
   and the OG `…/og/og-<slug>.webp`.
4. **Links** — lint internal links in the new page; convert any
   `https://www.facilitron.com/...` to relative paths and confirm each target exists
   (`find pages -type f -name "*.vue" | grep -i <keyword>`). Watch the known trap:
   `/product/scheduling-and-reservations/` has no index — use
   `/product/facilitron-scheduling-and-reservations`.
5. **Prose & a11y** — before publish, offer `tron:prose-lint` on the copy and
   `tron:a11y-scan` against the rendered guide route (new pages should clear the WCAG gate).
6. **Clean up** — remove the dropped-in sources and `/tmp/guide-<slug>`. Only the new
   `.vue` page and the `index.vue` edit should end up tracked.

### Verification loop (validate → fix → repeat)

Quality is iterative, not one-shot. Run this loop until it comes back clean before you
call the guide done:

1. **Validate.** Render the route (Stage 5 step 1), then run `tron:prose-lint` on the copy
   and `tron:a11y-scan` against the rendered guide. Re-grep the page source for em dashes
   (`grep -n '—' pages/resources/guides/<slug>.vue`) — Facilitron voice has **no em
   dashes** in produced copy.
2. **Fix.** Address each finding at its source: rewrite em dashes to commas, periods, or
   "to" ranges; supply real `alt` text for any image flagged by a11y; tighten vague or
   off-brand prose.
3. **Repeat.** Re-run the same checks. Don't stop at the first pass — fixes can introduce
   new findings (a reworded sentence can reintroduce a dash). Loop until prose-lint,
   a11y-scan, and the em-dash grep all come back empty.

## Common pitfalls

- **Using `::fImg`/`::image-text` or markdown** — those are content-collection (news)
  components. Guides are Vue: use `<NuxtImg provider="imagekit">` and the palette above.
- **Forgetting the index entry** — the page works at its URL but never appears on
  `/resources/guides`. Always do Stage 4.
- **TOC anchor mismatch** — a `tocItems` `id` that doesn't match a `BaseSection id`
  scrolls nowhere. Keep them in sync; add `scroll-mt-36` so the sticky nav doesn't cover
  the heading.
- **Body image referenced by full URL** — use the relative provider path
  (`guides/<slug>/<name>.webp`); only the OG image is a full URL.
- **Duplicate H1** — the hero already renders the title; don't open the body with `#`.
- **`content/QuoteSimple.vue` instead of `section/QuoteSimple.vue`** — the content one
  lacks `backgroundColor`/`borderBottom`/`image`. Use `<SectionQuoteSimple>`.
- **Arbitrary Tailwind values** — `bg-[#…]`/`w-[…]` violate the design system. Add a
  `tron-` token to `tailwind.config.ts` if a needed color is missing.

## Reference: working example

`pages/resources/guides/preventive-maintenance-strategy.vue` is the cleanest end-to-end
example — hero + TOC, `v-for` data arrays (`tocItems`, `faqItems`, `implementationSteps`,
`comparisonTable`), the timeline pattern, the dark section, the mid-page CTA, and the
`useDynamicMeta` call with an OG image.
